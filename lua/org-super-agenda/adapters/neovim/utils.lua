-- adapters/neovim/utils.lua
local get_cfg = require('org-super-agenda.config').get
local U = {}

function U.expand(path) return (path:gsub('^~', vim.fn.expand('$HOME'))) end

function U.get_org_files(dir)
  local res, cmd = {}, string.format('find %q -type f -name "*.org"', U.expand(dir))
  local handle = io.popen(cmd)
  if handle then for f in handle:lines() do res[#res+1] = f end; handle:close() end
  return res
end

function U.show_help()
  local cfg = get_cfg()
  local km  = cfg.keymaps or {}
  local function fmt(key, label) if not key or key == '' then return nil end return string.format('%-10s  %s', key, label) end

  local lines = {
    'Org-Super-Agenda – Keymaps',
    '──────────────────────────',
    '',
    'Change Dates:',
    fmt(km.reschedule, 'Set SCHEDULED'),
    fmt(km.set_deadline, 'Set DEADLINE'),
    '',
    'Priority:',
    fmt(km.priority_up, 'Priority up    ↑'),
    fmt(km.priority_down, 'Priority down  ↓'),
    fmt(km.priority_A, 'Set [#A]'),
    fmt(km.priority_B, 'Set [#B]'),
    fmt(km.priority_C, 'Set [#C]'),
    fmt(km.priority_clear, 'Clear priority'),
    '',
  }

  local any_filter = false
  for _, st in ipairs(cfg.todo_states or {}) do
    if st.keymap and st.keymap ~= '' then
      if not any_filter then lines[#lines + 1] = 'Todo Filters:'; any_filter = true end
      lines[#lines + 1] = fmt(st.keymap, 'Show only ' .. st.name)
    end
  end
  lines[#lines + 1] = fmt(km.filter, 'Filter by keyword')
  lines[#lines + 1] = fmt(km.filter_fuzzy, 'Filter by keyword (fuzzy)')
  lines[#lines + 1] = fmt(km.filter_query, 'Filter by query')
  lines[#lines + 1] = fmt(km.filter_reset, 'Reset all filters')
  if any_filter then lines[#lines + 1] = '' end

  vim.list_extend(lines, {
    'Misc:',
    fmt('<CR>', 'Open headline'),
    fmt(km.reload, 'Reload agenda'),
    fmt(km.cycle_todo, 'Cycle TODO-States'),
    fmt(km.set_state, 'Set state (menu)'),
    fmt(km.undo, 'Undo'),
    fmt(km.toggle_other, 'Toggle "Other" group'),
    fmt(km.toggle_duplicates, 'Toggle duplicates'),
    fmt(km.cycle_view, 'Switch view (classic/compact)'),
    fmt(km.hide_item, 'Hide headline from agenda'),
    fmt(km.reset_hidden, 'Reset hide'),
    fmt(km.refile, 'Refile headline [<C-Space> toggles mode]'),
    fmt('q / <Esc>', 'Close agenda'),
    '',
    'g? / q / <Esc> close this help.',
  })

  local out = {}
  for _, l in ipairs(lines) do if l then out[#out + 1] = l end end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable, vim.bo[buf].filetype = false, 'text'

  local ui = vim.api.nvim_list_uis()[1]
  local h, w = #out + 2, 60
  vim.api.nvim_open_win(buf, true, {
    relative='editor', style='minimal', border='rounded',
    row=math.floor((ui.height - h) / 2), col=math.floor((ui.width - w) / 2),
    width=w, height=h, title='Agenda-Help',
  })

  local function close() pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  for _, k in ipairs({ 'g?', 'q', '<Esc>' }) do
    vim.keymap.set('n', k, close, { buffer = buf, silent = true })
  end
end

return U

