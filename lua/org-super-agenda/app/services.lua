-- app/services.lua -- thin imperative shell around pipeline & view
local Services = { agenda = {}, refile = {} }

local store, source, view, pipeline
local function cfg() return require('org-super-agenda.config').get() end

function Services.setup(deps)
  store    = deps.store
  source   = deps.source
  view     = deps.view
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
    if opts.todo_filter == nil then s.opts.todo_filter = nil end
    if opts.headline_filter == nil then s.opts.headline_filter = nil end
    if opts.headline_fuzzy == nil then s.opts.headline_fuzzy = nil end
    if opts.query == nil then s.opts.query = nil end
    local state_opts = vim.tbl_deep_extend('force', s.opts or {}, {
      todo_filter     = opts.todo_filter,
      headline_filter = opts.headline_filter,
      headline_fuzzy  = opts.headline_fuzzy,
      query           = opts.query,
    })
    store.set_opts(state_opts)
  end
  if cursor then store.set_cursor(cursor) end

  local s = store.get()
  local producer = pipeline.run(source, cfg(), s)
  if reuse and view.is_open() then view.update(producer, s.cursor, s.view_mode, view_opts)
  else view.render(producer, s.cursor, s.view_mode, view_opts) end
end

function Services.agenda.open(opts) store.set_cursor(nil); render(nil, opts or {}, false) end
function Services.agenda.refresh(cursor, opts) render(cursor, opts, true) end
function Services.agenda.on_close()
  if not cfg().persist_hidden then store.reset_hidden() end
  store.sticky_reset() -- drop session-only DONE visibility on close
end

function Services.agenda.toggle_duplicates()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  store.toggle_dupes()
  if cur then Services.agenda.refresh(cur) end
end

function Services.agenda.cycle_view()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  local m = store.get().view_mode
  store.set_view_mode(m == 'classic' and 'compact' or 'classic')
  if cur then Services.agenda.refresh(cur) else Services.agenda.open() end
end

function Services.agenda.hide_current()
  local lm  = view.line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = lm[cur[1]]
  if not it then return end
  local key = string.format('%s:%s', it.file or '', it._src_line or 0)
  store.hide(key)
  store.sticky_remove(key) -- if it was sticky, hide overrides
  Services.agenda.refresh(cur)
end

function Services.agenda.reset_hidden() store.reset_hidden() end

function Services.refile_start(src_file, s, e, lvl)
  local ok, ref = pcall(require, 'org-super-agenda.adapters.neovim.refile_telescope')
  if not ok then return vim.notify('Refile requires telescope + org-telescope', vim.log.levels.WARN) end
  ref.start({ src_file = src_file, s = s, e = e, src_level = lvl }, function()
    local cur = vim.api.nvim_win_get_cursor(0)
    Services.agenda.refresh(cur)
  end)
end

return Services

