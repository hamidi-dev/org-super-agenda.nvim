-- core/group.lua -- pure grouping
local G = {}

function G.group_items(raw, spec)
  local groups_spec    = spec.groups or {}
  local allow_dupes    = spec.allow_duplicates
  local hide_empty     = spec.hide_empty
  local show_other     = spec.show_other
  local other_name     = spec.other_name or 'Other'

  local list, map = {}, {}
  for _, g in ipairs(groups_spec) do
    local entry = { name = g.name, items = {}, sort = g.sort }
    list[#list+1] = entry
    map[g.name] = entry
  end

  local other -- catch-all
  if show_other then
    other = { name = other_name, items = {} }
    list[#list+1] = other
  end

  for _, it in ipairs(raw) do
    local placed = 0
    for _, g in ipairs(groups_spec) do
      if g.matcher(it) then
        map[g.name].items[#map[g.name].items+1] = it
        placed = placed + 1
        if not allow_dupes then break end
      end
    end
    -- IMPORTANT: DO NOT send DONE into "Other"
    if placed == 0 and other and (it.todo_state ~= 'DONE') then
      other.items[#other.items+1] = it
    end
  end

  if hide_empty then
    local filtered = {}
    for _, grp in ipairs(list) do
      if #grp.items > 0 then filtered[#filtered+1] = grp end
    end
    list = filtered
  end

  return list
end

return G

