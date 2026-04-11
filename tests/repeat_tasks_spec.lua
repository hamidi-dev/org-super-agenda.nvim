local Actions = require('org-super-agenda.adapters.neovim.actions')
local Store = require('org-super-agenda.app.store')
local Services = require('org-super-agenda.app.services')
local config = require('org-super-agenda.config')

describe('repeat task support', function()
  local original_state
  local original_refresh
  local original_notify
  local original_loaded = {}
  local temp_files = {}
  local refresh_calls = 0
  local notifications = {}

  local module_names = {
    'orgmode',
    'orgmode.api',
    'orgmode.config',
    'orgmode.objects.date',
    'orgmode.objects.todo_state',
  }

  local function write_temp_org(lines)
    local path = vim.fn.tempname() .. '.org'
    vim.fn.writefile(lines, path)
    temp_files[#temp_files + 1] = path
    return path
  end

  local function setup_agenda_buffer(path)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'agenda row' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    Actions.set_keymaps(buf, vim.api.nvim_get_current_win(), { [1] = { file = path, _src_line = 1 } }, function() end)
    return buf
  end

  local function invoke_buffer_mapping(lhs)
    local map = vim.fn.maparg(lhs, 'n', false, true)
    assert.is_truthy(map)
    assert.is_truthy(map.callback)
    map.callback()
  end

  local function setup_fake_org(opts)
    local path = opts.path
    local todo = opts.todo or 'TODO'
    local replaced = {}

    local kw_todo = { value = 'TODO', type = 'TODO', index = 1, sequence_index = 1 }
    local kw_done = { value = 'DONE', type = 'DONE', index = 2, sequence_index = 1 }
    local todo_keywords = {
      find = function(_, value)
        if value == 'TODO' then
          return kw_todo
        end
        if value == 'DONE' then
          return kw_done
        end
      end,
      all = function()
        return { kw_todo, kw_done }
      end,
    }

    local internal_file = {
      filename = path,
      get_todo_keywords = function()
        return todo_keywords
      end,
    }

    local internal = {
      file = internal_file,
      todo = todo,
      properties = {},
      notes = {},
      repeater_dates = opts.repeater_dates or {},
      closed_set = false,
      get_todo = function(self)
        return self.todo
      end,
      is_done = function(self)
        return self.todo == 'DONE'
      end,
      set_todo = function(self, keyword)
        self.todo = keyword
      end,
      get_repeater_dates = function(self)
        return self.repeater_dates
      end,
      set_closed_date = function(self)
        self.closed_set = true
      end,
      remove_closed_date = function(self)
        self.closed_set = false
      end,
      set_property = function(self, key, value)
        self.properties[key] = value
      end,
      add_note = function(self, note)
        table.insert(self.notes, note)
      end,
      get_indent = function()
        return ''
      end,
    }

    local api_headline = {
      file = { filename = path },
      position = { start_line = 1, end_line = 1 },
      todo_value = todo,
      todo_type = todo_keywords:find(todo).type,
      properties = {},
      _section = internal,
    }

    function api_headline:reload()
      self.todo_value = internal:get_todo()
      local kw = todo_keywords:find(self.todo_value)
      self.todo_type = kw and kw.type or ''
      self.properties = vim.deepcopy(internal.properties)
      return self
    end

    function api_headline:_do_action(action)
      return {
        wait = function()
          action()
          return self:reload()
        end,
      }
    end

    local fake_instance = {
      files = {
        get_closest_headline = function()
          return internal
        end,
      },
      org_mappings = {
        _replace_date = function(_, date)
          table.insert(replaced, date.kind)
        end,
      },
    }

    package.loaded['orgmode'] = {
      instance = function()
        return fake_instance
      end,
    }

    package.loaded['orgmode.api'] = {
      load = function(requested)
        if requested == path then
          return {
            get_headline_on_line = function(_, line)
              if line == 1 then
                return api_headline
              end
            end,
          }
        end
        return {}
      end,
      org = {},
    }

    package.loaded['orgmode.config'] = {
      org_log_repeat = true,
      org_log_done = 'time',
    }

    package.loaded['orgmode.objects.date'] = {
      now = function()
        return {
          to_wrapped_string = function()
            return '[2026-04-11 Fri 12:00]'
          end,
          to_string = function()
            return '2026-04-11 Fri 12:00'
          end,
        }
      end,
    }

    package.loaded['orgmode.objects.todo_state'] = {
      new = function(_, _)
        return {
          get_reset_todo = function()
            return kw_todo
          end,
        }
      end,
    }

    return {
      api_headline = api_headline,
      internal = internal,
      replaced = replaced,
    }
  end

  before_each(function()
    original_state = vim.deepcopy(Store.state)
    original_refresh = Services.agenda.refresh
    original_notify = vim.notify
    refresh_calls = 0
    notifications = {}
    temp_files = {}

    for _, name in ipairs(module_names) do
      original_loaded[name] = package.loaded[name]
    end

    Services.agenda.refresh = function()
      refresh_calls = refresh_calls + 1
    end
    vim.notify = function(msg)
      notifications[#notifications + 1] = msg
    end

    Store.state = vim.deepcopy(original_state)
    config.setup(vim.deepcopy(config.defaults))
  end)

  after_each(function()
    Services.agenda.refresh = original_refresh
    vim.notify = original_notify
    Store.state = vim.deepcopy(original_state)
    config.setup(vim.deepcopy(config.defaults))

    for _, name in ipairs(module_names) do
      package.loaded[name] = original_loaded[name]
    end

    for _, path in ipairs(temp_files) do
      pcall(vim.fn.delete, path)
    end
  end)

  it('advances repeater metadata and resets to TODO when marking a repeating task done', function()
    local path = write_temp_org({ '* TODO Weekly review' })
    local env = setup_fake_org({
      path = path,
      repeater_dates = {
        {
          kind = 'scheduled',
          apply_repeater = function(self)
            return { kind = self.kind }
          end,
        },
        {
          kind = 'deadline',
          apply_repeater = function(self)
            return { kind = self.kind }
          end,
        },
      },
    })

    setup_agenda_buffer(path)
    invoke_buffer_mapping('sd')

    assert.are.same({ 'scheduled', 'deadline' }, env.replaced)
    assert.equals('TODO', env.internal.todo)
    assert.equals('[2026-04-11 Fri 12:00]', env.internal.properties.LAST_REPEAT)
    assert.equals(1, #env.internal.notes)
    assert.is_true(env.internal.notes[1][1]:find('State ') ~= nil)
    assert.is_false(Store.sticky_has(path .. ':1'))
    assert.equals(1, refresh_calls)
    assert.are.same({}, notifications)
  end)

  it('keeps non-repeating tasks as DONE and records sticky state', function()
    local path = write_temp_org({ '* TODO One-off task' })
    local env = setup_fake_org({ path = path, repeater_dates = {} })

    setup_agenda_buffer(path)
    invoke_buffer_mapping('sd')

    assert.are.same({}, env.replaced)
    assert.equals('DONE', env.internal.todo)
    assert.is_true(env.internal.closed_set)
    assert.is_true(Store.sticky_has(path .. ':1'))
    assert.equals(1, refresh_calls)
    assert.are.same({}, notifications)
  end)
end)
