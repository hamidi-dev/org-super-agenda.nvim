local cfg      = require('org-super-agenda.config')
local source   = require('org-super-agenda.source')
local groups   = require('org-super-agenda.groups')
local view     = require('org-super-agenda.view')

local M        = {}

M._last_opts   = {}
M._last_cursor = nil
M._hidden      = {}

local function key_of(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

local function build_items(opts)
  opts = opts or {}
  local items = source.collect_items()

  if next(M._hidden) then
    local filtered = {}
    for _, it in ipairs(items) do
      if not M._hidden[key_of(it)] then
        filtered[#filtered + 1] = it
      end
    end
    items = filtered
  end

  if opts.todo_filter then
    local wanted = {}
    if type(opts.todo_filter) == 'string' then
      wanted[opts.todo_filter] = true
    elseif type(opts.todo_filter) == 'table' then
      for _, st in ipairs(opts.todo_filter) do wanted[st] = true end
    end
    if next(wanted) then
      local filtered = {}
      for _, it in ipairs(items) do
        if wanted[it.todo_state] then table.insert(filtered, it) end
      end
      items = filtered
    end
  end

  if opts.headline_filter and opts.headline_filter ~= '' then
    local q        = opts.headline_filter
    local fuzzy    = opts.headline_fuzzy
    local filtered = {}

    local function corpus(it)
      local fn   = vim.fn.fnamemodify(it.file or '', ':t'):gsub('%.org$', '')
      local tags = it.tags and #it.tags > 0 and (':' .. table.concat(it.tags, ':') .. ':') or ''
      return table.concat({
        it.headline or '',
        it.todo_state or '',
        fn,
        tags,
      }, ' '):lower()
    end

    if fuzzy then
      for _, it in ipairs(items) do
        if #vim.fn.matchfuzzy({ corpus(it) }, q) > 0 then
          filtered[#filtered + 1] = it
        end
      end
    else
      q = q:lower()
      for _, it in ipairs(items) do
        if corpus(it):find(q, 1, true) then
          filtered[#filtered + 1] = it
        end
      end
    end
    items = filtered
  end

  return items
end

local function do_render(cursor_pos, opts, reuse)
  local items   = build_items(opts)
  local grouped = groups.group_items(items)
  local mode    = cfg.get().view_mode or 'classic'
  local data    = grouped

  if reuse and view.is_open() then
    view.update(data, cursor_pos, mode)
  else
    view.render(data, cursor_pos, mode)
  end
end


function M.setup(opts)
  cfg.setup(opts or {})
  vim.api.nvim_create_user_command('OrgSuperAgenda', function() M.open() end, {})
end

--- open a (new) agenda view ---------------------------------------------------
-- normally called by user :OrgSuperAgenda
function M.open(cursor_pos, opts)
  opts           = opts or {}
  M._last_opts   = opts
  M._last_cursor = cursor_pos
  do_render(cursor_pos, opts, false) -- force fresh float
end

--- refresh existing agenda in-place (no flicker) ------------------------------
-- used internally after edits (schedule, deadline, priority...)
function M.refresh(cursor_pos, opts)
  -- merge new opts into stored opts; new opts override
  if opts then
    if opts.todo_filter == nil and M._last_opts then
      M._last_opts.todo_filter = nil
    end
    if opts.headline_filter == nil and M._last_opts then
      M._last_opts.headline_filter = nil
    end
    if opts.headline_fuzzy == nil and M._last_opts then
      M._last_opts.headline_fuzzy = nil
    end
    M._last_opts = vim.tbl_deep_extend('force', M._last_opts or {}, opts)
  end
  M._last_cursor = cursor_pos or M._last_cursor
  do_render(M._last_cursor, M._last_opts, true)
end

function M.hide_current()
  local lm  = require('org-super-agenda.view').line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = lm[cur[1]]
  if not it then return end
  M._hidden[key_of(it)] = true
  M.refresh(cur)
end

function M.reset_hidden()
  M._hidden = {}
end

function M.toggle_duplicates()
  local cur
  if view.is_open() then cur = vim.api.nvim_win_get_cursor(0) end
  cfg.setup({ allow_duplicates = not cfg.get().allow_duplicates })
  if cur then M.refresh(cur) end
end

function M.cycle_view()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  local mode = cfg.get().view_mode or 'classic'
  local next_mode = (mode == 'classic') and 'compact' or 'classic'
  cfg.setup({ view_mode = next_mode })
  if cur then M.refresh(cur) else M.open() end
end

function M.on_close()
  if not cfg.get().persist_hidden then
    M.reset_hidden()
  end
end

M._build_items = build_items
return M
