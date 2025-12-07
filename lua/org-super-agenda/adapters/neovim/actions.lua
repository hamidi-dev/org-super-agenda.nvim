-- adapters/neovim/actions.lua
local utils     = require('org-super-agenda.adapters.neovim.utils')
local config    = require('org-super-agenda.config')
local Services  = require('org-super-agenda.app.services')
local Store     = require('org-super-agenda.app.store')

local A = {}
local function get_cfg() return config.get() end
local function key_for_hl(hl)
  return string.format('%s:%s', hl.file.filename or '', hl.position and hl.position.start_line or 0)
end

-- === helpers: swap detection, buffer status, snapshots, safe writes ===
local function has_swap_for(path)
  -- Heuristic: look for .*{basename}*.sw?
  local dir = vim.fn.fnamemodify(path, ":p:h")
  local base = vim.fn.fnamemodify(path, ":t")
  local patt = dir .. "/.*" .. vim.fn.escape(base, "[]^$\\.*") .. ".*.sw?"
  return vim.fn.glob(patt) ~= ""
end

local function buf_status_for(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then return { bufnr = -1, loaded = false, modified = false } end
  local loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local modified = loaded and vim.api.nvim_buf_get_option(bufnr, 'modified') or false
  return { bufnr = bufnr, loaded = loaded, modified = modified }
end

-- Snapshot/restore utilities
local function snapshot_heading_from_buf(hl)
  local bufnr = vim.fn.bufnr(hl.file.filename)
  if bufnr == -1 then bufnr = vim.fn.bufadd(hl.file.filename) end
  if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start = hl.position.start_line
  while start > 1 and not lines[start]:match("^%*+") do start = start - 1 end
  local lvl  = #(lines[start]:match("^(%*+)"))
  local stop = #lines
  for i = start + 1, #lines do
    local s = lines[i]:match("^(%*+)")
    if s and #s <= lvl then stop = i - 1; break end
  end
  return {
    bufnr = bufnr, start = start, stop = stop,
    seg = vim.list_slice(lines, start, stop),
    mode = 'buffer',
  }
end

local function heading_range_in_file(all_lines, pos_start)
  local start = pos_start
  while start > 0 and not all_lines[start]:match("^%*+") do start = start - 1 end
  if start == 0 then return nil end
  local lvl = #(all_lines[start]:match("^(%*+)"))
  local stop = #all_lines
  for i = start + 1, #all_lines do
    local s = all_lines[i]:match("^(%*+)")
    if s and #s <= lvl then stop = i - 1; break end
  end
  return start, stop
end

local function snapshot_heading_from_disk(path, pos_start)
  local lines = vim.fn.readfile(path)
  local s, e = heading_range_in_file(lines, pos_start)
  if not s then
    -- fallback: single-line snapshot only
    s, e = pos_start, pos_start
  end
  return {
    path = path, start = s, stop = e,
    seg = vim.list_slice(lines, s, e),
    mode = 'file',
  }
end

local function make_restore_from_snapshot(snap)
  if snap.mode == 'buffer' then
    return function()
      vim.api.nvim_buf_set_lines(snap.bufnr, snap.start - 1, snap.stop, false, snap.seg)
      vim.api.nvim_buf_call(snap.bufnr, function() vim.cmd('silent noautocmd write') end)
    end
  else
    return function()
      local before = vim.fn.readfile(snap.path)
      -- splice original segment back
      local out = {}
      for i = 1, snap.start - 1 do out[#out+1] = before[i] end
      for _, l in ipairs(snap.seg) do out[#out+1] = l end
      for i = snap.stop + 1, #before do out[#out+1] = before[i] end
      vim.fn.writefile(out, snap.path)
    end
  end
end

local function compute_cycled_line(line, next_state)
  -- Accept either "* TODO foo" or "* foo"
  local stars, cur_state, rest = line:match('^(%*+)%s+([A-Z]+)%s+(.*)$')
  if not stars then
    stars, rest = line:match('^(%*+)%s+(.*)$')
  end
  if not stars then return nil end
  if next_state == '' then
    return (stars .. ' ' .. rest)
  else
    return (stars .. ' ' .. next_state .. ' ' .. rest)
  end
end

local function safe_set_heading_state(hl, next_state)
  local path = hl.file.filename
  local lnum = (hl.position and hl.position.start_line or 1)
  if lnum < 1 then return false, "Invalid headline position" end

  local st = buf_status_for(path)

  -- If buffer is loaded here and modified, refuse.
  if st.loaded and st.modified then
    return false, "File is open and modified in this Neovim; aborting to avoid data loss."
  end

  -- If not loaded and a swap exists, very likely open elsewhere: refuse.
  if (not st.loaded) and has_swap_for(path) then
    return false, "Detected a swap file for this path (likely open in another Vim). Refusing to edit."
  end

  -- Build new line content
  local new_line

  if st.loaded then
    -- buffer path (unmodified)
    local old = vim.api.nvim_buf_get_lines(st.bufnr, lnum - 1, lnum, false)[1]
    if not old then return false, "Could not read current line" end
    new_line = compute_cycled_line(old, next_state)
    if not new_line then return false, "Not a valid org headline line" end
    vim.api.nvim_buf_set_lines(st.bufnr, lnum - 1, lnum, false, { new_line })
    vim.api.nvim_buf_call(st.bufnr, function() vim.cmd('silent noautocmd write') end)
    return true
  else
    -- on-disk edit
    local lines = vim.fn.readfile(path)
    local old = lines[lnum]
    if not old then return false, "Could not read current line on disk" end
    new_line = compute_cycled_line(old, next_state)
    if not new_line then return false, "Not a valid org headline line" end
    lines[lnum] = new_line
    vim.fn.writefile(lines, path)
    return true
  end
end

-- === headline toolbelt ===
local function with_headline(line_map, cb)
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = line_map[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('No entry under cursor', vim.log.levels.WARN)
    return
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
      lines = vim.api.nvim_buf_get_lines(bufnr, hl.position.start_line - 1, hl.position.end_line, false)
    end
    if #lines == 0 then return end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'org'
    local ui  = vim.api.nvim_list_uis()[1]
    local h   = math.min(#lines + 2, math.floor(ui.height * 0.6))
    local w   = math.min(80, math.floor(ui.width * 0.8))
    local win = vim.api.nvim_open_win(buf, true, {
      relative='editor', style='minimal', border='rounded',
      width=w, height=h, col=math.floor((ui.width - w)/2), row=math.floor((ui.height - h)/2),
      title='Org Preview',
    })
    local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
    vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
  end)
end

local function apply_with_undo_snapshot(cur, snap, op_fn)
  Store.push_undo(make_restore_from_snapshot(snap))
  local p = op_fn()
  vim.defer_fn(function()
    if p and type(p.next) == 'function' then p:next(function() Services.agenda.refresh(cur) end)
    else Services.agenda.refresh(cur) end
  end, 10)
end

-- === state setting helpers ===
local function build_state_shortcuts(states)
  local shortcuts = {}
  local used = { ['0'] = true }
  local conflicts = {}
  for _, st in ipairs(states) do
    local key = st.shortcut
    if not key then
      key = st.name:sub(1, 1):lower()
    end
    if used[key] then
      conflicts[#conflicts + 1] = st.name
    else
      used[key] = true
      shortcuts[#shortcuts + 1] = { key = key, name = st.name, color = st.color }
    end
  end
  return shortcuts, conflicts
end

local function set_state_for_headline(line_map, next_state)
  with_headline(line_map, function(cur, hl)
    local st = buf_status_for(hl.file.filename)
    local snap = st.loaded and snapshot_heading_from_buf(hl)
                 or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
    Store.push_undo(make_restore_from_snapshot(snap))

    local success, err = safe_set_heading_state(hl, next_state)
    if not success then
      vim.notify(err, vim.log.levels.WARN)
      return
    end

    local key = key_for_hl(hl)
    if next_state == 'DONE' then Store.sticky_add(key) else Store.sticky_remove(key) end
    Services.agenda.refresh(cur)
  end)
end

local function show_state_menu(line_map, shortcuts)
  local chunks = { { 'Set state: ', 'Normal' } }
  for i, s in ipairs(shortcuts) do
    local hl_name = 'OrgSuperAgendaStateMenu' .. s.name
    if s.color then
      vim.api.nvim_set_hl(0, hl_name, { fg = s.color, bold = true })
    end
    chunks[#chunks + 1] = { s.key .. '=', 'Comment' }
    chunks[#chunks + 1] = { s.name, s.color and hl_name or 'Normal' }
    if i < #shortcuts then chunks[#chunks + 1] = { '  ', 'Normal' } end
  end
  chunks[#chunks + 1] = { '  ', 'Normal' }
  chunks[#chunks + 1] = { '0=', 'Comment' }
  chunks[#chunks + 1] = { 'clear', 'Normal' }

  vim.api.nvim_echo(chunks, false, {})
  local ok, c = pcall(vim.fn.getcharstr)
  vim.api.nvim_echo({}, false, {})
  if not ok then return end

  local next_state = nil
  if c == '0' then
    next_state = ''
  else
    for _, s in ipairs(shortcuts) do
      if s.key == c then next_state = s.name; break end
    end
  end
  if next_state == nil then return end
  set_state_for_headline(line_map, next_state)
end

-- === keymaps ===
function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -- close
  local function wipe()
    local popup = cfg.popup_mode
    if popup and popup.enabled and popup.hide_command then
      -- Popup mode: detach from tmux session to hide the popup
      vim.fn.system(popup.hide_command)
    else
      -- Normal mode: close buffer
      if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
      require('org-super-agenda').on_close()
    end
  end
  for _, k in ipairs({ 'q', '<Esc>' }) do vim.keymap.set('n', k, wipe, { buffer = buf, silent = true }) end

  -- open file
  vim.keymap.set('n', '<CR>', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(hl.file.filename))
      vim.api.nvim_win_set_cursor(0, { hl.position.start_line, 0 })
      local filebuf = vim.api.nvim_get_current_buf()
      pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = filebuf, once = true,
        callback = function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
            reopen(cur)
          end)
        end,
      })
    end)
  end, { buffer = buf, silent = true })

  -- reschedule / deadline (unchanged but undo-aware)
  vim.keymap.set('n', cfg.keymaps.reschedule, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file.filename)
      local snap = st.loaded and snapshot_heading_from_buf(hl)
                   or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
      local p = hl:set_scheduled()
      local function after() Store.push_undo(make_restore_from_snapshot(snap)); Services.agenda.refresh(cur) end
      if p and type(p.next) == 'function' then p:next(after) else after() end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file.filename)
      local snap = st.loaded and snapshot_heading_from_buf(hl)
                   or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
      local p = hl:set_deadline()
      local function after() Store.push_undo(make_restore_from_snapshot(snap)); Services.agenda.refresh(cur) end
      if p and type(p.next) == 'function' then p:next(after) else after() end
    end)
  end, { buffer = buf, silent = true })

  -- toggle Other
  if cfg.keymaps.toggle_other and cfg.keymaps.toggle_other ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_other, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local c   = get_cfg()
      require('org-super-agenda.config').setup({ show_other_group = not c.show_other_group })
      Services.agenda.refresh(cur)
    end, { buffer = buf, silent = true })
  end

  -- ✅ toggle duplicates
  if cfg.keymaps.toggle_duplicates and cfg.keymaps.toggle_duplicates ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_duplicates, function()
      Services.agenda.toggle_duplicates()
    end, { buffer = buf, silent = true })
  end

  -- priorities
  local function make_set_priority(prio)
    return function()
      with_headline(line_map, function(cur, hl)
        local st = buf_status_for(hl.file.filename)
        local snap = st.loaded and snapshot_heading_from_buf(hl)
                     or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
        Store.push_undo(make_restore_from_snapshot(snap))
        local p = hl:set_priority(prio)
        vim.defer_fn(function()
          if p and type(p.next) == 'function' then p:next(function() Services.agenda.refresh(cur) end)
          else Services.agenda.refresh(cur) end
        end, 10)
      end)
    end
  end
  vim.keymap.set('n', cfg.keymaps.priority_A, make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B, make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C, make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear, make_set_priority(''), { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_up, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file.filename)
      local snap = st.loaded and snapshot_heading_from_buf(hl)
                   or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
      Store.push_undo(make_restore_from_snapshot(snap))
      local p = hl:priority_up()
      vim.defer_fn(function()
        if p and type(p.next) == 'function' then p:next(function() Services.agenda.refresh(cur) end)
        else Services.agenda.refresh(cur) end
      end, 10)
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file.filename)
      local snap = st.loaded and snapshot_heading_from_buf(hl)
                   or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
      Store.push_undo(make_restore_from_snapshot(snap))
      local p = hl:priority_down()
      vim.defer_fn(function()
        if p and type(p.next) == 'function' then p:next(function() Services.agenda.refresh(cur) end)
        else Services.agenda.refresh(cur) end
      end, 10)
    end)
  end, { buffer = buf, silent = true })

  -- Quick TODO filters
  for _, st in ipairs(get_cfg().todo_states or {}) do
    if st.keymap and st.keymap ~= '' and st.name then
      vim.keymap.set('n', st.keymap, function()
        local cur = vim.api.nvim_win_get_cursor(0)
        Services.agenda.refresh(cur, { todo_filter = st.name })
      end, { buffer = buf, silent = true })
    end
  end

  if cfg.keymaps.filter_reset and cfg.keymaps.filter_reset ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_reset, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      Services.agenda.refresh(cur, { todo_filter = nil, headline_filter = nil, query = nil })
    end, { buffer = buf, silent = true })
  end

  -- live filters
  local function live_filter(fuzzy)
    local cur, query = vim.api.nvim_win_get_cursor(0), ''
    local function apply()
      Services.agenda.refresh(cur, { headline_filter = query, headline_fuzzy = fuzzy })
      vim.api.nvim_echo({ { 'Filter: ' .. query } }, false, {}); vim.cmd('redraw')
    end
    vim.api.nvim_echo({ { 'Filter: ' } }, false, {})
    while true do
      local ok, c = pcall(vim.fn.getcharstr); if not ok then break end
      if c == '\027' or c == '\013' then break end
      local bs = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
      if c == '\008' or c == '\127' or c == bs then query = query:sub(1, -2) else query = query .. c end
      apply()
    end
    vim.api.nvim_echo({}, false, {})
  end
  if cfg.keymaps.filter and cfg.keymaps.filter ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter, function() live_filter(false) end, { buffer = buf, silent = true, nowait = true })
  end
  if cfg.keymaps.filter_fuzzy and cfg.keymaps.filter_fuzzy ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_fuzzy, function() live_filter(true) end, { buffer = buf, silent = true, nowait = true })
  end

  -- query input
  if cfg.keymaps.filter_query and cfg.keymaps.filter_query ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_query, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local q = vim.fn.input('Query: ')
      Services.agenda.refresh(cur, { query = q })
    end, { buffer = buf, silent = true })
  end

  -- preview
  if cfg.keymaps.preview and cfg.keymaps.preview ~= '' then
    vim.keymap.set('n', cfg.keymaps.preview, function() preview_headline(line_map) end, { buffer = buf, silent = true })
  end

  -- hide/reset hidden
  if cfg.keymaps.hide_item and cfg.keymaps.hide_item ~= '' then
    vim.keymap.set('n', cfg.keymaps.hide_item, function() require('org-super-agenda').hide_current() end, { buffer = buf, silent = true })
  end
  if cfg.keymaps.reset_hidden and cfg.keymaps.reset_hidden ~= '' then
    vim.keymap.set('n', cfg.keymaps.reset_hidden, function()
      require('org-super-agenda').reset_hidden()
      Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
    end, { buffer = buf, silent = true })
  end

  -- cycle todo (safe across sessions + undoable)
  vim.keymap.set('n', cfg.keymaps.cycle_todo, function()
    with_headline(line_map, function(cur, hl)
      local seq = {}
      for _, s in ipairs(get_cfg().todo_states or {}) do seq[#seq + 1] = s.name end
      if #seq == 0 then return end
      local idx = 0
      for i, v in ipairs(seq) do if v == (hl.todo_value or '') then idx = i; break end end
      local next_state = seq[idx % #seq + 1]

      -- Take snapshot without forcing buffer load if possible
      local st = buf_status_for(hl.file.filename)
      local snap = st.loaded and snapshot_heading_from_buf(hl)
                   or snapshot_heading_from_disk(hl.file.filename, hl.position.start_line)
      Store.push_undo(make_restore_from_snapshot(snap))

      local ok, err = safe_set_heading_state(hl, next_state)
      if not ok then
        vim.notify(err, vim.log.levels.WARN)
        return
      end

      local key = key_for_hl(hl)
      if next_state == 'DONE' then Store.sticky_add(key) else Store.sticky_remove(key) end
      Services.agenda.refresh(cur)
    end)
  end, { buffer = buf, silent = true })

  -- reload
  vim.keymap.set('n', cfg.keymaps.reload, function()
    local cur = vim.api.nvim_win_get_cursor(0)
    Services.agenda.refresh(cur)
  end, { buffer = buf, silent = true })

  -- refile (unchanged)
  if cfg.keymaps.refile and cfg.keymaps.refile ~= '' then
    vim.keymap.set('n', cfg.keymaps.refile, function()
      with_headline(line_map, function(_, hl)
        local pos = hl.position
        if not (pos and pos.start_line and pos.end_line and hl.level) then
          return vim.notify('Cannot refile: missing position info from orgmode.', vim.log.levels.WARN)
        end
        Services.refile_start(hl.file.filename, pos.start_line, pos.end_line, hl.level)
      end)
    end, { buffer = buf, silent = true })
  end

  -- cycle view
  if cfg.keymaps.cycle_view and cfg.keymaps.cycle_view ~= '' then
    vim.keymap.set('n', cfg.keymaps.cycle_view, function() require('org-super-agenda').cycle_view() end, { buffer = buf, silent = true })
  end

  -- set state: direct keymaps (st, sd, etc) + timeout menu fallback
  local prefix = cfg.keymaps.set_state
  if prefix and prefix ~= '' then
    local states = get_cfg().todo_states or {}
    local shortcuts, conflicts = build_state_shortcuts(states)
    if #conflicts > 0 then
      vim.notify(
        'State shortcut conflict for: ' .. table.concat(conflicts, ', ') ..
        '\nAdd explicit "shortcut" field to todo_states config.',
        vim.log.levels.ERROR
      )
    else
      for _, s in ipairs(shortcuts) do
        vim.keymap.set('n', prefix .. s.key, function()
          set_state_for_headline(line_map, s.name)
        end, { buffer = buf, silent = true, nowait = true })
      end
      vim.keymap.set('n', prefix .. '0', function()
        set_state_for_headline(line_map, '')
      end, { buffer = buf, silent = true, nowait = true })
      vim.keymap.set('n', prefix, function()
        show_state_menu(line_map, shortcuts)
      end, { buffer = buf, silent = true })
    end
  end

  -- undo
  vim.keymap.set('n', cfg.keymaps.undo, function()
    Store.pop_undo()
    Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
  end, { buffer = buf, silent = true })

  -- help
  vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })
end

return A

