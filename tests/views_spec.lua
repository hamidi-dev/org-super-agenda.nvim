local Views = require('org-super-agenda.core.views')
local Item = require('org-super-agenda.core.item')
local Date = require('org-super-agenda.core.date')
local Store = require('org-super-agenda.app.store')
local config = require('org-super-agenda.config')

describe('core.views', function()
  describe('resolve', function()
    it('returns nil for nil input', function()
      assert.is_nil(Views.resolve(nil))
    end)

    it('resolves a view with name and filter', function()
      local v = Views.resolve({ name = 'Work Week', filter = 'tag:work sched>=0' })
      assert.equals('Work Week', v.name)
      assert.is_not_nil(v.filter)
      assert.equals('tag:work sched>=0', v.filter_raw)
    end)

    it('resolves a view without filter', function()
      local v = Views.resolve({ name = 'All Items' })
      assert.equals('All Items', v.name)
      assert.is_nil(v.filter)
      assert.is_nil(v.filter_raw)
    end)

    it('preserves custom groups', function()
      local groups = {
        {
          name = 'Urgent',
          matcher = function()
            return true
          end,
        },
      }
      local v = Views.resolve({ name = 'Test', groups = groups })
      assert.equals(groups, v.groups)
    end)

    it('preserves sort spec', function()
      local v = Views.resolve({ name = 'Test', sort = { by = 'priority', order = 'desc' } })
      assert.equals('priority', v.sort.by)
      assert.equals('desc', v.sort.order)
    end)

    it('preserves title override', function()
      local v = Views.resolve({ name = 'Test', title = 'Custom Title' })
      assert.equals('Custom Title', v.title)
    end)

    it('defaults name to Custom View', function()
      local v = Views.resolve({ filter = 'tag:work' })
      assert.equals('Custom View', v.name)
    end)
  end)

  describe('list', function()
    it('returns empty for nil', function()
      assert.same({}, Views.list(nil))
    end)

    it('returns empty for empty table', function()
      assert.same({}, Views.list({}))
    end)

    it('lists views sorted by name', function()
      local views = {
        beta = { name = 'Beta View', keymap = '<leader>ob', filter = 'tag:beta' },
        alpha = { name = 'Alpha View', filter = 'tag:alpha' },
      }
      local result = Views.list(views)
      assert.equals(2, #result)
      assert.equals('Alpha View', result[1].name)
      assert.equals('alpha', result[1].key)
      assert.is_nil(result[1].keymap)
      assert.equals('Beta View', result[2].name)
      assert.equals('<leader>ob', result[2].keymap)
    end)

    it('uses key as name fallback', function()
      local views = { my_view = { filter = 'tag:test' } }
      local result = Views.list(views)
      assert.equals('my_view', result[1].name)
    end)
  end)

  describe('apply_filter', function()
    local today = os.date('*t')
    local items = {
      Item.new({ headline = 'Work task', tags = { 'work' }, todo_state = 'TODO', scheduled = Date.new(today.year, today.month, today.day) }),
      Item.new({ headline = 'Personal task', tags = { 'personal' }, todo_state = 'TODO' }),
      Item.new({ headline = 'Done work', tags = { 'work' }, todo_state = 'DONE' }),
    }

    it('returns all items when no filter', function()
      local result = Views.apply_filter(items, nil)
      assert.equals(3, #result)
    end)

    it('returns all items when resolved view has no filter', function()
      local v = Views.resolve({ name = 'All' })
      local result = Views.apply_filter(items, v)
      assert.equals(3, #result)
    end)

    it('filters by tag', function()
      local v = Views.resolve({ name = 'Work', filter = 'tag:work' })
      local result = Views.apply_filter(items, v)
      assert.equals(2, #result)
      assert.equals('Work task', result[1].headline)
      assert.equals('Done work', result[2].headline)
    end)

    it('filters by tag and state', function()
      local v = Views.resolve({ name = 'Work Active', filter = 'tag:work -is:done' })
      local result = Views.apply_filter(items, v)
      assert.equals(1, #result)
      assert.equals('Work task', result[1].headline)
    end)

    it('filters with scheduled range', function()
      local v = Views.resolve({ name = 'Scheduled Today', filter = 'sched>=0 sched<=0' })
      local result = Views.apply_filter(items, v)
      assert.equals(1, #result)
      assert.equals('Work task', result[1].headline)
    end)
  end)
end)

describe('store.active_view', function()
  after_each(function()
    Store.clear_active_view()
  end)

  it('starts with no active view', function()
    assert.is_nil(Store.get_active_view())
    assert.is_nil(Store.get_active_view_key())
  end)

  it('sets and gets active view', function()
    local view = { name = 'Test View' }
    Store.set_active_view(view, 'test')
    assert.equals(view, Store.get_active_view())
    assert.equals('test', Store.get_active_view_key())
  end)

  it('clears active view', function()
    Store.set_active_view({ name = 'X' }, 'x')
    Store.clear_active_view()
    assert.is_nil(Store.get_active_view())
    assert.is_nil(Store.get_active_view_key())
  end)
end)

describe('config.custom_views', function()
  local defaults = vim.deepcopy(config.defaults)

  after_each(function()
    config.setup(vim.deepcopy(defaults))
  end)

  it('defaults to empty table', function()
    config.setup({})
    assert.same({}, config.get().custom_views)
  end)

  it('preserves user-defined views', function()
    config.setup({
      custom_views = {
        work = { name = 'Work', filter = 'tag:work', keymap = '<leader>ow' },
      },
    })
    local cv = config.get().custom_views
    assert.is_not_nil(cv.work)
    assert.equals('Work', cv.work.name)
    assert.equals('tag:work', cv.work.filter)
    assert.equals('<leader>ow', cv.work.keymap)
  end)

  it('ships open_view keymap default', function()
    config.setup(vim.deepcopy(defaults))
    assert.equals('V', config.get().keymaps.open_view)
  end)
end)
