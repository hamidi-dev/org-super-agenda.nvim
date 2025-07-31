-- org-super-agenda.actions ---------------------------------------------------
local utils   = require('org-super-agenda.utils')
local config  = require('org-super-agenda.config')
local view    = require('org-super-agenda.view')
local A       = {}
local get_cfg = config.get

local function with_headline(_, cb)
  local lm  = view.line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = lm[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('No entry under cursor', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.fn.bufnr(it.file)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(it.file)
    vim.fn.bufload(bufnr)
  end

  local ok, api_root = pcall(require, 'orgmode.api'); if not ok then return end
  local org_api = api_root.load and api_root or api_root.org
  local file    = org_api.load(it.file); if vim.islist(file) then file = file[1] end
  if not (file and file.get_headline_on_line) then return end

  local hl = file:get_headline_on_line(it._src_line)
  if not hl then return end
  cb(cur, hl)
end

local function preview_headline(line_map)
  with_headline(line_map, function(_, hl)
    local lines = {}
    if hl._section and hl._section.get_lines then
      lines = hl._section:get_lines()
    elseif hl.position and hl.position.start_line and hl.position.end_line then
      local bufnr = vim.fn.bufnr(hl.file.filename)
      if bufnr == -1 then bufnr = vim.fn.bufadd(hl.file.filename) end
      if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
      lines = vim.api.nvim_buf_get_lines(bufnr,
        hl.position.start_line - 1,
        hl.position.end_line,
        false)
    end
    if #lines == 0 then return end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'org'

    local ui             = vim.api.nvim_list_uis()[1]
    local h              = math.min(#lines + 2, math.floor(ui.height * 0.6))
    local w              = math.min(80, math.floor(ui.width * 0.8))
    local win            = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      style    = 'minimal',
      border   = 'rounded',
      width    = w,
      height   = h,
      col      = math.floor((ui.width - w) / 2),
      row      = math.floor((ui.height - h) / 2),
      title    = 'Org Preview',
    })
    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
  end)
end

function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -------------------------------------------------------------------------
  -- wipe / close ----------------------------------------------------------
  local function wipe()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    require('org-super-agenda').on_close()
  end
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
      local p = hl:set_scheduled()
      if p and type(p.next) == 'function' then
        p:next(function() require('org-super-agenda').refresh(cur) end)
      else
        require('org-super-agenda').refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- deadline -------------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:set_deadline()
      if p and type(p.next) == 'function' then
        p:next(function() require('org-super-agenda').refresh(cur) end)
      else
        require('org-super-agenda').refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- toggle Other group --------------------------------------------------
  if cfg.keymaps.toggle_other and cfg.keymaps.toggle_other ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_other, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      config.setup({ show_other_group = not get_cfg().show_other_group })
      require('org-super-agenda').refresh(cur)
    end, { buffer = buf, silent = true })
  end

  ------------------------------------------------------------------------
  -- toggle duplicates ---------------------------------------------------
  if cfg.keymaps.toggle_duplicates and cfg.keymaps.toggle_duplicates ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_duplicates, function()
      require('org-super-agenda').toggle_duplicates()
    end, { buffer = buf, silent = true })
  end

  ------------------------------------------------------------------------
  -- Priorities -----------------------------------------------------------
  local function do_refresh(cur)
    require('org-super-agenda').refresh(cur)
  end

  local function make_set_priority(prio)
    return function()
      with_headline(line_map, function(cur, hl)
        local p = hl:set_priority(prio)
        if p and type(p.next) == 'function' then
          p:next(function() do_refresh(cur) end)
        else
          do_refresh(cur)
        end
      end)
    end
  end

  vim.keymap.set('n', cfg.keymaps.priority_A, make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B, make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C, make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear, make_set_priority(''), { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_up, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:priority_up()
      if p and type(p.next) == 'function' then
        p:next(function() do_refresh(cur) end)
      else
        do_refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:priority_down()
      if p and type(p.next) == 'function' then
        p:next(function() do_refresh(cur) end)
      else
        do_refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- Quick TODO filters --------------------------------------------------
  for _, st in ipairs(get_cfg().todo_states or {}) do
    if st.keymap and st.keymap ~= '' and st.name then
      vim.keymap.set('n', st.keymap, function()
        local cur = vim.api.nvim_win_get_cursor(0)
        require('org-super-agenda').refresh(cur, { todo_filter = st.name })
      end, { buffer = buf, silent = true })
    end
  end

  if cfg.keymaps.filter_reset and cfg.keymaps.filter_reset ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_reset, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      -- passing nil removes the filters stored in the module
      require('org-super-agenda').refresh(cur, { todo_filter = nil, headline_filter = nil })
    end, { buffer = buf, silent = true })
  end

  local function live_filter(fuzzy)
    local cur   = vim.api.nvim_win_get_cursor(0)
    local query = ''

    local function apply()
      require('org-super-agenda').refresh(cur, {
        headline_filter = query,
        headline_fuzzy  = fuzzy,
      })
      vim.api.nvim_echo({ { 'Filter: ' .. query } }, false, {})
      vim.cmd('redraw')
    end

    vim.api.nvim_echo({ { 'Filter: ' } }, false, {})
    while true do
      local ok, c = pcall(vim.fn.getcharstr)
      if not ok then break end

      -- handle escape
      if c == '\027' or c == '\013' then break end

      -- handle backspace
      local bs = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
      if c == '\008' or c == '\127' or c == bs then
        query = query:sub(1, -2)
      else
        query = query .. c
      end
      apply()
    end
    vim.api.nvim_echo({}, false, {})
  end


  if cfg.keymaps.filter and cfg.keymaps.filter ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter, function() live_filter(false) end,
      { buffer = buf, silent = true, nowait = true })
  end

  if cfg.keymaps.filter_fuzzy and cfg.keymaps.filter_fuzzy ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_fuzzy, function() live_filter(true) end,
      { buffer = buf, silent = true, nowait = true })
  end

  if cfg.keymaps.preview and cfg.keymaps.preview ~= '' then
    vim.keymap.set('n', cfg.keymaps.preview, function()
      preview_headline(line_map)
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.hide_item and cfg.keymaps.hide_item ~= '' then
    vim.keymap.set('n', cfg.keymaps.hide_item, function()
      require('org-super-agenda').hide_current()
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.reset_hidden and cfg.keymaps.reset_hidden ~= '' then
    vim.keymap.set('n', cfg.keymaps.reset_hidden, function()
      require('org-super-agenda').reset_hidden()
      require('org-super-agenda').refresh(vim.api.nvim_win_get_cursor(0))
    end, { buffer = buf, silent = true })
  end

  -- ------------------------------------------------------------------------
  -- Cycle TODO‑Keyword -----------------------------------------------------
  -- ------------------------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.cycle_todo, function()
    with_headline(line_map, function(cur, hl)
      local seq = {}
      for _, s in ipairs(get_cfg().todo_states or {}) do
        seq[#seq + 1] = s.name
      end
      if #seq == 0 then return end

      local idx = 0
      for i, v in ipairs(seq) do
        if v == (hl.todo_value or '') then
          idx = i; break
        end
      end
      local next_state = seq[idx % #seq + 1]
      local old_state  = hl.todo_value or ''

      local bufnr      = vim.fn.bufnr(hl.file.filename)
      local created    = false
      if bufnr == -1 then
        bufnr   = vim.fn.bufadd(hl.file.filename)
        created = true
      end
      if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end

      local lnum = (hl.position and hl.position.start_line or 1) - 1
      if lnum < 0 then return end
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
      if not line then return end

      local stars, _, rest = line:match('^(%*+)%s+([A-Z]+)%s+(.*)$')
      if not stars then stars, rest = line:match('^(%*+)%s+(.*)$') end
      if not stars then return end

      local new_line = (next_state == '')
          and string.format('%s %s', stars, rest)
          or string.format('%s %s %s', stars, next_state, rest)

      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent noautocmd write') end)
      if created and vim.fn.bufwinnr(bufnr) == -1 then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end

      local agenda_buf  = buf
      local agenda_lnum = cur[1] - 1
      local row         = vim.api.nvim_buf_get_lines(
        agenda_buf, agenda_lnum, agenda_lnum + 1, false
      )[1] or ''

      if old_state ~= '' then
        row = row:gsub(old_state, (next_state == '' and '' or next_state), 1)
      else
        row = row:gsub('^%s*', '%0' .. next_state .. ' ')
      end

      vim.api.nvim_buf_set_option(agenda_buf, 'modifiable', true)
      vim.api.nvim_buf_set_lines(agenda_buf, agenda_lnum, agenda_lnum + 1, false,
        { row })
      vim.api.nvim_buf_set_option(agenda_buf, 'modifiable', false)

      if next_state == 'DONE' then
        local hi = require('org-super-agenda.highlight')
        vim.api.nvim_buf_clear_namespace(agenda_buf, view._ns,
          agenda_lnum, agenda_lnum + 1)
        vim.api.nvim_buf_add_highlight(
          agenda_buf, view._ns, hi.group('DONE'),
          agenda_lnum, 0, -1
        )
      else
        require('org-super-agenda').refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- Reload (r) –-----------------------------
  ------------------------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.reload, function()
    local cur = vim.api.nvim_win_get_cursor(0)
    require('org-super-agenda').refresh(cur)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- Cycle View -----------------------------------------------------
  if cfg.keymaps.cycle_view and cfg.keymaps.cycle_view ~= '' then
    vim.keymap.set('n', cfg.keymaps.cycle_view, function()
      require('org-super-agenda').cycle_view()
    end, { buffer = buf, silent = true })
  end

  ------------------------------------------------------------------------
  -- Help ----------------------------------------------------------------
  vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })
end

return A
