-- org-super-agenda.view ------------------------------------------------------
local hi      = require('org-super-agenda.highlight')
local layout  = require('org-super-agenda.layout')
local actions = require('org-super-agenda.actions')
local get_cfg = require('org-super-agenda.config').get
local V       = {}

function V.render(groups, cursor)
  hi.ensure()
  local cfg                 = get_cfg()
  local ui                  = vim.api.nvim_list_uis()[1]
  local left                = cfg.window.margin_left or 0
  local right               = cfg.window.margin_right or 0
  local win_w               = math.floor(ui.width * cfg.window.width) - left - right

  -- rows, hls, map ---------------------------------------------------------
  local rows, hls, line_map = layout.build(groups, win_w)

  -- Buffer / Window --------------------------------------------------------
  local buf                 = vim.api.nvim_create_buf(false, true)
  local pad                 = {}
  for _, l in ipairs(rows) do
    pad[#pad + 1] = string.rep(' ', left) .. l .. string.rep(' ', right)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pad)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(
      buf, 0, h[4],
      h[1],
      left + h[2],
      h[3] == -1 and -1 or left + h[3]
    )
  end
  vim.api.nvim_buf_set_option(buf, 'filetype', 'org')
  vim.api.nvim_buf_set_name(buf, 'Org Super Agenda')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local h   = math.floor(ui.height * cfg.window.height)
  local w   = win_w + left + right
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    style     = 'minimal',
    width     = w,
    height    = h,
    col       = math.floor((ui.width - w) / 2),
    row       = math.floor((ui.height - h) / 2),
    border    = cfg.window.border,
    title     = cfg.window.title,
    title_pos = cfg.window.title_pos,
  })
  vim.api.nvim_win_set_option(win, 'wrap', false)

  -- Keymaps / Actions ------------------------------------------------------
  local function reopen(cur)
    require('org-super-agenda').open(cur)
  end
  actions.set_keymaps(buf, win, line_map, reopen)

  -- Cursor‑Restore ---------------------------------------------------------
  if cursor then
    vim.schedule(function()
      pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end)
  end
end

return V
