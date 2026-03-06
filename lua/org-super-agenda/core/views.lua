-- core/views.lua -- custom view resolution
local Q = require('org-super-agenda.core.query')

local V = {}

function V.resolve(view_def)
  if not view_def then
    return nil
  end
  local resolved = {
    name = view_def.name or 'Custom View',
    filter = nil,
    groups = view_def.groups,
    sort = view_def.sort,
    title = view_def.title,
    view_mode = view_def.view_mode,
  }
  if view_def.filter and view_def.filter ~= '' then
    resolved.filter = Q.parse(view_def.filter)
    resolved.filter_raw = view_def.filter
  end
  return resolved
end

function V.list(custom_views)
  if not custom_views or type(custom_views) ~= 'table' then
    return {}
  end
  local out = {}
  for key, def in pairs(custom_views) do
    out[#out + 1] = {
      key = key,
      name = def.name or key,
      keymap = def.keymap,
      filter = def.filter or '',
    }
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function V.apply_filter(items, resolved_view)
  if not resolved_view or not resolved_view.filter then
    return items
  end
  local t = {}
  for _, it in ipairs(items) do
    if resolved_view.filter.matches(it) then
      t[#t + 1] = it
    end
  end
  return t
end

return V
