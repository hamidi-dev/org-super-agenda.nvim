-- adapters/neovim/actions.lua
local utils = require('org-super-agenda.adapters.neovim.utils')
local config = require('org-super-agenda.config')
local Services = require('org-super-agenda.app.services')
local Store = require('org-super-agenda.app.store')
local guard = require('org-super-agenda.adapters.neovim.guard')
local backend = require('org-super-agenda.adapters.neovim.backend').get
local A = {}
local function get_cfg()
  return config.get()
end

local function key_for_hl(h)
  return string.format('%s:%s', h.file or '', h.line or 0)
end

local is_swap_error, has_swap_for, buf_status_for = guard.is_swap_error, guard.has_swap_for, guard.buf_status_for

-- === helpers: notifications, snapshots, safe writes ===
local function notify_swap_conflict(path, action)
  local short = vim.fn.fnamemodify(path or '', ':~:.')
  local msg = string.format('%s blocked: swap-file conflict (E325) for %s. Resolve the swap/recovery prompt and try again.', action, short)
  vim.notify(msg, vim.log.levels.WARN, { title = 'org-super-agenda' })
  pcall(vim.api.nvim_echo, { { msg, 'WarningMsg' } }, true, {})
end

local function notify_action_error(action, err, path)
  if type(err) == 'table' and err.kind == 'swap_conflict' then
    notify_swap_conflict(err.path or path, action)
    return
  end

  if type(err) == 'string' and err:find('Detected a swap file', 1, true) then
    notify_swap_conflict(path, action)
    return
  end

  vim.notify(tostring(err), vim.log.levels.WARN, { title = 'org-super-agenda' })
end

-- Snapshot/restore utilities
local function heading_level(line)
  local stars = (line or ''):match('^(%*+)%s')
  return stars and #stars or nil
end

local function heading_range_in_file(all_lines, pos_start)
  local start = pos_start
  while start > 0 and not all_lines[start]:match('^%*+') do
    start = start - 1
  end
  if start == 0 then
    return nil
  end
  local lvl = #(all_lines[start]:match('^(%*+)'))
  local stop = #all_lines
  for i = start + 1, #all_lines do
    local s = all_lines[i]:match('^(%*+)')
    if s and #s <= lvl then
      stop = i - 1
      break
    end
  end
  return start, stop
end

-- The outermost ancestor's subtree: a change can also touch ancestors (statistics cookies)
local function tree_range(lines, pos_start)
  local start = math.min(pos_start, #lines)
  while start > 0 and not heading_level(lines[start]) do
    start = start - 1
  end
  if start == 0 then
    return nil
  end
  local lvl = heading_level(lines[start])
  for i = start - 1, 1, -1 do
    local l = heading_level(lines[i])
    if l and l < lvl then
      start, lvl = i, l
      if l == 1 then
        break
      end
    end
  end
  local _, stop = heading_range_in_file(lines, start)
  return start, stop
end

local function make_snapshot(lines, pos_start)
  local s, e = tree_range(lines, pos_start)
  if not s then
    s, e = pos_start, pos_start
  end
  return { start = s, stop = e, seg = vim.list_slice(lines, s, e) }
end

local function snapshot_heading_from_buf(hl)
  local bufnr = vim.fn.bufnr(hl.file)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(hl.file)
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  local snap = make_snapshot(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), hl.line)
  snap.bufnr, snap.mode = bufnr, 'buffer'
  return snap
end

local function snapshot_heading_from_disk(path, pos_start)
  local snap = make_snapshot(vim.fn.readfile(path), pos_start)
  snap.path, snap.mode = path, 'file'
  return snap
end

local function snapshot_lines(snap)
  if snap.mode == 'buffer' then
    return vim.api.nvim_buf_is_valid(snap.bufnr) and vim.api.nvim_buf_get_lines(snap.bufnr, 0, -1, false) or {}
  end
  return vim.fn.filereadable(snap.path) == 1 and vim.fn.readfile(snap.path) or {}
end

local function region_stop(lines, start)
  if start > #lines or not heading_level(lines[start]) then
    return nil
  end
  local _, stop = heading_range_in_file(lines, start)
  return stop
end

-- Record the region as the action left it; undo only restores while it still
-- looks exactly like this, so later edits (saved or not) are never reverted.
local function seal(snap)
  if snap.post then
    return
  end
  local lines = snapshot_lines(snap)
  local stop = region_stop(lines, snap.start)
  snap.post = stop and vim.list_slice(lines, snap.start, stop) or {}
end

-- Where the region ends now, or nil when it changed since the action (or the
-- action never completed: an unsealed snapshot is never restored)
local function restore_stop(lines, snap)
  if not snap.post then
    return nil
  end
  local stop = region_stop(lines, snap.start)
  if not stop or stop - snap.start + 1 ~= #snap.post then
    return nil
  end
  for i, l in ipairs(snap.post) do
    if lines[snap.start + i - 1] ~= l then
      return nil
    end
  end
  return stop
end

local function notify_undo_skipped(path, why)
  local short = vim.fn.fnamemodify(path or '', ':~:.')
  vim.notify(string.format('Undo skipped: %s %s.', short, why), vim.log.levels.WARN, { title = 'org-super-agenda' })
end

-- Undo never writes a buffer's unsaved edits
local function has_unsaved_edits(path)
  return buf_status_for(path).modified
end

local function make_restore_from_snapshot(snap)
  if snap.mode == 'buffer' then
    return function()
      local path = vim.api.nvim_buf_get_name(snap.bufnr)
      if vim.bo[snap.bufnr].modified then
        return notify_undo_skipped(path, 'has unsaved changes')
      end
      local stop = restore_stop(vim.api.nvim_buf_get_lines(snap.bufnr, 0, -1, false), snap)
      if not stop then
        return notify_undo_skipped(path, 'changed since')
      end
      vim.api.nvim_buf_set_lines(snap.bufnr, snap.start - 1, stop, false, snap.seg)
      backend().save_buffer(snap.bufnr)
    end
  else
    return function()
      if has_unsaved_edits(snap.path) then
        return notify_undo_skipped(snap.path, 'has unsaved changes')
      end
      local before = vim.fn.readfile(snap.path)
      local stop = restore_stop(before, snap)
      if not stop then
        return notify_undo_skipped(snap.path, 'changed since')
      end
      local out = {}
      for i = 1, snap.start - 1 do
        out[#out + 1] = before[i]
      end
      for _, l in ipairs(snap.seg) do
        out[#out + 1] = l
      end
      for i = stop + 1, #before do
        out[#out + 1] = before[i]
      end
      vim.fn.writefile(out, snap.path)
      local bufnr = vim.fn.bufnr(snap.path)
      if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd('silent noautocmd edit')
        end)
      end
    end
  end
end

local function push_bulk_undo(restores)
  if #restores == 0 then
    return
  end
  Store.push_undo(function()
    for i = #restores, 1, -1 do
      pcall(restores[i])
    end
  end)
end

local function upsert_planning_line(lines, headline_lnum, keyword, value)
  local s, e = heading_range_in_file(lines, headline_lnum)
  if not s then
    return false
  end

  local new_stamp = keyword .. ': ' .. value

  -- 1) keyword already on its own line → replace whole line
  local key_pat = '^' .. keyword .. ':'
  for i = s + 1, e do
    if lines[i] and lines[i]:match(key_pat) then
      lines[i] = new_stamp
      return true
    end
  end

  -- 2) keyword inline on a combined planning line (e.g. "SCHEDULED: <…> DEADLINE: <…>")
  local inline_pat = keyword .. ':%s*<[^>]*>'
  for i = s + 1, e do
    local l = lines[i]
    if l and l:match(inline_pat) then
      lines[i] = l:gsub(keyword .. ':%s*<[^>]*>', new_stamp)
      return true
    end
  end

  -- 3) keyword not present yet → append to existing planning line or create one
  --    org parsers only recognise planning when all keywords are on ONE line
  for i = s + 1, e do
    local l = lines[i] or ''
    if l:match('^%*+') then
      break
    end
    if l:match('SCHEDULED:') or l:match('DEADLINE:') or l:match('CLOSED:') then
      lines[i] = l .. ' ' .. new_stamp
      return true
    end
  end
  -- no planning line at all → insert one right after the headline
  table.insert(lines, s + 1, new_stamp)
  return true
end

-- === headline toolbelt ===
local function with_headline(line_map, cb)
  local cur = vim.api.nvim_win_get_cursor(0)
  local it = line_map[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('No entry under cursor', vim.log.levels.WARN)
    return
  end
  local ok, hl = pcall(backend().headline, it.file, it._src_line)
  if not ok then
    vim.notify(tostring(hl), vim.log.levels.WARN, { title = 'org-super-agenda' })
    return
  end
  if not hl then
    return
  end
  cb(cur, hl)
end

local function preview_headline(line_map)
  with_headline(line_map, function(_, hl)
    local lines = backend().section_lines(hl) or {}
    if #lines == 0 then
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'org'
    local ui = vim.api.nvim_list_uis()[1]
    local h = math.min(#lines + 2, math.floor(ui.height * 0.6))
    local w = math.min(80, math.floor(ui.width * 0.8))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      style = 'minimal',
      border = 'rounded',
      width = w,
      height = h,
      col = math.floor((ui.width - w) / 2),
      row = math.floor((ui.height - h) / 2),
      title = 'Org Preview',
    })
    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
  end)
end

local function toggle_group_on_cursor(line_map)
  local cur = vim.api.nvim_win_get_cursor(0)
  local entry = line_map[cur[1]]
  if not (entry and entry._kind == 'group_header' and entry.group_name) then
    return false
  end
  require('org-super-agenda').toggle_group(entry.group_name, cur)
  return true
end

-- Each action seals its own snapshot once its change is complete
local function apply_with_undo_snapshot(cur, snap, op_fn)
  Store.push_undo(make_restore_from_snapshot(snap))
  local ok, p = pcall(op_fn)
  if not ok then
    seal(snap)
    vim.notify(tostring(p), vim.log.levels.WARN, { title = 'org-super-agenda' })
    return
  end
  local async = p and type(p.next) == 'function'
  if async then
    p:next(function()
      seal(snap)
    end)
  else
    seal(snap)
  end
  vim.defer_fn(function()
    if async then
      p:next(function()
        Services.agenda.refresh(cur)
      end)
    else
      Services.agenda.refresh(cur)
    end
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
    local st = buf_status_for(hl.file)
    local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl.file, hl.line)
    Store.push_undo(make_restore_from_snapshot(snap))

    local success, updated = backend().set_state(hl, next_state)
    seal(snap)
    if not success then
      notify_action_error('Set state', updated, hl.file)
      return
    end

    local key = key_for_hl(updated)
    if updated.done then
      Store.sticky_add(key)
    else
      Store.sticky_remove(key)
    end
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
    if i < #shortcuts then
      chunks[#chunks + 1] = { '  ', 'Normal' }
    end
  end
  chunks[#chunks + 1] = { '  ', 'Normal' }
  chunks[#chunks + 1] = { '0=', 'Comment' }
  chunks[#chunks + 1] = { 'clear', 'Normal' }

  vim.api.nvim_echo(chunks, false, {})
  local ok, c = pcall(vim.fn.getcharstr)
  vim.api.nvim_echo({}, false, {})
  if not ok then
    return
  end

  local next_state = nil
  if c == '0' then
    next_state = ''
  else
    for _, s in ipairs(shortcuts) do
      if s.key == c then
        next_state = s.name
        break
      end
    end
  end
  if next_state == nil then
    return
  end
  set_state_for_headline(line_map, next_state)
end

-- === bulk actions ===
local function item_key_from_it(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

-- Remove a planning keyword from a line (inline or standalone)
local function remove_planning_keyword(line, keyword)
  -- inline: "SCHEDULED: <…> DEADLINE: <…>"  →  strip just the keyword+stamp
  local stripped = line:gsub('%s*' .. keyword .. ':%s*<[^>]*>', '')
  -- if the whole line is now empty/whitespace, signal full removal
  if stripped:match('^%s*$') then
    return nil
  end
  return stripped
end

local function resolve_headline(it)
  local ok, hl = pcall(backend().headline, it.file, it._src_line)
  return ok and hl or nil
end

-- Bulk changes run top-down; each one can add lines (CLOSED, SCHEDULED, a
-- LOGBOOK note) and shift the targets below it in the same file.
local function line_count(path)
  local b = vim.fn.bufnr(path)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
    return vim.api.nvim_buf_line_count(b)
  end
  return vim.fn.filereadable(path) == 1 and #vim.fn.readfile(path) or 0
end

local function sort_targets(targets)
  table.sort(targets, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a._src_line < b._src_line
  end)
end

local function new_shifts()
  local shift = {}
  return {
    at = function(it)
      return { file = it.file, _src_line = it._src_line + (shift[it.file] or 0) }
    end,
    moved = function(path, before)
      shift[path] = (shift[path] or 0) + line_count(path) - before
    end,
  }
end

local function find_stamp_near(path, start_line, keyword)
  local lines = vim.fn.readfile(path)
  for i = start_line, math.min(start_line + 5, #lines) do
    if i > start_line and heading_level(lines[i]) then
      break
    end
    local m = (lines[i] or ''):match(keyword .. ':%s*(<[^>]*>)')
    if m then
      return m
    end
  end
  return nil
end

-- Apply a date bulk-op: open datepicker on first_hl, then mirror result to all targets.
-- Handles both "set new date" and "remove date" (r in datepicker).
local function bulk_apply_date(targets, cur, first_hl, snap_first, keyword, open_picker)
  if not first_hl then
    return
  end

  local fname = first_hl.file
  local start_l = first_hl.line
  if not (fname and start_l) then
    vim.notify('bulk_apply_date: cannot resolve headline path/line', vim.log.levels.WARN)
    return
  end

  for _, it in ipairs(targets) do
    local blocked = it.file and guard.check_editable(it.file)
    if blocked then
      notify_action_error(keyword, blocked, it.file)
      return
    end
  end

  -- read planning stamp BEFORE the picker runs (to detect removal afterwards)
  local before_stamp = find_stamp_near(fname, start_l, keyword)
  local shifts = new_shifts()
  local first_lines = line_count(fname)

  local ok_p, p = pcall(open_picker, first_hl)
  if not ok_p then
    if is_swap_error(p) then
      notify_swap_conflict(fname, keyword)
    else
      vim.notify('Could not open datepicker: ' .. tostring(p), vim.log.levels.WARN)
    end
    return
  end

  local function after_first(result)
    local after_stamp = find_stamp_near(fname, start_l, keyword)
    local removed = (before_stamp ~= nil and after_stamp == nil)
    local cancelled = type(result) == 'table' and result.cancelled
    if cancelled or not (removed or after_stamp) then
      return Services.agenda.refresh(cur)
    end
    local restores = { make_restore_from_snapshot(snap_first) }
    seal(snap_first)
    shifts.moved(fname, first_lines)
    local set_date = backend().set_date

    for i = 2, #targets do
      local it = shifts.at(targets[i])
      local path2, lnum2 = it.file, it._src_line
      local before = path2 and line_count(path2)
      local h2 = set_date and resolve_headline(it)
      if h2 then
        local snap2 = snapshot_heading_from_disk(path2, h2.line)
        restores[#restores + 1] = make_restore_from_snapshot(snap2)
        local _, err = set_date(h2, keyword, (not removed) and after_stamp or nil)
        if err then
          notify_action_error(keyword, err, path2)
        end
        seal(snap2)
        shifts.moved(path2, before)
      elseif path2 and lnum2 and not set_date then
        local snap2 = snapshot_heading_from_disk(path2, lnum2)
        restores[#restores + 1] = make_restore_from_snapshot(snap2)
        local flines = vim.fn.readfile(path2)

        if removed then
          -- strip the keyword from every line it appears on
          for li = lnum2, math.min(lnum2 + 5, #flines) do
            local l = flines[li] or ''
            if l:match(keyword .. ':') then
              local new_l = remove_planning_keyword(l, keyword)
              if new_l == nil then
                table.remove(flines, li)
              else
                flines[li] = new_l
              end
              break
            end
          end
        else
          -- set the new stamp (after_stamp may be nil if user picked nothing — skip)
          if after_stamp then
            upsert_planning_line(flines, lnum2, keyword, after_stamp)
          end
        end

        vim.fn.writefile(flines, path2)
        local bufnr2 = vim.fn.bufnr(path2)
        if bufnr2 ~= -1 and vim.api.nvim_buf_is_loaded(bufnr2) then
          vim.api.nvim_buf_call(bufnr2, function()
            vim.cmd('silent noautocmd edit')
          end)
        end
        seal(snap2)
        shifts.moved(path2, before)
      end
    end

    push_bulk_undo(restores)
    Store.mark_clear()
    Services.agenda.refresh(cur)
  end

  if p and type(p.next) == 'function' then
    p:next(after_first)
  else
    after_first(p)
  end
end

local function bulk_action_menu(line_map)
  local marked = Store.get_marked()
  if #marked == 0 then
    vim.notify('No items marked. Use `m` to mark items first.', vim.log.levels.WARN)
    return
  end

  -- collect item objects for marked keys
  local items_by_key = {}
  for _, it in pairs(line_map) do
    if it and it.file then
      items_by_key[item_key_from_it(it)] = it
    end
  end

  local targets = {}
  for _, k in ipairs(marked) do
    if items_by_key[k] then
      targets[#targets + 1] = items_by_key[k]
    end
  end

  if #targets == 0 then
    vim.notify('Marked items not found in current view.', vim.log.levels.WARN)
    return
  end
  sort_targets(targets)

  -- resolve first headline + snapshot (needed for r/d datepicker actions)
  local first_hl, snap_first
  do
    for _, it in ipairs(targets) do
      local hl = resolve_headline(it)
      if hl then
        first_hl = hl
        local fname_hl = hl.file
        local st = buf_status_for(fname_hl)
        if st.loaded and st.modified then
          vim.notify('File is open and modified; save first.', vim.log.levels.WARN)
          return
        end
        snap_first = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(fname_hl, hl.line)
        break
      end
    end
  end

  local function apply_bulk_state(next_state, cur)
    local restores = {}
    local shifts = new_shifts()
    for _, target in ipairs(targets) do
      local hl = resolve_headline(shifts.at(target))
      if hl then
        local hl_fname = hl.file
        local st = buf_status_for(hl_fname)
        local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl_fname, hl.line)
        restores[#restores + 1] = make_restore_from_snapshot(snap)
        local before = line_count(hl_fname)
        local ok3, updated = backend().set_state(hl, next_state)
        seal(snap)
        shifts.moved(hl_fname, before)
        if not ok3 then
          notify_action_error('Bulk state change', updated, hl.file)
        else
          local key = key_for_hl(updated or hl)
          if updated and updated.done then
            Store.sticky_add(key)
          else
            Store.sticky_remove(key)
          end
        end
      end
    end
    push_bulk_undo(restores)
    Store.mark_clear()
    Services.agenda.refresh(cur)
  end

  local function choose_bulk_state_select(cur)
    local shortcuts, _ = build_state_shortcuts(get_cfg().todo_states or {})
    if #shortcuts == 0 then
      return
    end
    local options = { { key = '0', name = 'clear' } }
    for _, s in ipairs(shortcuts) do
      options[#options + 1] = { key = s.key, name = s.name }
    end
    vim.ui.select(options, {
      prompt = 'Bulk state:',
      format_item = function(item)
        return string.format('%s = %s', item.key, item.name)
      end,
    }, function(choice)
      if not choice then
        return
      end
      local next_state = (choice.key == '0') and '' or choice.name
      apply_bulk_state(next_state, cur)
    end)
  end

  local function choose_bulk_state_keys(cur)
    local shortcuts, _ = build_state_shortcuts(get_cfg().todo_states or {})
    if #shortcuts == 0 then
      return
    end
    local sch = { { '0', 'Comment' }, { '=clear  ', 'Normal' } }
    for _, s in ipairs(shortcuts) do
      sch[#sch + 1] = { s.key, 'Comment' }
      sch[#sch + 1] = { '=' .. s.name .. '  ', 'Normal' }
    end
    vim.api.nvim_echo(sch, false, {})
    local ok2, c2 = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({}, false, {})
    if not ok2 then
      return
    end

    local next_state
    if c2 == '0' then
      next_state = ''
    else
      for _, s in ipairs(shortcuts) do
        if s.key == c2 then
          next_state = s.name
          break
        end
      end
    end
    if next_state == nil then
      return
    end
    apply_bulk_state(next_state, cur)
  end

  local count = #targets
  local mode = (get_cfg().bulk_action_prompt == 'select') and 'select' or 'keys'

  if mode == 'select' then
    local actions = {
      { key = 's', label = 'set state' },
      { key = 'r', label = 'reschedule' },
      { key = 'd', label = 'deadline' },
    }
    vim.ui.select(actions, {
      prompt = string.format('Bulk (%d) action:', count),
      format_item = function(item)
        return string.format('%s = %s', item.key, item.label)
      end,
    }, function(choice)
      if not choice then
        return
      end
      local cur = vim.api.nvim_win_get_cursor(0)
      if choice.key == 's' then
        choose_bulk_state_select(cur)
      elseif choice.key == 'r' then
        -- bulk reschedule: prompt once via first item, apply result to all
        bulk_apply_date(targets, cur, first_hl, snap_first, 'SCHEDULED', function(hl)
          return backend().pick_date(hl, 'SCHEDULED')
        end)
      elseif choice.key == 'd' then
        -- bulk deadline: same pattern
        bulk_apply_date(targets, cur, first_hl, snap_first, 'DEADLINE', function(hl)
          return backend().pick_date(hl, 'DEADLINE')
        end)
      end
    end)
  else
    local chunks = {
      { 'Bulk (' .. count .. '): ', 'Normal' },
      { 's', 'Comment' },
      { '=state  ', 'Normal' },
      { 'r', 'Comment' },
      { '=reschedule  ', 'Normal' },
      { 'd', 'Comment' },
      { '=deadline', 'Normal' },
    }
    vim.api.nvim_echo(chunks, false, {})
    local ok, c = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({}, false, {})
    if not ok then
      return
    end

    local cur = vim.api.nvim_win_get_cursor(0)
    if c == 's' then
      choose_bulk_state_keys(cur)
    elseif c == 'r' then
      -- bulk reschedule: prompt once via first item, apply result to all
      bulk_apply_date(targets, cur, first_hl, snap_first, 'SCHEDULED', function(hl)
        return backend().pick_date(hl, 'SCHEDULED')
      end)
    elseif c == 'd' then
      -- bulk deadline: same pattern
      bulk_apply_date(targets, cur, first_hl, snap_first, 'DEADLINE', function(hl)
        return backend().pick_date(hl, 'DEADLINE')
      end)
    end
  end
end

-- === keymaps ===
function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -- close
  local function wipe()
    local popup = get_cfg().popup_mode
    -- Check enabled lazily at call time: explicit config OR env var set in the nvim session.
    -- The env var approach is the zero-config path for the tmux script.
    local enabled = popup and (popup.enabled or vim.env.ORG_SUPER_AGENDA_POPUP == '1')
    if enabled and popup and popup.hide_command then
      -- Popup mode: detach from tmux session to hide the popup
      vim.fn.system(popup.hide_command)
    else
      -- Normal mode: close buffer and window
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      require('org-super-agenda').on_close()
    end
  end
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, wipe, { buffer = buf, silent = true })
  end

  -- edit file in floating window (configurable keymap, default Enter)
  if cfg.keymaps.edit and cfg.keymaps.edit ~= '' then
    vim.keymap.set('n', cfg.keymaps.edit, function()
      with_headline(line_map, function(cur, hl)
        local agendabuf = vim.api.nvim_get_current_buf()
        vim.cmd('edit ' .. vim.fn.fnameescape(hl.file))
        vim.api.nvim_win_set_cursor(0, { hl.line, 0 })
        local filebuf = vim.api.nvim_get_current_buf()
        pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })

        -- Add q/Esc keymaps to file buffer for consistent close behavior
        local function close_file()
          if vim.api.nvim_buf_is_valid(filebuf) then
            pcall(vim.api.nvim_buf_delete, filebuf, { force = false })
          end
        end
        for _, k in ipairs({ 'q', '<Esc>' }) do
          vim.keymap.set('n', k, close_file, { buffer = filebuf, silent = true })
        end

        vim.api.nvim_create_autocmd('BufWinLeave', {
          buffer = filebuf,
          once = true,
          callback = function()
            vim.schedule(function()
              pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
              reopen(cur)
            end)
          end,
        })
      end)
    end, { buffer = buf, silent = true })
  end

  -- goto: close float and open file in previous window
  local function goto_headline()
    local popup = cfg.popup_mode
    if popup and popup.enabled then
      vim.notify('goto not available in popup mode', vim.log.levels.WARN)
      return
    end

    with_headline(line_map, function(cur, hl)
      local ViewPort = require('org-super-agenda.adapters.neovim.view_float')
      local prev_win = ViewPort.prev_win()

      -- Close the floating window
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
      require('org-super-agenda').on_close()

      -- Switch to previous window and open file
      if prev_win and vim.api.nvim_win_is_valid(prev_win) then
        vim.api.nvim_set_current_win(prev_win)
      end
      vim.cmd('edit ' .. vim.fn.fnameescape(hl.file))
      vim.api.nvim_win_set_cursor(0, { hl.line, 0 })
    end)
  end

  if cfg.keymaps['goto'] and cfg.keymaps['goto'] ~= '' then
    vim.keymap.set('n', cfg.keymaps['goto'], goto_headline, { buffer = buf, silent = true })
  end

  -- reschedule / deadline (unchanged but undo-aware)
  vim.keymap.set('n', cfg.keymaps.reschedule, function()
    with_headline(line_map, function(cur, hl)
      local path = hl.file
      local st = buf_status_for(path)
      if (not st.loaded) and has_swap_for(path) then
        notify_swap_conflict(path, 'Reschedule')
        return
      end
      local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(path, hl.line)
      local ok_p, p = pcall(function()
        return backend().pick_date(hl, 'SCHEDULED')
      end)
      if not ok_p then
        if is_swap_error(p) then
          notify_swap_conflict(path, 'Reschedule')
        else
          vim.notify('Could not open datepicker: ' .. tostring(p), vim.log.levels.WARN)
        end
        return
      end
      local function after()
        Store.push_undo(make_restore_from_snapshot(snap))
        seal(snap)
        Services.agenda.refresh(cur)
      end
      if p and type(p.next) == 'function' then
        p:next(after)
      else
        after()
      end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local path = hl.file
      local st = buf_status_for(path)
      if (not st.loaded) and has_swap_for(path) then
        notify_swap_conflict(path, 'Set deadline')
        return
      end
      local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(path, hl.line)
      local ok_p, p = pcall(function()
        return backend().pick_date(hl, 'DEADLINE')
      end)
      if not ok_p then
        if is_swap_error(p) then
          notify_swap_conflict(path, 'Set deadline')
        else
          vim.notify('Could not open datepicker: ' .. tostring(p), vim.log.levels.WARN)
        end
        return
      end
      local function after()
        Store.push_undo(make_restore_from_snapshot(snap))
        seal(snap)
        Services.agenda.refresh(cur)
      end
      if p and type(p.next) == 'function' then
        p:next(after)
      else
        after()
      end
    end)
  end, { buffer = buf, silent = true })

  -- toggle Other
  if cfg.keymaps.toggle_other and cfg.keymaps.toggle_other ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_other, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local c = get_cfg()
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
        local st = buf_status_for(hl.file)
        local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl.file, hl.line)
        apply_with_undo_snapshot(cur, snap, function()
          return backend().set_priority(hl, prio)
        end)
      end)
    end
  end
  vim.keymap.set('n', cfg.keymaps.priority_A, make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B, make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C, make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear, make_set_priority(''), { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_up, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file)
      local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl.file, hl.line)
      apply_with_undo_snapshot(cur, snap, function()
        return backend().priority_up(hl)
      end)
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down, function()
    with_headline(line_map, function(cur, hl)
      local st = buf_status_for(hl.file)
      local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl.file, hl.line)
      apply_with_undo_snapshot(cur, snap, function()
        return backend().priority_down(hl)
      end)
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
      vim.api.nvim_echo({ { 'Filter: ' .. query } }, false, {})
      vim.cmd('redraw')
    end
    vim.api.nvim_echo({ { 'Filter: ' } }, false, {})
    while true do
      local ok, c = pcall(vim.fn.getcharstr)
      if not ok then
        break
      end
      if c == '\027' or c == '\013' then
        break
      end
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
    vim.keymap.set('n', cfg.keymaps.filter, function()
      live_filter(false)
    end, { buffer = buf, silent = true, nowait = true })
  end
  if cfg.keymaps.filter_fuzzy and cfg.keymaps.filter_fuzzy ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_fuzzy, function()
      live_filter(true)
    end, { buffer = buf, silent = true, nowait = true })
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
    vim.keymap.set('n', cfg.keymaps.preview, function()
      preview_headline(line_map)
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.clock_in and cfg.keymaps.clock_in ~= '' then
    vim.keymap.set('n', cfg.keymaps.clock_in, function()
      with_headline(line_map, function(cur, hl)
        local p, err = backend().clock_in(hl)
        if err then
          vim.notify(err, vim.log.levels.WARN)
          return
        end
        if p and type(p.next) == 'function' then
          p:next(function()
            Services.agenda.refresh(cur)
          end)
        else
          Services.agenda.refresh(cur)
        end
      end)
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.clock_out and cfg.keymaps.clock_out ~= '' then
    vim.keymap.set('n', cfg.keymaps.clock_out, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local p, err = backend().clock_out()
      if err then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      if p and type(p.next) == 'function' then
        p:next(function()
          Services.agenda.refresh(cur)
        end)
      else
        Services.agenda.refresh(cur)
      end
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.clock_cancel and cfg.keymaps.clock_cancel ~= '' then
    vim.keymap.set('n', cfg.keymaps.clock_cancel, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local p, err = backend().clock_cancel()
      if err then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      if p and type(p.next) == 'function' then
        p:next(function()
          Services.agenda.refresh(cur)
        end)
      else
        Services.agenda.refresh(cur)
      end
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.clock_goto and cfg.keymaps.clock_goto ~= '' then
    vim.keymap.set('n', cfg.keymaps.clock_goto, function()
      local agendabuf = vim.api.nvim_get_current_buf()
      local cur = vim.api.nvim_win_get_cursor(0)
      local jumped, err = backend().clock_goto()
      if err then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      if not jumped then
        return
      end
      local filebuf = vim.api.nvim_get_current_buf()
      if filebuf == agendabuf then
        return
      end
      pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = filebuf,
        once = true,
        callback = function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
            reopen(cur)
          end)
        end,
      })
    end, { buffer = buf, silent = true })
  end

  -- fold + fallback: toggle group fold on group header, otherwise run fold_item_action
  local fold_actions = {
    ['goto'] = goto_headline,
    preview = function()
      preview_headline(line_map)
    end,
  }
  if cfg.keymaps.fold_or_action and cfg.keymaps.fold_or_action ~= '' then
    vim.keymap.set('n', cfg.keymaps.fold_or_action, function()
      if not toggle_group_on_cursor(line_map) then
        local action = fold_actions[cfg.fold_item_action] or fold_actions['preview']
        action()
      end
    end, { buffer = buf, silent = true })
  end

  if cfg.keymaps.fold_all and cfg.keymaps.fold_all ~= '' then
    vim.keymap.set('n', cfg.keymaps.fold_all, function()
      require('org-super-agenda').fold_all()
    end, { buffer = buf, silent = true, nowait = true })
  end

  if cfg.keymaps.unfold_all and cfg.keymaps.unfold_all ~= '' then
    vim.keymap.set('n', cfg.keymaps.unfold_all, function()
      require('org-super-agenda').unfold_all()
    end, { buffer = buf, silent = true, nowait = true })
  end

  -- hide/reset hidden
  if cfg.keymaps.hide_item and cfg.keymaps.hide_item ~= '' then
    vim.keymap.set('n', cfg.keymaps.hide_item, function()
      require('org-super-agenda').hide_current()
    end, { buffer = buf, silent = true })
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
      for _, s in ipairs(get_cfg().todo_states or {}) do
        seq[#seq + 1] = s.name
      end
      if #seq == 0 then
        return
      end
      local idx = 0
      for i, v in ipairs(seq) do
        if v == (hl.todo or '') then
          idx = i
          break
        end
      end
      local next_state = seq[idx % #seq + 1]

      -- Take snapshot without forcing buffer load if possible
      local st = buf_status_for(hl.file)
      local snap = st.loaded and snapshot_heading_from_buf(hl) or snapshot_heading_from_disk(hl.file, hl.line)
      Store.push_undo(make_restore_from_snapshot(snap))

      local ok, updated = backend().set_state(hl, next_state)
      seal(snap)
      if not ok then
        notify_action_error('Cycle TODO', updated, hl.file)
        return
      end

      local key = key_for_hl(updated)
      if updated.done then
        Store.sticky_add(key)
      else
        Store.sticky_remove(key)
      end
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
        if not (hl.line and hl.end_line and hl.level) then
          return vim.notify('Cannot refile: missing position info from the org backend.', vim.log.levels.WARN)
        end
        Services.refile_start(hl.file, hl.line, hl.end_line, hl.level)
      end)
    end, { buffer = buf, silent = true })
  end

  -- cycle view
  if cfg.keymaps.cycle_view and cfg.keymaps.cycle_view ~= '' then
    vim.keymap.set('n', cfg.keymaps.cycle_view, function()
      require('org-super-agenda').cycle_view()
    end, { buffer = buf, silent = true })
  end

  -- set state: direct keymaps (st, sd, etc) + timeout menu fallback
  local prefix = cfg.keymaps.set_state
  if prefix and prefix ~= '' then
    local states = get_cfg().todo_states or {}
    local shortcuts, conflicts = build_state_shortcuts(states)
    if #conflicts > 0 then
      vim.notify(
        'State shortcut conflict for: ' .. table.concat(conflicts, ', ') .. '\nAdd explicit "shortcut" field to todo_states config.',
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

  -- bulk: mark toggle
  if cfg.keymaps.bulk_mark and cfg.keymaps.bulk_mark ~= '' then
    vim.keymap.set('n', cfg.keymaps.bulk_mark, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local it = line_map[cur[1]]
      if not (it and it.file) then
        return
      end
      Store.mark_toggle(item_key_from_it(it))
      Services.agenda.refresh(cur)
    end, { buffer = buf, silent = true, nowait = true })
  end

  -- bulk: unmark all
  if cfg.keymaps.bulk_unmark_all and cfg.keymaps.bulk_unmark_all ~= '' then
    vim.keymap.set('n', cfg.keymaps.bulk_unmark_all, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      Store.mark_clear()
      Services.agenda.refresh(cur)
    end, { buffer = buf, silent = true, nowait = true })
  end

  -- bulk: reselect last marks (like vim gv for visual)
  if cfg.keymaps.bulk_reselect and cfg.keymaps.bulk_reselect ~= '' then
    vim.keymap.set('n', cfg.keymaps.bulk_reselect, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      if Store.mark_restore_last() then
        Services.agenda.refresh(cur)
      else
        vim.notify('No previous marks to restore.', vim.log.levels.INFO)
      end
    end, { buffer = buf, silent = true, nowait = true })
  end

  -- bulk: action menu
  if cfg.keymaps.bulk_action and cfg.keymaps.bulk_action ~= '' then
    vim.keymap.set('n', cfg.keymaps.bulk_action, function()
      bulk_action_menu(line_map)
    end, { buffer = buf, silent = true })
  end

  -- open view picker
  if cfg.keymaps.open_view and cfg.keymaps.open_view ~= '' then
    vim.keymap.set('n', cfg.keymaps.open_view, function()
      require('org-super-agenda').show_view_picker()
    end, { buffer = buf, silent = true })
  end

  -- help
  vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })
end

return A
