local get_cfg = require('org-super-agenda.config').get
local U = {}

function U.expand(path) return (path:gsub('^~', vim.fn.expand('$HOME'))) end

-- Directory filter helper ----------------------------------------------------
function U.in_dirs(path, dirlist)
  if #dirlist == 0 then return true end
  for _, d in ipairs(dirlist) do
    if path:find('^' .. vim.pesc(U.expand(d))) then return true end
  end
end

-- ⬇️  NEW: recursively collect *.org files in a directory ---------------------
function U.get_org_files(dir)
  local res, cmd = {}, string.format('find %q -type f -name "*.org"', U.expand(dir))
  local handle = io.popen(cmd)
  if handle then
    for f in handle:lines() do table.insert(res, f) end
    handle:close()
  end
  return res
end

-- truncate a string to `len` characters --------------------------------------
function U.truncate(str, len)
  if not len or #str <= len then return str end
  return str:sub(1, len)
end

------------------------------------------------------------------------
-- Help context  (g?) -------------------------------------------------
------------------------------------------------------------------------
function U.show_help()
  local cfg = get_cfg()
  local km  = cfg.keymaps or {}

  local function fmt(key, label)
    if not key or key == '' then return nil end
    return string.format('%-10s  %s', key, label)
  end

  local lines = {
    'Org‑Super‑Agenda – Keymaps',
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
      if not any_filter then
        lines[#lines + 1] = 'Todo Filters:'
        any_filter = true
      end
      lines[#lines + 1] = fmt(st.keymap, 'Show only ' .. st.name)
    end
  end
  lines[#lines + 1] = fmt(km.filter_reset, 'Reset all filters')

  if any_filter then lines[#lines + 1] = '' end

  vim.list_extend(lines, {
    'Misc:',
    fmt('<CR>', 'Open headline'),
    fmt('q / <Esc>', 'Close agenda'),
    '',
    'g? / q / <Esc> close this help.',
  })

  local out = {}
  for _, l in ipairs(lines) do if l then out[#out + 1] = l end end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'text'

  local ui  = vim.api.nvim_list_uis()[1]
  local h   = #out + 2
  local w   = 50
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    style    = 'minimal',
    border   = 'rounded',
    row      = math.floor((ui.height - h) / 2),
    col      = math.floor((ui.width - w) / 2),
    width    = w,
    height   = h,
    title    = 'Agenda‑Help',
  })

  local function close() pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  for _, k in ipairs({ 'g?', 'q', '<Esc>' }) do
    vim.keymap.set('n', k, close, { buffer = buf, silent = true })
  end
end

return U
