-- core/layout/compact.lua -- pure rows/hls/line_map
local L = {}

local function truncate(str, len) if not len or #str <= len then return str end return str:sub(1, len) end

local function build_labels(it)
  local labels = {}
  if it.deadline then
    local d = it.deadline:days_from_today()
    local lab = (d < 0) and string.format('%d d. ago:', math.abs(d))
        or (d == 0) and 'today:'
        or string.format('in %d d.:', d)
    table.insert(labels, { sev = (d < 0) and 1000 + math.abs(d) or 500 - d, txt = lab })
  end
  if it.scheduled then
    local d = it.scheduled:days_from_today()
    local lab = (d < 0) and string.format('Sched. %dx:', math.abs(d))
        or (d == 0) and 'Sched. today:'
        or string.format('Sched. in %d d.:', d)
    table.insert(labels, { sev = (d < 0) and 900 + math.abs(d) or 400 - d, txt = lab })
  end
  table.sort(labels, function(a, b) return a.sev > b.sev end)
  local parts = {}
  for _, l in ipairs(labels) do parts[#parts+1] = l.txt end
  return table.concat(parts, '  ')
end

function L.build(groups, win_width, cfg)
  local rows, hls, line_map = {}, {}, {}
  local fname_w   = cfg.compact and cfg.compact.filename_min_width or 8
  local label_w   = cfg.compact and cfg.compact.label_min_width or 12

  for _, grp in ipairs(groups) do
    for _, it in ipairs(grp.items) do
      local name = ((it.file or ''):match('[^/]+$') or ''):gsub('%.org$', '') .. ':'
      if #name > fname_w then fname_w = #name end
    end
  end

  local ln = 0
  local function emit(s) ln = ln + 1; rows[ln] = s; return ln end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(string.format(cfg.group_format or '* %s', grp.name))
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      for _, it in ipairs(grp.items) do
        local name = (((it.file or ''):match('[^/]+$') or ''):gsub('%.org$', '') .. ':')
        local label = build_labels(it)
        if label == '' then label = string.rep(' ', label_w) else label = string.format('%-' .. label_w .. 's', label) end
        local pri   = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
        local todo  = it.todo_state or ''
        local head  = truncate(it.headline or '', cfg.heading_max_length)

        local text, spans = '', {}
        local s_fn  = #text; text = text .. string.format('%-' .. fname_w .. 's', name); spans[#spans+1] = {field='filename', s=s_fn, e=#text, state=it.todo_state}
        local s_lab = #text; text = text .. label; spans[#spans+1] = {field='date', s=s_lab, e=#text, state=it.todo_state}
        text = text .. ' '
        local s_todo = #text; text = text .. todo; spans[#spans+1] = {field='todo', s=s_todo, e=#text, state=it.todo_state}
        if pri then text = text .. ' '; local s_pr = #text; text = text .. pri; spans[#spans+1] = {field='priority', s=s_pr, e=#text, state=it.todo_state} end
        text = text .. ' '
        local s_head = #text; text = text .. head; spans[#spans+1] = {field='headline', s=s_head, e=#text, state=it.todo_state}

        if cfg.show_tags and it.tags and #it.tags > 0 then
          local tag = ':' .. table.concat(it.tags, ':') .. ':'
          local start = win_width - #tag - 1
          if #text + 1 < start then text = text .. string.rep(' ', start - #text) .. tag else text = text .. ' ' .. tag end
          spans[#spans + 1] = { field = 'tags', s = #text - #tag, e = #text, state=it.todo_state }
        end

        local lnum = emit(text); line_map[lnum] = it
        for _, sp in ipairs(spans) do
          hls[#hls + 1] = { lnum - 1, sp.s, sp.e, nil, field=sp.field, state=it.todo_state }
        end
      end
    end
  end

  return rows, hls, line_map
end

return L

