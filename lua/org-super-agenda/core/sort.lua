-- core/sort.lua -- item sorting helpers
local Date = require('org-super-agenda.core.date')

local S = {}

local function prio_rank(p) return ({ A=3, B=2, C=1 })[p or ''] or 0 end

local function todo_rank_factory(cfg)
  local rank, i = {}, 1
  for _, st in ipairs(cfg.todo_states or {}) do rank[st.name] = i; i = i + 1 end
  return function(state) return rank[state or ''] or 999 end
end

local key_getters = {
  date_nearest = function(it)
    local d1 = it.deadline  and it.deadline:days_from_today()
    local d2 = it.scheduled and it.scheduled:days_from_today()
    if d1 and d2 then return math.min(d1, d2) end
    return d1 or d2 or math.huge
  end,
  deadline  = function(it) return it.deadline  and it.deadline:days_from_today()  or math.huge end,
  scheduled = function(it) return it.scheduled and it.scheduled:days_from_today() or math.huge end,
  deadline_time  = function(it) return it.deadline  and it.deadline:to_time()  or math.huge end,
  scheduled_time = function(it) return it.scheduled and it.scheduled:to_time() or math.huge end,
  priority  = function(it) return prio_rank(it.priority) end,
  todo      = function(_, ranker) return function(it) return ranker(it.todo_state) end end,
  filename  = function(it) return (it.file or ''):match('[^/]+$') or '' end,
  headline  = function(it) return (it.headline or ''):lower() end,
}

local function cmp_with_order(a, b, asc)
  if a == b then return false end
  if asc then return a < b else return a > b end
end

-- spec: { by = 'deadline'|'scheduled'|'deadline_time'|'scheduled_time'|'priority'|'todo'|'filename'|'headline'|'date_nearest',
--         order = 'asc'|'desc' }
function S.sort_items(items, spec, cfg)
  spec = spec or {}
  local by    = (spec.by or (cfg.group_sort and cfg.group_sort.by)) or 'date_nearest'
  local order = (spec.order or (cfg.group_sort and cfg.group_sort.order)) or 'asc'
  local asc   = order ~= 'desc'

  local getter = key_getters[by]
  if not getter then return items end

  local todo_rank = todo_rank_factory(cfg)
  local keyf = (by == 'todo') and getter(nil, todo_rank) or getter

  table.sort(items, function(a, b)
    local ka, kb = keyf(a), keyf(b)
    -- Tie-breakers: higher priority first, then filename, then headline
    if ka == kb then
      local pa, pb = prio_rank(a.priority), prio_rank(b.priority)
      if pa ~= pb then return pa > pb end
      local fa, fb = key_getters.filename(a), key_getters.filename(b)
      if fa ~= fb then return fa < fb end
      local ha, hb = key_getters.headline(a), key_getters.headline(b)
      return ha < hb
    end
    return cmp_with_order(ka, kb, asc)
  end)

  return items
end

return S

