-- adapters/neovim/backends/orgmode.lua -- headline operations on nvim-orgmode
local guard = require('org-super-agenda.adapters.neovim.guard')
local source = require('org-super-agenda.adapters.neovim.source_orgmode')

local B = { name = 'orgmode', source = source }

local buf_status_for, has_swap_for = guard.buf_status_for, guard.has_swap_for

function B.available()
  return (pcall(require, 'orgmode.api'))
end

local function ref(hl)
  return {
    file = (hl.file and hl.file.filename) or hl.filename,
    line = hl.position and hl.position.start_line,
    end_line = hl.position and hl.position.end_line,
    level = hl.level,
    todo = hl.todo_value,
    done = hl.todo_type == 'DONE',
    native = hl,
  }
end

function B.headline(file, lnum)
  local ok, api_root = pcall(require, 'orgmode.api')
  if not ok then
    return nil
  end
  local org_api = api_root.load and api_root or api_root.org
  local f = org_api.load(file)
  if vim.islist(f) then
    f = f[1]
  end
  if not (f and f.get_headline_on_line) then
    return nil
  end
  local hl = f:get_headline_on_line(lnum)
  return hl and ref(hl) or nil
end

local function get_org_clock()
  local ok_org, org = pcall(require, 'orgmode')
  if not ok_org or type(org.instance) ~= 'function' then
    return nil, 'orgmode not available'
  end
  local ok_inst, inst = pcall(org.instance)
  if not ok_inst or not inst or not inst.clock then
    return nil, 'orgmode clock is unavailable'
  end
  return inst.clock
end

local function clock_in_headline(hl)
  local _, err = get_org_clock()
  if err then
    return nil, err
  end

  if type(hl._do_action) ~= 'function' then
    return nil, 'Selected headline does not support clock actions'
  end

  return hl:_do_action(function()
    local org = require('orgmode')
    local clock = org.instance().clock
    clock:org_clock_in()
  end)
end

local function clock_out_active()
  local clock, err = get_org_clock()
  if not clock then
    return nil, err
  end
  local org = require('orgmode')
  clock:update_clocked_headline()
  local active = clock.clocked_headline
  if not (active and active.is_clocked_in and active:is_clocked_in()) then
    active = org.instance().files:get_clocked_headline()
  end
  if not (active and active.is_clocked_in and active:is_clocked_in()) then
    return nil
  end
  return active.file:update(function()
    local reloaded = active.file:reload_sync():get_closest_headline({ active:get_range().start_line, 0 })
    reloaded:clock_out()
    clock.clocked_headline = nil
  end)
end

local function clock_cancel_active()
  local clock, err = get_org_clock()
  if not clock then
    return nil, err
  end
  local org = require('orgmode')
  clock:update_clocked_headline()
  local active = clock.clocked_headline
  if not (active and active.is_clocked_in and active:is_clocked_in()) then
    active = org.instance().files:get_clocked_headline()
  end
  if not (active and active.is_clocked_in and active:is_clocked_in()) then
    return nil
  end
  return active.file:update(function()
    local reloaded = active.file:reload_sync():get_closest_headline({ active:get_range().start_line, 0 })
    reloaded:cancel_active_clock()
    clock.clocked_headline = nil
  end)
end

local function clock_goto_active()
  local clock, err = get_org_clock()
  if not clock then
    return false, err
  end
  local before = vim.api.nvim_get_current_buf()
  clock:org_clock_goto()
  local after = vim.api.nvim_get_current_buf()
  return before ~= after, nil
end

local function compute_cycled_line(line, next_state)
  -- Accept either "* TODO foo" or "* foo"
  local stars, cur_state, rest = line:match('^(%*+)%s+([A-Z]+)%s+(.*)$')
  if not stars then
    stars, rest = line:match('^(%*+)%s+(.*)$')
  end
  if not stars then
    return nil
  end
  if next_state == '' then
    return (stars .. ' ' .. rest)
  else
    return (stars .. ' ' .. next_state .. ' ' .. rest)
  end
end

local function safe_set_heading_state(hl, next_state)
  local path = (hl.file and hl.file.filename) or hl.filename
  local lnum = (hl.position and hl.position.start_line or 1)
  if lnum < 1 then
    return false, 'Invalid headline position'
  end

  local st = buf_status_for(path)

  -- If buffer is loaded here and modified, refuse.
  if st.loaded and st.modified then
    return false, 'File is open and modified in this Neovim; aborting to avoid data loss.'
  end

  -- If not loaded and a swap exists, very likely open elsewhere: refuse.
  if (not st.loaded) and has_swap_for(path) then
    return false, 'Detected a swap file for this path (likely open in another Vim). Refusing to edit.'
  end

  -- Build new line content
  local new_line

  if st.loaded then
    -- buffer path (unmodified)
    local old = vim.api.nvim_buf_get_lines(st.bufnr, lnum - 1, lnum, false)[1]
    if not old then
      return false, 'Could not read current line'
    end
    new_line = compute_cycled_line(old, next_state)
    if not new_line then
      return false, 'Not a valid org headline line'
    end
    vim.api.nvim_buf_set_lines(st.bufnr, lnum - 1, lnum, false, { new_line })
    vim.api.nvim_buf_call(st.bufnr, function()
      vim.cmd('silent noautocmd write')
    end)
    return true
  else
    -- on-disk edit
    local lines = vim.fn.readfile(path)
    local old = lines[lnum]
    if not old then
      return false, 'Could not read current line on disk'
    end
    new_line = compute_cycled_line(old, next_state)
    if not new_line then
      return false, 'Not a valid org headline line'
    end
    lines[lnum] = new_line
    vim.fn.writefile(lines, path)
    return true
  end
end

local function get_headline_todo_keywords(hl)
  local section = hl and hl._section
  local file = section and section.file
  if not (file and file.get_todo_keywords) then
    return nil
  end
  return file:get_todo_keywords()
end

local function should_use_orgmode_state_transition(hl, next_state)
  if not hl or next_state == '' then
    return false
  end

  local todos = get_headline_todo_keywords(hl)
  if not todos then
    return false
  end

  local current_value = hl.todo_value or (hl._section and hl._section:get_todo()) or ''
  local current_kw = current_value ~= '' and todos:find(current_value) or nil
  local target_kw = todos:find(next_state)

  if not current_kw or not target_kw then
    return false
  end

  return current_kw.sequence_index == target_kw.sequence_index and current_kw.type ~= target_kw.type
end

local function apply_heading_state_via_orgmode(hl, next_state)
  local todos = get_headline_todo_keywords(hl)
  local path = (hl.file and hl.file.filename) or hl.filename
  local start_line = hl.position and hl.position.start_line or 1
  local current_value = hl.todo_value or (hl._section and hl._section:get_todo()) or ''
  local current_kw = current_value ~= '' and todos and todos:find(current_value) or nil
  local target_kw = todos and todos:find(next_state) or nil

  if not todos or not current_kw or not target_kw then
    return false, 'Could not resolve orgmode todo state transition'
  end

  local st = buf_status_for(path)
  if st.loaded and st.modified then
    return false, 'File is open and modified in this Neovim; aborting to avoid data loss.'
  end
  if (not st.loaded) and has_swap_for(path) then
    return false, { kind = 'swap_conflict', path = path }
  end

  local function run_transition()
    local org = require('orgmode')
    local instance = org.instance()
    local mappings = instance and instance.org_mappings
    local current = instance and instance.files and instance.files:get_closest_headline()
    if not current then
      error('orgmode todo transition engine is unavailable', 0)
    end

    local old_state = current:get_todo()
    local was_done = current:is_done()
    current:set_todo(next_state)

    local item = instance.files:get_closest_headline()
    local is_done = item:is_done() and not was_done
    local is_undone = not item:is_done() and was_done

    if not is_done and not is_undone then
      return true
    end

    local org_config = require('orgmode.config')
    local Date = require('orgmode.objects.date')
    local TodoState = require('orgmode.objects.todo_state')
    local repeater_dates = item:get_repeater_dates()

    if #repeater_dates == 0 then
      local log_closed_time = org_config.org_log_done == 'time'
      if log_closed_time then
        if is_done then
          item:set_closed_date()
        elseif is_undone then
          item:remove_closed_date()
        end
      end
      return true
    end

    if not (mappings and mappings._replace_date) then
      error('orgmode repeater engine is unavailable', 0)
    end

    for _, date in ipairs(repeater_dates) do
      mappings:_replace_date(date:apply_repeater())
    end

    item = instance.files:get_closest_headline()
    local new_todo = item:get_todo()
    local todo_state = TodoState:new({ current_state = new_todo, todos = item.file:get_todo_keywords() })
    local reset_keyword = todo_state:get_reset_todo(item, old_state)
    item:set_todo(reset_keyword.value)

    local log_repeat_enabled = org_config.org_log_repeat ~= false
    local prompt_repeat_note = org_config.org_log_repeat == 'note'
    local prompt_done_note = org_config.org_log_done == 'note'
    if log_repeat_enabled then
      item:set_property('LAST_REPEAT', Date.now():to_wrapped_string(false))
      if not prompt_repeat_note and not prompt_done_note then
        local indent = item:get_indent()
        local repeat_note_template = ('%s- State %-12s from %-12s [%s]'):format(
          indent,
          [["]] .. (new_todo or '') .. [["]],
          [["]] .. (old_state or '') .. [["]],
          Date.now():to_string()
        )
        item:add_note({ repeat_note_template })
      end
    end

    return true
  end

  local ok, result = pcall(function()
    if st.loaded then
      return vim.api.nvim_buf_call(st.bufnr, function()
        local view = vim.fn.winsaveview() or {}
        vim.fn.cursor({ start_line, 1 })
        run_transition()
        vim.cmd('silent noautocmd write')
        vim.fn.winrestview(view)
        local ok_reload, reloaded = pcall(function()
          return hl:reload()
        end)
        return ok_reload and reloaded or hl
      end)
    end

    return hl:_do_action(function()
      return run_transition()
    end):wait(20000)
  end)

  if not ok then
    return false, tostring(result)
  end

  return true, result
end

local function apply_heading_state(hl, next_state)
  if should_use_orgmode_state_transition(hl, next_state) then
    return apply_heading_state_via_orgmode(hl, next_state)
  end

  local ok, err = safe_set_heading_state(hl, next_state)
  if not ok then
    return false, err
  end

  local reload_ok, reloaded = pcall(function()
    return hl:reload()
  end)
  if reload_ok and reloaded then
    return true, reloaded
  end

  return true, hl
end

local function open_loaded_datepicker(hl, keyword, bufnr)
  local Calendar = require('orgmode.objects.calendar')
  local Date = require('orgmode.objects.date')

  local get_date = keyword == 'SCHEDULED' and 'get_scheduled_date' or 'get_deadline_date'
  local set_date = keyword == 'SCHEDULED' and 'set_scheduled_date' or 'set_deadline_date'
  local remove_date = keyword == 'SCHEDULED' and 'remove_scheduled_date' or 'remove_deadline_date'
  local title = keyword == 'SCHEDULED' and 'Set schedule' or 'Set deadline'
  local initial = hl._section and hl._section[get_date] and hl._section[get_date](hl._section) or Date.today()

  return Calendar.new({ date = initial, clearable = true, title = title }):open():next(function(new_date, cleared)
    if not new_date and not cleared then
      return
    end

    return vim.api.nvim_buf_call(bufnr, function()
      local view = vim.fn.winsaveview() or {}
      vim.fn.cursor({ hl.position.start_line, 1 })

      local org = require('orgmode')
      local item = org.instance().files:get_closest_headline()
      if not item then
        error('orgmode date change target is unavailable', 0)
      end

      if cleared then
        item[remove_date](item)
      else
        item[set_date](item, new_date)
      end

      vim.cmd('silent noautocmd write')
      vim.fn.winrestview(view)
      return true
    end)
  end)
end

local function open_unloaded_datepicker(hl, keyword)
  local Calendar = require('orgmode.objects.calendar')
  local Date = require('orgmode.objects.date')
  local scheduled = keyword == 'SCHEDULED'
  local initial
  if scheduled then
    initial = hl.scheduled
  else
    initial = hl.deadline
  end
  local title = scheduled and 'Set schedule' or 'Set deadline'
  return Calendar.new({ date = initial or Date.today(), clearable = true, title = title }):open():next(function(new_date, cleared)
    if not new_date and not cleared then
      return
    end
    local value = cleared and '' or new_date
    local p
    if scheduled then
      p = hl:set_scheduled(value)
    else
      p = hl:set_deadline(value)
    end
    return p:next(function()
      return true
    end)
  end)
end

-- Resolves { cancelled = true } when nothing was picked, like the org.nvim backend
local function open_headline_datepicker(hl, keyword)
  local st = buf_status_for(hl.file.filename)
  local p
  if st.loaded then
    p = open_loaded_datepicker(hl, keyword, st.bufnr)
  else
    p = open_unloaded_datepicker(hl, keyword)
  end
  return p:next(function(res)
    if res == nil then
      return { cancelled = true }
    end
    return res
  end)
end

function B.set_state(h, state)
  local ok, updated = apply_heading_state(h.native, state)
  if not ok then
    return false, updated
  end
  return true, ref(updated or h.native)
end

function B.pick_date(h, keyword)
  return open_headline_datepicker(h.native, keyword)
end

function B.set_priority(h, prio)
  return h.native:set_priority(prio)
end

function B.priority_up(h)
  return h.native:priority_up()
end

function B.priority_down(h)
  return h.native:priority_down()
end

function B.clock_in(h)
  return clock_in_headline(h.native)
end

B.clock_out = clock_out_active
B.clock_cancel = clock_cancel_active
B.clock_goto = clock_goto_active

function B.clock_status()
  local ok, org = pcall(require, 'orgmode')
  if not ok or type(org.instance) ~= 'function' then
    return ''
  end
  local ok_inst, inst = pcall(org.instance)
  if not ok_inst or not inst or not inst.clock or type(inst.clock.get_statusline) ~= 'function' then
    return ''
  end
  local ok_status, status = pcall(inst.clock.get_statusline, inst.clock)
  if not ok_status or type(status) ~= 'string' then
    return ''
  end
  return status
end

function B.save_buffer(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('silent noautocmd write')
  end)
  return true
end

function B.section_lines(h)
  local hl = h.native
  if hl._section and hl._section.get_lines then
    return hl._section:get_lines()
  end
  if h.line and h.end_line then
    local bufnr = vim.fn.bufnr(h.file)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(h.file)
    end
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end
    return vim.api.nvim_buf_get_lines(bufnr, h.line - 1, h.end_line, false)
  end
  return {}
end

return B
