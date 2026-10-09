local has_org_nvim = pcall(require, 'org.api')

local describe_org = has_org_nvim and describe or function(name)
  describe(name, function()
    pending('org.nvim is not on the runtimepath')
  end)
end

describe('backend resolution', function()
  local backend = require('org-super-agenda.adapters.neovim.backend')

  it('keeps nvim-orgmode for auto when it is available', function()
    assert.equals('orgmode', backend.resolve_name('auto'))
  end)

  it('accepts explicit names and aliases', function()
    assert.equals('org.nvim', backend.resolve_name('org.nvim'))
    assert.equals('orgmode', backend.resolve_name('nvim-orgmode'))
  end)

  it('rejects unknown backends', function()
    assert.has_error(function()
      backend.resolve_name('emacs')
    end)
  end)
end)

describe_org('org.nvim backend', function()
  local config = require('org-super-agenda.config')
  local Store = require('org-super-agenda.app.store')
  local Services = require('org-super-agenda.app.services')
  local Actions = require('org-super-agenda.adapters.neovim.actions')
  local source = require('org-super-agenda.adapters.neovim.source_org_nvim')

  local dir, original_refresh, original_state, refresh_calls

  local function write(name, lines)
    local path = dir .. '/' .. name
    vim.fn.writefile(lines, path)
    return path
  end

  local function read(path)
    return vim.fn.readfile(path)
  end

  local function find(items, headline)
    for _, it in ipairs(items) do
      if it.headline == headline then
        return it
      end
    end
  end

  local function wipe_buffers()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b):find(dir, 1, true) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end

  local function press(lhs, path, line)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'agenda row' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), { [1] = { file = path, _src_line = line } }, function() end)
    local map = vim.fn.maparg(lhs, 'n', false, true)
    assert.is_truthy(map.callback)
    map.callback()
  end

  before_each(function()
    dir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(dir, 'p')
    require('org').setup({
      agenda_files = { dir .. '/*.org' },
      todo_keywords = { 'TODO', 'PROGRESS', 'WAITING', '|', 'DONE' },
      log_done = 'time',
    })
    config.setup(vim.tbl_deep_extend('force', vim.deepcopy(config.defaults), { backend = 'org.nvim' }))
    original_state = vim.deepcopy(Store.state)
    original_refresh = Services.agenda.refresh
    refresh_calls = 0
    Services.agenda.refresh = function()
      refresh_calls = refresh_calls + 1
    end
  end)

  after_each(function()
    pcall(function()
      require('org.api').clock.cancel()
    end)
    Services.agenda.refresh = original_refresh
    Store.state = original_state
    config.setup(vim.deepcopy(config.defaults))
    wipe_buffers()
    vim.fn.delete(dir, 'rf')
  end)

  it('collects items with inherited tags, dates, properties and ancestry', function()
    write('work.org', {
      '#+FILETAGS: :proj:',
      '* TODO Parent :work:',
      'SCHEDULED: <2026-10-09 Fri 09:00-10:30 +1w>',
      ':PROPERTIES:',
      ':Effort: 1:00',
      ':END:',
      '** WAITING [#A] Child',
      'DEADLINE: <2026-10-12 Mon>',
      'body text',
      '* Event',
      'SCHEDULED: <2026-10-10 Sat>',
      '* Plain note',
      '* DONE Finished',
    })

    local items = source.collect()
    assert.equals(4, #items)

    local parent = find(items, 'Parent')
    assert.are.same({ 'proj', 'work' }, parent.tags)
    assert.equals('TODO', parent.todo_state)
    assert.equals('2026-10-09 09:00-10:30', tostring(parent.scheduled))
    assert.equals('1:00', parent.properties.effort)
    assert.is_true(parent.has_more)
    assert.are.same({}, parent.parents)

    local child = find(items, 'Child')
    assert.equals('A', child.priority)
    assert.equals(2, child.level)
    assert.equals('2026-10-12', tostring(child.deadline))
    assert.is_true(child.has_more)
    assert.equals('Parent', child.parents[1].headline)
    assert.equals(child.file .. ':2', child.parents[1].key)

    local event = find(items, 'Event')
    assert.is_nil(event.todo_state)
    assert.is_false(event.has_more)
    assert.is_nil(find(items, 'Plain note'))
    assert.is_not_nil(find(items, 'Finished'))
  end)

  it('honors org_files overrides and exclusions', function()
    local a = write('a.org', { '* TODO In a' })
    write('b.org', { '* TODO In b' })
    config.setup({ exclude_files = { dir .. '/b.org' } })
    local items = source.collect()
    assert.equals(1, #items)
    assert.equals('In a', items[1].headline)

    config.setup({ org_files = { a }, exclude_files = {} })
    items = source.collect()
    assert.equals(1, #items)
    assert.equals(a, items[1].file)
  end)

  it('sets states through org.nvim, logs CLOSED and keeps DONE sticky', function()
    local path = write('t.org', { '* TODO Task' })
    press('sd', path, 1)
    local lines = read(path)
    assert.equals('* DONE Task', lines[1])
    assert.is_truthy(lines[2]:match('^CLOSED: %['))
    assert.is_true(Store.sticky_has(path .. ':1'))
    assert.equals(1, refresh_calls)

    press('u', path, 1)
    assert.are.same({ '* TODO Task' }, read(path))
  end)

  it('advances repeating tasks instead of finishing them', function()
    local path = write('r.org', { '* TODO Review', 'SCHEDULED: <2026-10-09 Fri +1w>' })
    press('sd', path, 1)
    local text = table.concat(read(path), '\n')
    assert.is_truthy(text:find('* TODO Review', 1, true))
    assert.is_truthy(text:find('<2026-10-16 Fri +1w>', 1, true))
    assert.is_false(Store.sticky_has(path .. ':1'))
  end)

  it('clears the TODO keyword', function()
    local path = write('c.org', { '* WAITING Task' })
    press('s0', path, 1)
    assert.equals('* Task', read(path)[1])
  end)

  it('refuses to edit a file with unsaved changes', function()
    local path = write('m.org', { '* TODO Task' })
    vim.cmd('badd ' .. vim.fn.fnameescape(path))
    local b = vim.fn.bufnr(path)
    vim.fn.bufload(b)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { '* TODO Task edited' })
    local notified
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    press('sd', path, 1)
    vim.notify = original_notify
    assert.is_truthy(tostring(notified):find('modified', 1, true))
    assert.are.same({ '* TODO Task' }, read(path))
  end)

  it('sets and shifts priorities', function()
    local path = write('p.org', { '* TODO Task' })
    press('A', path, 1)
    assert.equals('* TODO [#A] Task', read(path)[1])
    press('-', path, 1)
    assert.equals('* TODO [#B] Task', read(path)[1])
    press('0', path, 1)
    assert.equals('* TODO Task', read(path)[1])
  end)

  it('reschedules with the picked date and removes it', function()
    local path = write('d.org', { '* TODO Task' })
    local cal = require('org.calendar')
    local original_pick = cal.pick
    local seen
    cal.pick = function(opts)
      seen = opts
      return require('org.date').parse('<2026-11-02 Mon>')
    end
    press('cs', path, 1)
    assert.equals('SCHEDULED: <2026-11-02 Mon>', read(path)[2])
    assert.is_false(seen.allow_remove)

    cal.pick = function(opts)
      seen = opts
      return { remove = true }
    end
    press('cs', path, 1)
    cal.pick = original_pick
    assert.is_true(seen.allow_remove)
    assert.are.same({ '* TODO Task' }, read(path))
  end)

  it('clocks in and out and reports the running clock', function()
    local path = write('k.org', { '* TODO Task' })
    local backend = require('org-super-agenda.adapters.neovim.backend').get()
    assert.equals('org.nvim', backend.name)

    press('I', path, 1)
    local items = source.collect()
    assert.is_true(items[1].clocked_in)
    assert.is_truthy(backend.clock_status():find('Task', 1, true))

    press('O', path, 1)
    assert.is_false(require('org.api').clock.is_running())
    assert.is_truthy(table.concat(read(path), '\n'):find('CLOCK: %[.*%]%-%-%['))
    assert.equals('', backend.clock_status())
  end)

  it('starts the schedule picker empty when only a deadline is set', function()
    local path = write('dl.org', { '* TODO Task', 'DEADLINE: <2026-10-20 Tue>' })
    local cal = require('org.calendar')
    local original_pick = cal.pick
    local seen
    cal.pick = function(opts)
      seen = opts
      return nil
    end
    press('cs', path, 1)
    cal.pick = original_pick
    assert.is_nil(seen.default)
    assert.is_false(seen.allow_remove)
    assert.are.same({ '* TODO Task', 'DEADLINE: <2026-10-20 Tue>' }, read(path))
  end)

  it('refuses priority and clock changes on files open elsewhere or modified', function()
    local guard = require('org-super-agenda.adapters.neovim.guard')
    local path = write('g.org', { '* TODO Task' })
    local notes = {}
    local original_notify, original_swap = vim.notify, guard.has_swap_for
    vim.notify = function(msg)
      notes[#notes + 1] = tostring(msg)
    end
    guard.has_swap_for = function()
      return true
    end
    press('A', path, 1)
    press('I', path, 1)
    guard.has_swap_for = original_swap

    vim.cmd('badd ' .. vim.fn.fnameescape(path))
    local b = vim.fn.bufnr(path)
    vim.fn.bufload(b)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { '* TODO Task', 'unsaved' })
    press('A', path, 1)
    vim.notify = original_notify

    assert.are.same({ '* TODO Task' }, read(path))
    assert.is_false(require('org.api').clock.is_running())
    assert.is_truthy(notes[1]:find('swap file', 1, true))
    assert.is_truthy(notes[2]:find('swap file', 1, true))
    assert.is_truthy(notes[3]:find('modified', 1, true))
  end)

  it('undo restores statistics cookies on ancestors', function()
    local path = write('s.org', { '* TODO Parent [0/1]', '** TODO Child', '* TODO Next' })
    press('sd', path, 2)
    assert.is_truthy(read(path)[1]:find('[1/1]', 1, true))
    press('u', path, 2)
    assert.are.same({ '* TODO Parent [0/1]', '** TODO Child', '* TODO Next' }, read(path))
  end)

  local function edit_on_disk(path, lines)
    vim.fn.writefile(lines, path)
    local b = vim.fn.bufnr(path)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
      vim.api.nvim_buf_call(b, function()
        vim.cmd('silent edit!')
      end)
    end
  end

  local function capture_notify(fn)
    local notes = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = tostring(msg)
    end
    local ok, err = pcall(fn)
    vim.notify = original_notify
    assert(ok, err)
    return notes
  end

  it('undo skips instead of swallowing a sibling demoted after the change', function()
    local path = write('sib.org', { '* TODO A', '* TODO B' })
    press('A', path, 1)
    edit_on_disk(path, { '* TODO [#A] A', '** TODO B' })
    local notes = capture_notify(function()
      press('u', path, 1)
    end)
    assert.are.same({ '* TODO [#A] A', '** TODO B' }, read(path))
    assert.is_truthy(notes[1]:find('changed since', 1, true))
  end)

  it('undo never reverts a saved edit elsewhere in the same tree', function()
    local path = write('tree.org', { '* Parent', '** TODO A', '** TODO B' })
    press('A', path, 2)
    edit_on_disk(path, { '* Parent', '** TODO [#A] A', '** TODO B renamed' })
    capture_notify(function()
      press('u', path, 2)
    end)
    assert.are.same({ '* Parent', '** TODO [#A] A', '** TODO B renamed' }, read(path))
  end)

  it('undo never duplicates an entry promoted after the change', function()
    local path = write('promo.org', { '* Parent', '** TODO A', '** TODO B' })
    press('A', path, 2)
    edit_on_disk(path, { '* Parent', '* TODO [#A] A', '** TODO B' })
    capture_notify(function()
      press('u', path, 2)
    end)
    assert.are.same({ '* Parent', '* TODO [#A] A', '** TODO B' }, read(path))
  end)

  it('clocking in refuses when the running clock is in a modified file', function()
    local a = write('ca.org', { '* TODO A' })
    local b = write('cb.org', { '* TODO B' })
    press('I', a, 1)
    local buf = vim.fn.bufnr(a)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'unsaved' })
    local notes = capture_notify(function()
      press('I', b, 1)
    end)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('silent edit!')
    end)
    local status = require('org.api').clock.status()
    assert.equals(a, status.file)
    assert.are.same({ '* TODO B' }, read(b))
    assert.is_truthy(notes[1]:find('modified', 1, true))
  end)

  describe('bulk dates', function()
    local original_select, original_pick

    local function bulk_reschedule(items, stamp)
      config.setup({ bulk_action_prompt = 'select' })
      for _, it in ipairs(items) do
        Store.mark_toggle(string.format('%s:%s', it.file, it._src_line))
      end
      vim.ui.select = function(choices, _, cb)
        for _, c in ipairs(choices) do
          if c.key == 'r' then
            return cb(c)
          end
        end
      end
      local cal = require('org.calendar')
      cal.pick = function()
        return require('org.date').parse(stamp)
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'row' })
      Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), items, function() end)
      vim.fn.maparg('b', 'n', false, true).callback()
    end

    before_each(function()
      original_select = vim.ui.select
      original_pick = require('org.calendar').pick
    end)

    after_each(function()
      vim.ui.select = original_select
      require('org.calendar').pick = original_pick
    end)

    it('reschedules every target through org.nvim and undoes them together', function()
      local path = write('bulk.org', { '* Parent', '** TODO A', '** TODO B' })
      bulk_reschedule({ { file = path, _src_line = 2 }, { file = path, _src_line = 3 } }, '<2026-11-02 Mon>')
      assert.are.same({
        '* Parent',
        '** TODO A',
        'SCHEDULED: <2026-11-02 Mon>',
        '** TODO B',
        'SCHEDULED: <2026-11-02 Mon>',
      }, read(path))
      press('u', path, 2)
      assert.are.same({ '* Parent', '** TODO A', '** TODO B' }, read(path))
    end)

    it('marks several entries DONE in one file and undoes them together', function()
      local path = write('bs.org', { '* TODO A', '* TODO B', '* TODO C' })
      config.setup({ bulk_action_prompt = 'select' })
      for _, l in ipairs({ 3, 1, 2 }) do
        Store.mark_toggle(path .. ':' .. l)
      end
      vim.ui.select = function(choices, opts, cb)
        local want = opts.prompt:find('state', 1, true) and 'DONE' or 's'
        for _, c in ipairs(choices) do
          if c.key == want or c.name == want then
            return cb(c)
          end
        end
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'row' })
      local items = { { file = path, _src_line = 1 }, { file = path, _src_line = 2 }, { file = path, _src_line = 3 } }
      Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), items, function() end)
      vim.fn.maparg('b', 'n', false, true).callback()
      local lines = read(path)
      assert.equals(6, #lines)
      assert.equals('* DONE A', lines[1])
      assert.equals('* DONE B', lines[3])
      assert.equals('* DONE C', lines[5])
      press('u', path, 1)
      assert.are.same({ '* TODO A', '* TODO B', '* TODO C' }, read(path))
    end)

    it('removes the date from every target when it is removed from the first', function()
      local path = write('br.org', {
        '* TODO A',
        'SCHEDULED: <2026-10-20 Tue>',
        '* TODO B',
        'SCHEDULED: <2026-10-21 Wed>',
        '* TODO C',
        'SCHEDULED: <2026-10-22 Thu>',
      })
      config.setup({ bulk_action_prompt = 'select' })
      for _, l in ipairs({ 1, 3, 5 }) do
        Store.mark_toggle(path .. ':' .. l)
      end
      vim.ui.select = function(choices, _, cb)
        for _, c in ipairs(choices) do
          if c.key == 'r' then
            return cb(c)
          end
        end
      end
      require('org.calendar').pick = function()
        return { remove = true }
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'row' })
      local items = { { file = path, _src_line = 1 }, { file = path, _src_line = 3 }, { file = path, _src_line = 5 } }
      Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), items, function() end)
      vim.fn.maparg('b', 'n', false, true).callback()
      assert.are.same({ '* TODO A', '* TODO B', '* TODO C' }, read(path))
    end)

    it('leaves other targets alone when the picker is cancelled', function()
      local path = write('bc.org', { '* TODO A', '* TODO B', 'SCHEDULED: <2026-10-20 Tue>' })
      require('org.calendar').pick = function()
        return nil
      end
      config.setup({ bulk_action_prompt = 'select' })
      Store.mark_toggle(path .. ':1')
      Store.mark_toggle(path .. ':2')
      vim.ui.select = function(choices, _, cb)
        for _, c in ipairs(choices) do
          if c.key == 'r' then
            return cb(c)
          end
        end
      end
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'row' })
      Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), { { file = path, _src_line = 1 }, { file = path, _src_line = 2 } }, function() end)
      vim.fn.maparg('b', 'n', false, true).callback()
      assert.are.same({ '* TODO A', '* TODO B', 'SCHEDULED: <2026-10-20 Tue>' }, read(path))
    end)

    it('refuses the whole batch when any target file is modified', function()
      local a = write('ba.org', { '* TODO A' })
      local b = write('bb.org', { '* TODO B' })
      vim.cmd('badd ' .. vim.fn.fnameescape(b))
      local buf = vim.fn.bufnr(b)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'unsaved' })
      local notes = capture_notify(function()
        bulk_reschedule({ { file = a, _src_line = 1 }, { file = b, _src_line = 1 } }, '<2026-11-02 Mon>')
      end)
      assert.are.same({ '* TODO A' }, read(a))
      assert.are.same({ '* TODO B' }, read(b))
      assert.is_truthy(notes[1]:find('modified', 1, true))
    end)
  end)

  it('undoes overlapping async priority changes one by one', function()
    local path = write('async.org', { '* Parent', '** TODO A', '** TODO B' })
    local b = require('org-super-agenda.adapters.neovim.backend').get()
    local original = b.set_priority
    local pending = {}
    b.set_priority = function(h, prio)
      local cbs, done = {}, false
      local promise = {}
      function promise:next(cb)
        if done then
          cb()
        else
          cbs[#cbs + 1] = cb
        end
        return self
      end
      pending[#pending + 1] = function()
        original(h, prio)
        done = true
        for _, cb in ipairs(cbs) do
          cb()
        end
      end
      return promise
    end
    press('A', path, 2)
    pending[1]()
    press('B', path, 3)
    pending[2]()
    vim.wait(50)
    b.set_priority = original
    assert.are.same({ '* Parent', '** TODO [#A] A', '** TODO [#B] B' }, read(path))
    press('u', path, 2)
    assert.are.same({ '* Parent', '** TODO [#A] A', '** TODO B' }, read(path))
    press('u', path, 2)
    assert.are.same({ '* Parent', '** TODO A', '** TODO B' }, read(path))
  end)

  it('undo of a failed action never overwrites later edits', function()
    local path = write('fail.org', { '* TODO Task' })
    local b = require('org-super-agenda.adapters.neovim.backend').get()
    local original = b.set_priority
    b.set_priority = function()
      error('boom', 0)
    end
    capture_notify(function()
      press('A', path, 1)
    end)
    b.set_priority = original
    edit_on_disk(path, { '* TODO Task edited' })
    capture_notify(function()
      press('u', path, 1)
    end)
    assert.are.same({ '* TODO Task edited' }, read(path))
  end)

  it('undo never writes unsaved edits', function()
    local path = write('u.org', { '* TODO Task' })
    press('A', path, 1)
    local b = vim.fn.bufnr(path)
    vim.api.nvim_buf_set_lines(b, 1, 1, false, { 'unsaved note' })
    local notes = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = tostring(msg)
    end
    press('u', path, 1)
    vim.notify = original_notify
    assert.are.same({ '* TODO [#A] Task' }, read(path))
    assert.is_truthy(notes[1]:find('unsaved', 1, true))
  end)

  it('undo saves through org write hooks', function()
    local path = write('w.org', { '* TODO Task' })
    vim.cmd('badd ' .. vim.fn.fnameescape(path))
    vim.fn.bufload(vim.fn.bufnr(path))
    local hooks = require('org.write_hooks')
    local writes = 0
    hooks.register('osa-test', {
      pre = function()
        writes = writes + 1
      end,
    })
    press('A', path, 1)
    local after_change = writes
    press('u', path, 1)
    hooks.unregister('osa-test')
    assert.is_true(after_change >= 1)
    assert.equals(after_change + 1, writes)
    assert.are.same({ '* TODO Task' }, read(path))
  end)

  it('previews the headline subtree', function()
    local path = write('v.org', { '* TODO Task', 'notes', '** TODO Sub', '* TODO Other' })
    local backend = require('org-super-agenda.adapters.neovim.backend').get()
    local h = backend.headline(path, 1)
    assert.are.same({ '* TODO Task', 'notes', '** TODO Sub' }, backend.section_lines(h))
  end)
end)
