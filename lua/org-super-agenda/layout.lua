-- org-super-agenda.layout ----------------------------------------------------
local utils   = require('org-super-agenda.utils')
local hi      = require('org-super-agenda.highlight')
local get_cfg = require('org-super-agenda.config').get
local L       = {}

local function prefix(it, cfg)
  local indent = string.rep(' ', it.level)
  local pri    = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
  local parts  = {
    filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
    todo     = it.todo_state,
    priority = pri,
    headline = utils.truncate(it.headline, cfg.heading_max_length),
  }
  local order  = vim.deepcopy(cfg.heading_order or { 'filename', 'todo', 'priority', 'headline' })
  local tok    = {}

  if parts.filename and order[1] == 'filename' then
    table.insert(tok, '[' .. parts.filename .. ']')
    table.remove(order, 1)
  end
  for _, k in ipairs(order) do
    if parts[k] and parts[k] ~= '' then table.insert(tok, parts[k]) end
  end
  return indent .. table.concat(tok, ' ')
end

-- public --------------------------------------------------------------------
---@return rows, hls, line_map
function L.build(groups, win_width)
  local cfg       = get_cfg()
  local rows, hls = {}, {}
  local line_map  = {}
  local widest    = 0

  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      widest = math.max(widest, #prefix(it, cfg))
    end
  end
  widest = widest + 1

  local ln = 0
  local function emit(s)
    ln = ln + 1; rows[ln] = s; return ln
  end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(string.format(cfg.group_format or '* %s', grp.name))
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      for _, it in ipairs(grp.items) do
        local indent      = string.rep(' ', it.level)
        local pri         = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil

        local sched_label = cfg.short_date_labels and 'S' or 'SCHEDULED'
        local dead_label  = cfg.short_date_labels and 'D' or 'DEADLINE'
        local meta        = {}
        if it.scheduled then meta[#meta + 1] = sched_label .. ': <' .. tostring(it.scheduled) .. '>' end
        if it.deadline then meta[#meta + 1] = dead_label .. ':  <' .. tostring(it.deadline) .. '>' end
        local meta_str = table.concat(meta, ' ')

        -- Prefix + Highlight‑Spans --------------------------------------
        local parts    = {
          filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
          todo     = it.todo_state,
          priority = pri,
          headline = utils.truncate(it.headline, cfg.heading_max_length),
        }
        local order    = vim.deepcopy(cfg.heading_order or { 'filename', 'todo', 'priority', 'headline' })
        local col      = #indent
        local spans    = {}
        local text     = indent

        local function push(field, txt)
          if not txt or txt == '' then return end
          if #text > 0 and text:sub(-1) ~= ' ' then text, col = text .. ' ', col + 1 end
          local s = col
          text, col = text .. txt, col + #txt
          spans[#spans + 1] = { field = field, s = s, e = col }
        end

        if parts.filename and order[1] == 'filename' then
          push('filename', '[' .. parts.filename .. ']'); table.remove(order, 1)
        end
        for _, k in ipairs(order) do push(k, parts[k]) end

        if cfg.inline_dates and meta_str ~= '' then
          if #text < widest then
            text, col = text .. string.rep(' ', widest - #text), widest
          else
            text, col = text .. ' ', col + 1
          end
          local ms = col
          text, col = text .. meta_str, col + #meta_str
          spans[#spans + 1] = { field = 'date', s = ms, e = col }
        end

        if cfg.show_tags and it.tags and #it.tags > 0 then
          local tag   = ':' .. table.concat(it.tags, ':') .. ':'
          local start = win_width - #tag - 1
          if #text + 1 < start then
            text = text .. string.rep(' ', start - #text) .. tag
          else
            text = text .. ' ' .. tag
          end
          spans[#spans + 1] = { field = 'tags', s = #text - #tag, e = #text }
        end

        local lnum = emit(text)
        line_map[lnum] = it

        local hl_cfg = hi.group(it.todo_state)
        for _, sp in ipairs(spans) do
          if hi.want(it.todo_state, sp.field) then
            hls[#hls + 1] = { lnum - 1, sp.s, sp.e, hl_cfg }
          end
        end

        if not cfg.inline_dates and meta_str ~= '' then
          local mln = emit(indent .. '  ' .. meta_str)
          if hi.want(it.todo_state, 'date') then
            hls[#hls + 1] = { mln - 1, #indent + 2, -1, hl_cfg }
          end
        end
      end
    end
  end
  return rows, hls, line_map
end

return L
