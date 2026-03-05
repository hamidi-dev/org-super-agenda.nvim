-- app/store.lua -- single source of truth
local Store = {
  state = {
    opts = {},
    cursor = nil,
    hidden = {},
    marked = {},            -- items marked for bulk actions (key -> true)
    last_marked = {},       -- snapshot of marks before last clear (for gv restore)
    view_mode = nil,        -- set from config on Services.setup
    undo_stack = {},
    allow_duplicates = false,
    sticky_done = {},       -- items turned DONE during this session (keep visible)
    fullscreen = false,
    collapsed_groups = {},  -- group_name -> true when collapsed
    active_view = nil,      -- resolved custom view or nil for default
    active_view_key = nil,  -- key name of the active custom view
  }
}

function Store.get() return Store.state end
function Store.set_opts(opts) Store.state.opts = opts or {} end
function Store.set_cursor(cur) Store.state.cursor = cur end
function Store.toggle_dupes() Store.state.allow_duplicates = not Store.state.allow_duplicates end
function Store.set_view_mode(m) Store.state.view_mode = m or 'classic' end
function Store.set_fullscreen(v) Store.state.fullscreen = v == true end
function Store.hide(key) Store.state.hidden[key] = true end
function Store.reset_hidden() Store.state.hidden = {} end

function Store.is_group_collapsed(name)
  return Store.state.collapsed_groups[name] == true
end

function Store.toggle_group(name)
  if not name or name == '' then return end
  if Store.state.collapsed_groups[name] then
    Store.state.collapsed_groups[name] = nil
  else
    Store.state.collapsed_groups[name] = true
  end
end

function Store.fold_groups(names)
  for _, name in ipairs(names or {}) do
    if type(name) == 'string' and name ~= '' then
      Store.state.collapsed_groups[name] = true
    end
  end
end

function Store.unfold_all_groups()
  Store.state.collapsed_groups = {}
end

function Store.mark_toggle(key)
  if Store.state.marked[key] then Store.state.marked[key] = nil
  else Store.state.marked[key] = true end
end
function Store.mark_clear()
  -- snapshot current marks before clearing (for gv restore)
  if next(Store.state.marked) then
    Store.state.last_marked = vim.deepcopy(Store.state.marked)
  end
  Store.state.marked = {}
end
function Store.is_marked(key) return Store.state.marked[key] == true end
function Store.get_marked()
  local t = {}
  for k in pairs(Store.state.marked) do t[#t+1] = k end
  return t
end
function Store.mark_restore_last()
  if next(Store.state.last_marked) then
    Store.state.marked = vim.deepcopy(Store.state.last_marked)
    return true
  end
  return false
end

function Store.set_active_view(resolved, key)
  Store.state.active_view = resolved
  Store.state.active_view_key = key
end

function Store.clear_active_view()
  Store.state.active_view = nil
  Store.state.active_view_key = nil
end

function Store.get_active_view() return Store.state.active_view end
function Store.get_active_view_key() return Store.state.active_view_key end

function Store.push_undo(fn) table.insert(Store.state.undo_stack, fn) end
function Store.pop_undo()
  local f = table.remove(Store.state.undo_stack)
  if f then pcall(f) end
end

-- sticky DONE tracking (visible until float closes)
function Store.sticky_add(key) Store.state.sticky_done[key] = true end
function Store.sticky_remove(key) Store.state.sticky_done[key] = nil end
function Store.sticky_has(key) return Store.state.sticky_done[key] == true end
function Store.sticky_reset() Store.state.sticky_done = {} end

return Store
