-- core/layout/tree.lua -- pure rows/hls/line_map; hierarchical (parent → subtask) rendering
local L = {}

local function truncate(str, len)
  if not len or #str <= len then
    return str
  end
  return str:sub(1, len)
end

local function file_stem(path)
  local p = (path or ''):gsub('\\', '/')
  local base = p:match('[^/]+$') or ''
  return base:gsub('%.org$', '')
end

local MARK_GLYPH = '● '
local CLOCK_GLYPH = '⏱ '
local BRANCH_MID = '├─ '
local BRANCH_LAST = '└─ '
local BAR_CONT = '│  '
local BAR_NONE = '   '

local function dwidth(s)
  return vim.fn.strdisplaywidth(s)
end

local function item_key(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

local function header_label(cfg, grp)
  local n = #grp.items
  local count = string.format('%d %s', n, (n == 1) and 'item' or 'items')
  return string.format((cfg.group_format or '* %s') .. ' (%s)', grp.name, count)
end

-- Build a forest from one group's items using each item's `parents` chain
-- (nearest ancestor first). An item nests under the closest ancestor that is
-- itself part of the group; when `show_ghosts` is set, ancestors that are NOT
-- part of the group are inserted as dimmed context nodes so the hierarchy
-- stays readable (e.g. subtasks scheduled today under an unscheduled project).
local function build_forest(items, show_ghosts)
  local nodes, roots, ghosts = {}, {}, {}
  for _, it in ipairs(items) do
    nodes[item_key(it)] = { item = it, children = {} }
  end

  local resolve
  local function ghost_node(anc, rest)
    if ghosts[anc.key] then
      return ghosts[anc.key]
    end
    local node = {
      item = {
        _ghost = true,
        headline = anc.headline,
        todo_state = anc.todo_state,
        level = anc.level,
        file = anc.file,
        _src_line = anc._src_line,
      },
      children = {},
      ghost = true,
    }
    ghosts[anc.key] = node
    local parent = resolve(rest)
    if parent then
      parent.children[#parent.children + 1] = node
    else
      roots[#roots + 1] = node
    end
    return node
  end

  -- parents: remaining ancestor chain, nearest first -> parent node or nil (root)
  resolve = function(parents)
    for i, anc in ipairs(parents or {}) do
      if nodes[anc.key] then
        return nodes[anc.key]
      end
      if show_ghosts then
        return ghost_node(anc, vim.list_slice(parents, i + 1, #parents))
      end
    end
    return nil
  end

  for _, it in ipairs(items) do
    local node = nodes[item_key(it)]
    local parent = resolve(it.parents)
    if parent then
      parent.children[#parent.children + 1] = node
    else
      roots[#roots + 1] = node
    end
  end
  return roots
end

-- Depth-first flatten; each entry carries its branch prefix ("│  └─ ") and
-- the continuation prefix ("│     ") used for wrapped meta lines below it.
local function flatten(forest)
  local out = {}
  local function visit(node, branch, cont)
    out[#out + 1] = { node = node, branch = branch, cont = cont }
    for i, c in ipairs(node.children) do
      local last = (i == #node.children)
      visit(c, cont .. (last and BRANCH_LAST or BRANCH_MID), cont .. (last and BAR_NONE or BAR_CONT))
    end
  end
  for _, r in ipairs(forest) do
    visit(r, '', '')
  end
  return out
end

local function build_parts(it, cfg, has_visible_children)
  local pri = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
  local parts = {
    filename = (cfg.show_filename and it.file) and file_stem(it.file),
    todo = it.todo_state,
    priority = pri,
    headline = truncate(it.headline or '', cfg.heading_max_length),
  }
  -- "…" only when the extra content is not already visible as subtasks
  if it.has_more and not has_visible_children then
    parts.headline = (parts.headline or '') .. ' …'
  end
  return parts
end

local function tokens(it, cfg, has_visible_children)
  local parts = build_parts(it, cfg, has_visible_children)
  local order = vim.deepcopy(cfg.classic.heading_order or { 'filename', 'todo', 'priority', 'headline' })
  local tok = {}
  if parts.filename and order[1] == 'filename' then
    tok[#tok + 1] = { field = 'filename', txt = '[' .. parts.filename .. ']' }
    table.remove(order, 1)
  end
  for _, k in ipairs(order) do
    if parts[k] and parts[k] ~= '' then
      tok[#tok + 1] = { field = k, txt = parts[k] }
    end
  end
  return tok
end

function L.build(groups, win_width, cfg, marked)
  local rows, hls, line_map = {}, {}, {}
  local show_ghosts = not (cfg.tree and cfg.tree.show_ghost_parents == false)

  local flat = {}
  for gi, g in ipairs(groups) do
    flat[gi] = flatten(build_forest(g.items, show_ghosts))
  end

  -- widest prefix (display width) across all groups for inline date alignment
  local widest = 0
  for _, entries in ipairs(flat) do
    for _, e in ipairs(entries) do
      if not e.node.ghost then
        local tok = {}
        for _, t in ipairs(tokens(e.node.item, cfg, #e.node.children > 0)) do
          tok[#tok + 1] = t.txt
        end
        widest = math.max(widest, dwidth('  ' .. e.branch .. table.concat(tok, ' ')))
      end
    end
  end
  widest = widest + 1

  local ln = 0
  local function emit(s)
    ln = ln + 1
    rows[ln] = s
    return ln
  end

  for gi, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(header_label(cfg, grp))
      line_map[hdln] = { _kind = 'group_header', group_name = grp.name }
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      if not grp.collapsed then
        for _, entry in ipairs(flat[gi]) do
          local node, it = entry.node, entry.node.item

          if node.ghost then
            local indent = '  '
            local text = indent .. entry.branch
            local branch_s, branch_e = #indent, #text
            local label = (it.todo_state and it.todo_state ~= '' and (it.todo_state .. ' ') or '') .. (it.headline or '')
            local lnum = emit(text .. label)
            line_map[lnum] = it
            if branch_e > branch_s then
              hls[#hls + 1] = { lnum - 1, branch_s, branch_e, 'OrgSA_TreeConnector' }
            end
            hls[#hls + 1] = { lnum - 1, branch_e, -1, 'OrgSA_TreeGhost' }
          else
            local is_marked = marked and marked[item_key(it)]
            local clock_pfx = it.clocked_in and CLOCK_GLYPH or ''
            local indent = (is_marked and MARK_GLYPH or '  ') .. clock_pfx
            local text = indent .. entry.branch
            local branch_s, branch_e = #indent, #text

            local spans = {}
            local function push(field, txt)
              if not txt or txt == '' then
                return
              end
              if #text > 0 and text:sub(-1) ~= ' ' then
                text = text .. ' '
              end
              local s = #text
              text = text .. txt
              spans[#spans + 1] = { field = field, s = s, e = #text, state = it.todo_state }
            end

            for _, t in ipairs(tokens(it, cfg, #node.children > 0)) do
              push(t.field, t.txt)
            end

            local sched_label = cfg.classic.short_date_labels and 'S' or 'SCHEDULED'
            local dead_label = cfg.classic.short_date_labels and 'D' or 'DEADLINE'
            local meta = {}
            if it.scheduled then
              meta[#meta + 1] = sched_label .. ': <' .. tostring(it.scheduled) .. '>'
            end
            if it.deadline then
              meta[#meta + 1] = dead_label .. ':  <' .. tostring(it.deadline) .. '>'
            end
            local meta_str = table.concat(meta, ' ')

            if cfg.classic.inline_dates and meta_str ~= '' then
              local w = dwidth(text)
              text = text .. string.rep(' ', math.max(widest - w, 1))
              local ms = #text
              text = text .. meta_str
              spans[#spans + 1] = { field = 'date', s = ms, e = #text, state = it.todo_state }
            end

            if cfg.show_tags and it.tags and #it.tags > 0 then
              local tag = ':' .. table.concat(it.tags, ':') .. ':'
              local start = win_width - dwidth(tag) - 1
              local w = dwidth(text)
              if w + 1 < start then
                text = text .. string.rep(' ', start - w) .. tag
              else
                text = text .. ' ' .. tag
              end
              spans[#spans + 1] = { field = 'tags', s = #text - #tag, e = #text, state = it.todo_state }
            end

            local lnum = emit(text)
            line_map[lnum] = it

            if branch_e > branch_s then
              hls[#hls + 1] = { lnum - 1, branch_s, branch_e, 'OrgSA_TreeConnector' }
            end
            for _, sp in ipairs(spans) do
              hls[#hls + 1] = { lnum - 1, sp.s, sp.e, nil, field = sp.field, state = sp.state }
            end
            if is_marked then
              hls[#hls + 1] = { lnum - 1, 0, #MARK_GLYPH, 'OrgSA_Marked', field = 'mark', state = it.todo_state }
            end
            if it.clocked_in then
              local cstart = is_marked and #MARK_GLYPH or 2
              hls[#hls + 1] = { lnum - 1, cstart, cstart + #CLOCK_GLYPH, 'OrgSA_Clock', field = 'clock', state = it.todo_state }
            end

            if not cfg.classic.inline_dates and meta_str ~= '' then
              local cont = '  ' .. entry.cont
              local mln = emit(cont .. '  ' .. meta_str)
              if #entry.cont > 0 then
                hls[#hls + 1] = { mln - 1, 2, #cont, 'OrgSA_TreeConnector' }
              end
              hls[#hls + 1] = { mln - 1, #cont + 2, -1, nil, field = 'date', state = it.todo_state }
            end
          end
        end
      end
    end
  end

  return rows, hls, line_map
end

return L
