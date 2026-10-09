-- adapters/neovim/backends/org_nvim.lua -- headline operations on org.nvim (xheisenbugx/org.nvim)
local guard = require('org-super-agenda.adapters.neovim.guard')
local source = require('org-super-agenda.adapters.neovim.source_org_nvim')

local B = { name = 'org.nvim', source = source }

function B.available()
  local ok, api = pcall(require, 'org.api')
  return ok and type(api) == 'table' and type(api.has) == 'function' and api.has('1.0') or false
end

local function ref(h)
  return { file = h.file, line = h.line, end_line = h.end_line, level = h.level, todo = h.todo, done = h.done == true, native = h }
end

local SWAP_MSG = 'Detected a swap file for this path (likely open in another Vim). Refusing to edit.'

local function edit_error(path)
  local err = guard.check_editable(path)
  if type(err) == 'table' then
    return SWAP_MSG
  end
  return err
end

local function notify_err(err)
  if err then
    vim.notify(tostring(err), vim.log.levels.WARN, { title = 'org-super-agenda' })
  end
end

function B.headline(file, lnum)
  local h = source.api().headline_at({ file = file, lnum = lnum })
  return h and ref(h) or nil
end

function B.set_state(h, state)
  local err = guard.check_editable(h.file)
  if err then
    return false, err
  end
  local res, set_err = h.native:set_todo(state ~= '' and state or nil)
  if not res then
    return false, set_err or 'Could not change the TODO state'
  end
  return true, ref(h.native)
end

local function input_date(prompt, existing)
  local ok, text = pcall(vim.fn.input, { prompt = prompt .. ': ', default = existing and existing.date or '', cancelreturn = vim.NIL })
  if not ok or text == vim.NIL or text == nil or vim.trim(text) == '' then
    return nil
  end
  return text
end

local function pick_date(prompt, existing)
  local ok_cal, cal = pcall(require, 'org.calendar')
  if not (ok_cal and type(cal.pick) == 'function') then
    return input_date(prompt, existing)
  end
  local default
  if existing then
    default = require('org.api.headline').to_date(existing)
  end
  return cal.pick({ default = default, prompt = prompt, allow_remove = existing ~= nil })
end

-- Synchronous: org.nvim's calendar blocks until a date is picked.
-- Returns { cancelled = true } when nothing was picked.
function B.pick_date(h, keyword)
  local blocked = edit_error(h.file)
  if blocked then
    error(blocked, 0)
  end
  local scheduled = keyword == 'SCHEDULED'
  local existing
  if scheduled then
    existing = h.native.scheduled
  else
    existing = h.native.deadline
  end
  local picked = pick_date(scheduled and 'Schedule' or 'Deadline', existing)
  local value = nil
  if picked and not (type(picked) == 'table' and picked.remove) then
    value = picked
  end
  if not picked or (value == nil and not existing) then
    return { cancelled = true }
  end
  local res, err
  if scheduled then
    res, err = h.native:schedule(value)
  else
    res, err = h.native:set_deadline(value)
  end
  if not res then
    error(err or 'Could not change the date', 0)
  end
end

function B.set_priority(h, prio)
  local blocked = edit_error(h.file)
  if blocked then
    return notify_err(blocked)
  end
  local _, err = h.native:set_priority(prio ~= '' and prio or nil)
  notify_err(err)
end

local function shift_priority(h, dir)
  local blocked = edit_error(h.file)
  if blocked then
    return notify_err(blocked)
  end
  local ok_edit, api_h = pcall(require, 'org.api.headline')
  local ok_prio, prio = pcall(require, 'org.priority')
  if not (ok_edit and ok_prio and api_h.edit and prio.shift) then
    return notify_err('org.nvim priority shifting is unavailable')
  end
  local _, err = api_h.edit(h.native, {}, function(t)
    if not prio.enabled() then
      return nil
    end
    prio.shift(t, dir)
    return true
  end)
  notify_err(err)
end

function B.priority_up(h)
  shift_priority(h, 1)
end

function B.priority_down(h)
  shift_priority(h, -1)
end

local function running_clock_error(api)
  local status = api.clock.status()
  return status and status.file and edit_error(status.file) or nil
end

-- Clocking in also stops (and saves) a clock running elsewhere
function B.clock_in(h)
  local blocked = edit_error(h.file) or running_clock_error(source.api())
  if blocked then
    return nil, blocked
  end
  local res, err = h.native:clock_in()
  if not res then
    return nil, err or 'Could not clock in'
  end
end

function B.clock_out()
  local api = source.api()
  if not api.clock.is_running() then
    return nil
  end
  local blocked = running_clock_error(api)
  if blocked then
    return nil, blocked
  end
  local minutes, err = api.clock.clock_out()
  if minutes == nil and err then
    return nil, err
  end
end

function B.clock_cancel()
  local api = source.api()
  if not api.clock.is_running() then
    return nil
  end
  local blocked = running_clock_error(api)
  if blocked then
    return nil, blocked
  end
  local ok, err = api.clock.cancel()
  if not ok then
    return nil, err
  end
end

function B.clock_goto()
  local ok_org, org = pcall(require, 'org')
  if not (ok_org and type(org.action) == 'function') then
    return false, 'org.nvim not available'
  end
  local before = vim.api.nvim_get_current_buf()
  org.action('clock_goto')
  return before ~= vim.api.nvim_get_current_buf(), nil
end

function B.clock_status()
  local ok_api, api = pcall(require, 'org.api')
  if not ok_api or not api.clock or not api.clock.is_running() then
    return ''
  end
  local ok, status = pcall(function()
    return require('org').statusline()
  end)
  return ok and type(status) == 'string' and status or ''
end

-- Set or (nil) remove a date without prompting, e.g. "<2026-11-02 Mon>"
function B.set_date(h, keyword, value)
  local blocked = edit_error(h.file)
  if blocked then
    return nil, blocked
  end
  local res, err
  if keyword == 'SCHEDULED' then
    res, err = h.native:schedule(value)
  else
    res, err = h.native:set_deadline(value)
  end
  return res and true or nil, err
end

-- Org's own save, so write hooks (org-crypt encryption) run
function B.save_buffer(bufnr)
  local ok_utils, utils = pcall(require, 'org.utils')
  if ok_utils and type(utils.save_buffer) == 'function' then
    local saved, err = utils.save_buffer(bufnr)
    if not saved then
      notify_err('Could not save: ' .. tostring(err))
    end
    return saved
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('silent write')
  end)
  return true
end

function B.section_lines(h)
  local bufnr = vim.fn.bufnr(h.file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, h.line - 1, h.end_line, false)
  end
  return vim.list_slice(vim.fn.readfile(h.file), h.line, h.end_line)
end

return B
