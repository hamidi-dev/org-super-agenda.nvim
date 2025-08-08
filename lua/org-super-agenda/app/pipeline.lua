-- app/pipeline.lua -- pure orchestration => returns a producer(win_width)->rows,hls,line_map
local filter = require('org-super-agenda.core.filter')
local group  = require('org-super-agenda.core.group')
local layout_classic = require('org-super-agenda.core.layout.classic')
local layout_compact = require('org-super-agenda.core.layout.compact')

local Pipeline = {}

local function key_of(it) return string.format('%s:%s', it.file or '', it._src_line or 0) end

function Pipeline.run(source, cfg, state)
  local items = source.collect()

  -- apply hidden
  if next(state.hidden) then
    local t = {}
    for _, it in ipairs(items) do
      if not state.hidden[key_of(it)] then t[#t+1] = it end
    end
    items = t
  end

  -- filters
  items = filter.apply(items, state.opts, cfg)

  -- grouping (excludes DONE from "Other" by design)
  local groups = group.group_items(items, {
    groups = cfg.groups,
    allow_duplicates = state.allow_duplicates,
    hide_empty = cfg.hide_empty_groups,
    show_other = cfg.show_other_group,
    other_name = cfg.other_group_name,
  })

  -- "sticky" DONE items (turned DONE during this session) stay visible
  -- in a dedicated group until the float is closed.
  local sticky = {}
  for _, it in ipairs(items) do
    if it.todo_state == 'DONE' and state.sticky_done[key_of(it)] then
      sticky[#sticky+1] = it
    end
  end
  if #sticky > 0 then
    groups[#groups+1] = { name = '✅ Done (this session)', items = sticky }
  end

  -- choose layout
  local layout = (state.view_mode == 'compact') and layout_compact or layout_classic

  return function(win_width)
    return layout.build(groups, win_width, cfg)
  end
end

return Pipeline

