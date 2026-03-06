-- org-super-agenda/init.lua (bootstrap & wiring)
local cfgmod = require('org-super-agenda.config')
local Store = require('org-super-agenda.app.store')
local Pipeline = require('org-super-agenda.app.pipeline')
local Services = require('org-super-agenda.app.services')

local SourcePort = require('org-super-agenda.adapters.neovim.source_orgmode')
local ViewPort = require('org-super-agenda.adapters.neovim.view_float')

local M = {}

function M.setup(user)
  local cfg = cfgmod.setup(user or {})

  -- wire services
  Services.setup({
    cfg = cfg,
    store = Store,
    source = SourcePort,
    view = ViewPort,
    pipeline = Pipeline,
  })

  -- :OrgSuperAgenda            -> centered float (from config sizes)
  -- :OrgSuperAgenda fullscreen -> fullscreen
  -- :OrgSuperAgenda!           -> fullscreen (bang alias)
  -- :OrgSuperAgenda view <name> -> open custom view
  -- :OrgSuperAgenda views       -> view picker
  vim.api.nvim_create_user_command('OrgSuperAgenda', function(opts)
    local args = vim.trim(opts.args or '')
    local fullscreen = opts.bang == true

    if args:lower():match('^full') then
      Services.agenda.open({ fullscreen = true })
    elseif args:lower():match('^views?$') and not args:match('^view%s+') then
      -- :OrgSuperAgenda views -> picker
      Services.agenda.open({ fullscreen = fullscreen })
      vim.schedule(function()
        M.show_view_picker()
      end)
    elseif args:match('^view%s+') then
      local view_key = args:match('^view%s+(.+)$')
      if view_key then
        Services.agenda.open_view(vim.trim(view_key), { fullscreen = fullscreen })
      end
    else
      Services.agenda.open({ fullscreen = fullscreen })
    end
  end, {
    nargs = '?',
    bang = true,
    complete = function(_, line)
      local parts = vim.split(vim.trim(line), '%s+')
      if #parts == 2 and parts[2]:match('^view') then
        local views = Services.agenda.list_views()
        local keys = { 'views' }
        for _, v in ipairs(views) do
          keys[#keys + 1] = 'view ' .. v.key
        end
        return keys
      end
      local base = { 'fullscreen', 'views' }
      local views = Services.agenda.list_views()
      for _, v in ipairs(views) do
        base[#base + 1] = 'view ' .. v.key
      end
      return base
    end,
  })

  -- register global keymaps for custom views
  for key, def in pairs(cfg.custom_views or {}) do
    if def.keymap and def.keymap ~= '' then
      vim.keymap.set('n', def.keymap, function()
        Services.agenda.open_view(key)
      end, { silent = true, desc = 'OrgSuperAgenda: ' .. (def.name or key) })
    end
  end
end

-- Expose a minimal API for internal adapters (used by actions)
M.refresh = function(cur, opts)
  Services.agenda.refresh(cur, opts)
end
M.on_close = function()
  Services.agenda.on_close()
end
M.toggle_duplicates = function()
  Services.agenda.toggle_duplicates()
end
M.cycle_view = function()
  Services.agenda.cycle_view()
end
M.hide_current = function()
  Services.agenda.hide_current()
end
M.reset_hidden = function()
  Services.agenda.reset_hidden()
end
M.toggle_group = function(name, cur)
  Services.agenda.toggle_group(name, cur)
end
M.fold_all = function()
  Services.agenda.fold_all()
end
M.unfold_all = function()
  Services.agenda.unfold_all()
end
M.push_undo = function(fn)
  Store.push_undo(fn)
end
M.pop_undo = function()
  return Store.pop_undo()
end
M.open_view = function(key, opts)
  Services.agenda.open_view(key, opts)
end
M.clear_view = function()
  Services.agenda.clear_view()
end
M.list_views = function()
  return Services.agenda.list_views()
end

function M.show_view_picker()
  local views = Services.agenda.list_views()
  if #views == 0 then
    vim.notify('No custom views configured', vim.log.levels.INFO)
    return
  end

  local active_key = Store.get_active_view_key()
  local items = {}
  if active_key then
    items[#items + 1] = { key = nil, label = '⏎  Default Agenda', desc = 'Back to default view' }
  end
  for _, v in ipairs(views) do
    local marker = (v.key == active_key) and ' ◀' or ''
    local km = v.keymap and (' [' .. v.keymap .. ']') or ''
    items[#items + 1] = {
      key = v.key,
      label = (v.name or v.key) .. km .. marker,
      desc = v.filter ~= '' and ('filter: ' .. v.filter) or '',
    }
  end

  local lines, widest = {}, 0
  for i, item in ipairs(items) do
    local line = string.format(' %s  %s', tostring(i), item.label)
    lines[#lines + 1] = line
    if #line > widest then
      widest = #line
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'text'

  local ui = vim.api.nvim_list_uis()[1]
  local h = #lines + 2
  local w = math.max(widest + 4, 30)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    row = math.floor((ui.height - h) / 2),
    col = math.floor((ui.width - w) / 2),
    width = w,
    height = h,
    title = 'Custom Views',
    title_pos = 'center',
  })
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function select_item(idx)
    close()
    local item = items[idx]
    if not item then
      return
    end
    if item.key == nil then
      Services.agenda.clear_view()
    else
      Services.agenda.open_view(item.key)
    end
  end

  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    select_item(row)
  end, { buffer = buf, silent = true })

  for i = 1, math.min(#items, 9) do
    vim.keymap.set('n', tostring(i), function()
      select_item(i)
    end, { buffer = buf, silent = true })
  end

  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, close, { buffer = buf, silent = true })
  end
end

return M
