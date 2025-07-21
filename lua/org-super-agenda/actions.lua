-- org-super-agenda.actions ---------------------------------------------------
local utils = require('org-super-agenda.utils')
local A = {}
local get_cfg = require('org-super-agenda.config').get

local function with_headline(line_map, cb)
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = line_map[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('Kein Eintrag unter dem Cursor', vim.log.levels.WARN)
    return
  end

  local ok, api_root = pcall(require, 'orgmode.api'); if not ok then return end
  local org_api = api_root.load and api_root or api_root.org
  local file    = org_api.load(it.file); if vim.islist(file) then file = file[1] end
  if not (file and file.get_headline_on_line) then return end

  local hl = file:get_headline_on_line(it._src_line); if not hl then return end
  cb(cur, hl)
end

function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -------------------------------------------------------------------------
  -- wipe / close ----------------------------------------------------------
  local function wipe() pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, wipe, { buffer = buf, silent = true })
  end

  -------------------------------------------------------------------------
  -- jump into org file ----------------------------------------------------
  vim.keymap.set('n', '<CR>', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(hl.file.filename))
      vim.api.nvim_win_set_cursor(0, { hl.position.start_line, 0 })

      local filebuf = vim.api.nvim_get_current_buf()
      pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer   = filebuf,
        once     = true,
        callback = function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
            reopen(cur)
          end)
        end,
      })
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- reschedule -----------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.reschedule, function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      hl:set_scheduled():next(function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(agendabuf) then
            pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
          end
          reopen(cur)
        end)
      end)
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- deadline -------------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      hl:set_deadline():next(function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(agendabuf) then
            pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
          end
          reopen(cur)
        end)
      end)
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- Priorities ---------------------------------------------------------
  local function refresh_agenda(cur, agendabuf)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(agendabuf) then
        pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      end
      require('org-super-agenda').open(cur)
    end)
  end

  -- set_priority("A"/"B"/"C"/"") -------------------
  local function make_set_priority(prio)
    return function()
      with_headline(line_map, function(cur, hl)
        local agendabuf = vim.api.nvim_get_current_buf()
        local p         = hl:set_priority(prio)
        if p and type(p.next) == 'function' then
          p:next(function() refresh_agenda(cur, agendabuf) end)
        else
          refresh_agenda(cur, agendabuf)
        end
      end)
    end
  end

  -- Setter ------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.priority_A or 'cA', make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B or 'cB', make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C or 'cC', make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear or 'c0', make_set_priority(''), { buffer = buf, silent = true })

  -- step‑wise up / down --------------------------------------------
  vim.keymap.set('n', cfg.keymaps.priority_up or 'c+', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      local p         = hl:priority_up()
      if p and type(p.next) == 'function' then
        p:next(function() refresh_agenda(cur, agendabuf) end)
      else
        refresh_agenda(cur, agendabuf)
      end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down or 'c-', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      local p         = hl:priority_down()
      if p and type(p.next) == 'function' then
        p:next(function() refresh_agenda(cur, agendabuf) end)
      else
        refresh_agenda(cur, agendabuf)
      end
    end)
  end, { buffer = buf, silent = true })

vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })

end

return A
