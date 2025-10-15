-- app/services.lua -- thin imperative shell around pipeline & view
local Services = { agenda = {}, refile = {} }

local store, source, view, pipeline
local function cfg()
  return require('org-super-agenda.config').get()
end

function Services.setup(deps)
  store = deps.store
  source = deps.source
  view = deps.view
  pipeline = deps.pipeline
  store.set_view_mode(cfg().view_mode or 'classic')
end

local function render(cursor, opts, reuse)
  if opts and opts.fullscreen ~= nil then
    store.set_fullscreen(opts.fullscreen)
  end
  local view_opts = { fullscreen = store.get().fullscreen }

  if opts then
    local s = store.get()
    if opts.todo_filter == nil then
      s.opts.todo_filter = nil
    end
    if opts.headline_filter == nil then
      s.opts.headline_filter = nil
    end
    if opts.headline_fuzzy == nil then
      s.opts.headline_fuzzy = nil
    end
    if opts.query == nil then
      s.opts.query = nil
    end
    local state_opts = vim.tbl_deep_extend('force', s.opts or {}, {
      todo_filter = opts.todo_filter,
      headline_filter = opts.headline_filter,
      headline_fuzzy = opts.headline_fuzzy,
      query = opts.query,
    })
    store.set_opts(state_opts)
  end
  if cursor then
    store.set_cursor(cursor)
  end

  local s = store.get()
  local producer = pipeline.run(source, cfg(), s)
  if reuse and view.is_open() then
    view.update(producer, s.cursor, s.view_mode, view_opts)
  else
    view.render(producer, s.cursor, s.view_mode, view_opts)
  end
end

function Services.agenda.open(opts)
  -- If already open, just focus the window and optionally refresh
  if view.is_open() then
    local buf = view._buf
    local win = view._win
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      if opts and (opts.fullscreen ~= nil or opts.todo_filter or opts.headline_filter) then
        render(vim.api.nvim_win_get_cursor(0), opts, true)
      end
      return
    end
  end
  -- Not open yet, create new window
  store.set_cursor(nil)
  render(nil, opts or {}, false)
end
function Services.agenda.refresh(cursor, opts)
  render(cursor, opts, true)
end
function Services.agenda.on_close()
  if not cfg().persist_hidden then
    store.reset_hidden()
  end
  store.sticky_reset()
  store.clear_active_view()
end

function Services.agenda.toggle_duplicates()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  store.toggle_dupes()
  if cur then
    Services.agenda.refresh(cur)
  end
end

function Services.agenda.cycle_view()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  local m = store.get().view_mode
  store.set_view_mode(m == 'classic' and 'compact' or 'classic')
  if cur then
    Services.agenda.refresh(cur)
  else
    Services.agenda.open()
  end
end

function Services.agenda.hide_current()
  local lm = view.line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it = lm[cur[1]]
  if not it then
    return
  end
  local key = string.format('%s:%s', it.file or '', it._src_line or 0)
  store.hide(key)
  store.sticky_remove(key) -- if it was sticky, hide overrides
  Services.agenda.refresh(cur)
end

function Services.agenda.reset_hidden()
  store.reset_hidden()
end

function Services.agenda.toggle_group(group_name, cursor)
  if not group_name or group_name == '' then
    return
  end
  store.toggle_group(group_name)
  Services.agenda.refresh(cursor or (view.is_open() and vim.api.nvim_win_get_cursor(0) or nil))
end

function Services.agenda.fold_all()
  if not view.is_open() then
    return
  end
  local line_map = view.line_map() or {}
  local seen, names = {}, {}
  for _, entry in pairs(line_map) do
    if type(entry) == 'table' and entry._kind == 'group_header' and entry.group_name and not seen[entry.group_name] then
      seen[entry.group_name] = true
      names[#names + 1] = entry.group_name
    end
  end
  store.fold_groups(names)
  Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
end

function Services.agenda.unfold_all()
  store.unfold_all_groups()
  if view.is_open() then
    Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
  end
end

function Services.agenda.open_view(view_key, opts)
  local views_core = require('org-super-agenda.core.views')
  local c = cfg()
  local def = c.custom_views and c.custom_views[view_key]
  if not def then
    vim.notify('Unknown view: ' .. tostring(view_key), vim.log.levels.WARN)
    return
  end
  local resolved = views_core.resolve(def)
  store.set_active_view(resolved, view_key)
  store.set_cursor(nil)
  render(nil, opts or {}, view.is_open())
end

function Services.agenda.clear_view()
  store.clear_active_view()
  if view.is_open() then
    Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
  end
end

function Services.agenda.list_views()
  local views_core = require('org-super-agenda.core.views')
  return views_core.list(cfg().custom_views)
end

function Services.refile_start(src_file, s, e, lvl)
  local ok, ref = pcall(require, 'org-super-agenda.adapters.neovim.refile_telescope')
  if not ok then
    return vim.notify('Refile requires telescope + org-telescope', vim.log.levels.WARN)
  end
  ref.start({ src_file = src_file, s = s, e = e, src_level = lvl }, function()
    local cur = vim.api.nvim_win_get_cursor(0)
    Services.agenda.refresh(cur)
  end)
end

return Services
