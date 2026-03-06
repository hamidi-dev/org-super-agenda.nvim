-- core/layout/classic.lua -- pure rows/hls/line_map
local L = {}

local function truncate(str, len)
  if not len or #str <= len then
    return str
  end
  return str:sub(1, len)
end

local function classic_prefix(it, cfg)
  local indent = '  ' .. string.rep(' ', it.level or 0)
  local pri = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
  local parts = {
    filename = (cfg.show_filename and it.file) and (it.file:match('[^/]+$') or ''):gsub('%.org$', ''),
    todo = it.todo_state,
    priority = pri,
    headline = truncate(it.headline or '', cfg.heading_max_length),
  }
  -- append “ …” if item has more content/subheadings
  if it.has_more then
    parts.headline = (parts.headline or '') .. ' …'
  end

  local order = vim.deepcopy(cfg.classic.heading_order or { 'filename', 'todo', 'priority', 'headline' })
  local tok = {}
  if parts.filename and order[1] == 'filename' then
    table.insert(tok, '[' .. parts.filename .. ']')
    table.remove(order, 1)
  end
  for _, k in ipairs(order) do
    if parts[k] and parts[k] ~= '' then
      table.insert(tok, parts[k])
    end
  end
  return indent .. table.concat(tok, ' ')
end

local MARK_GLYPH = '● '
local CLOCK_GLYPH = '⏱ '

local function item_key(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

local function header_label(cfg, grp)
  local n = #grp.items
  local count = string.format('%d %s', n, (n == 1) and 'item' or 'items')
  return string.format((cfg.group_format or '* %s') .. ' (%s)', grp.name, count)
end

function L.build(groups, win_width, cfg, marked)
  local rows, hls, line_map = {}, {}, {}
  local widest = 0
  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      widest = math.max(widest, #classic_prefix(it, cfg))
    end
  end
  widest = widest + 1

  local ln = 0
  local function emit(s)
    ln = ln + 1
    rows[ln] = s
    return ln
  end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(header_label(cfg, grp))
      line_map[hdln] = { _kind = 'group_header', group_name = grp.name }
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      if not grp.collapsed then
        for _, it in ipairs(grp.items) do
          local is_marked = marked and marked[item_key(it)]
          local clock_pfx = it.clocked_in and CLOCK_GLYPH or ''
          local indent = (is_marked and MARK_GLYPH or '  ') .. clock_pfx .. string.rep(' ', it.level or 0)
          local pri = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
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

          local parts = {
            filename = (cfg.show_filename and it.file) and (it.file:match('[^/]+$') or ''):gsub('%.org$', ''),
            todo = it.todo_state,
            priority = pri,
            headline = truncate(it.headline or '', cfg.heading_max_length),
          }
          if it.has_more then
            parts.headline = (parts.headline or '') .. ' …'
          end

          local order = vim.deepcopy(cfg.classic.heading_order or { 'filename', 'todo', 'priority', 'headline' })
          local col = #indent
          local spans, text = {}, indent

          local function push(field, txt)
            if not txt or txt == '' then
              return
            end
            if #text > 0 and text:sub(-1) ~= ' ' then
              text, col = text .. ' ', col + 1
            end
            local s = col
            text, col = text .. txt, col + #txt
            spans[#spans + 1] = { field = field, s = s, e = col, state = it.todo_state }
          end

          if parts.filename and order[1] == 'filename' then
            push('filename', '[' .. parts.filename .. ']')
            table.remove(order, 1)
          end
          for _, k in ipairs(order) do
            push(k, parts[k])
          end

          if cfg.classic.inline_dates and meta_str ~= '' then
            if #text < widest then
              text, col = text .. string.rep(' ', widest - #text), widest
            else
              text, col = text .. ' ', col + 1
            end
            local ms = col
            text, col = text .. meta_str, col + #meta_str
            spans[#spans + 1] = { field = 'date', s = ms, e = col, state = it.todo_state }
          end

          if cfg.show_tags and it.tags and #it.tags > 0 then
            local tag = ':' .. table.concat(it.tags, ':') .. ':'
            local start = win_width - #tag - 1
            if #text + 1 < start then
              text = text .. string.rep(' ', start - #text) .. tag
            else
              text = text .. ' ' .. tag
            end
            spans[#spans + 1] = { field = 'tags', s = #text - #tag, e = #text, state = it.todo_state }
          end

          local lnum = emit(text)
          line_map[lnum] = it

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
            local mln = emit(indent .. '  ' .. meta_str)
            hls[#hls + 1] = { mln - 1, #indent + 2, -1, nil, field = 'date', state = it.todo_state }
          end
        end
      end
    end
  end

  return rows, hls, line_map
end

return L
