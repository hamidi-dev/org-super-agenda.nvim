local Filter = require('org-super-agenda.core.filter')
local Item = require('org-super-agenda.core.item')
local Date = require('org-super-agenda.core.date')
local config = require('org-super-agenda.config')

describe('filter.apply', function()
  before_each(function()
    config.setup({
      todo_states = {
        { name = 'TODO' },
        { name = 'NEXT' },
        { name = 'DONE' },
      }
    })
  end)

  it('returns all items when no filters applied', function()
    local items = {
      Item.new{ headline = 'Task 1', todo_state = 'TODO' },
      Item.new{ headline = 'Task 2', todo_state = 'DONE' },
    }
    local filtered = Filter.apply(items, {}, config.get())
    assert.equals(2, #filtered)
  end)

  it('filters by single todo state', function()
    local items = {
      Item.new{ headline = 'Task 1', todo_state = 'TODO' },
      Item.new{ headline = 'Task 2', todo_state = 'DONE' },
      Item.new{ headline = 'Task 3', todo_state = 'NEXT' },
    }
    local filtered = Filter.apply(items, { todo_filter = 'TODO' }, config.get())
    assert.equals(1, #filtered)
    assert.equals('Task 1', filtered[1].headline)
  end)

  it('filters by multiple todo states', function()
    local items = {
      Item.new{ headline = 'Task 1', todo_state = 'TODO' },
      Item.new{ headline = 'Task 2', todo_state = 'DONE' },
      Item.new{ headline = 'Task 3', todo_state = 'NEXT' },
    }
    local filtered = Filter.apply(items, { todo_filter = {'TODO', 'NEXT'} }, config.get())
    assert.equals(2, #filtered)
    assert.equals('Task 1', filtered[1].headline)
    assert.equals('Task 3', filtered[2].headline)
  end)

  it('filters by headline text case-insensitively', function()
    local items = {
      Item.new{ headline = 'Team Meeting', todo_state = 'TODO' },
      Item.new{ headline = 'Code Review', todo_state = 'TODO' },
      Item.new{ headline = 'Project Meeting', todo_state = 'TODO' },
    }
    local filtered = Filter.apply(items, { headline_filter = 'meeting' }, config.get())
    assert.equals(2, #filtered)
    assert.equals('Team Meeting', filtered[1].headline)
    assert.equals('Project Meeting', filtered[2].headline)
  end)

  it('filters by headline with fuzzy matching', function()
    local items = {
      Item.new{ headline = 'Team Meeting', todo_state = 'TODO' },
      Item.new{ headline = 'Code Review', todo_state = 'TODO' },
    }
    local filtered = Filter.apply(items, {
      headline_filter = 'tm',
      headline_fuzzy = true
    }, config.get())
    assert.equals(1, #filtered)
    assert.equals('Team Meeting', filtered[1].headline)
  end)

  it('filters by advanced query', function()
    local items = {
      Item.new{ headline = 'Task 1', todo_state = 'TODO', tags = {'work'} },
      Item.new{ headline = 'Task 2', todo_state = 'TODO', tags = {'personal'} },
    }
    local filtered = Filter.apply(items, { query = 'tag:work' }, config.get())
    assert.equals(1, #filtered)
    assert.equals('Task 1', filtered[1].headline)
  end)

  it('combines multiple filters with AND logic', function()
    local items = {
      Item.new{ headline = 'Work Meeting', todo_state = 'TODO', tags = {'work'} },
      Item.new{ headline = 'Team Sync', todo_state = 'DONE', tags = {'work'} },
      Item.new{ headline = 'Work Review', todo_state = 'TODO', tags = {'personal'} },
    }
    local filtered = Filter.apply(items, {
      todo_filter = 'TODO',
      headline_filter = 'work',
      query = 'tag:work'
    }, config.get())
    assert.equals(1, #filtered)
    assert.equals('Work Meeting', filtered[1].headline)
  end)

  it('includes items with valid TODO states', function()
    local items = {
      Item.new{ headline = 'Task 1', todo_state = 'TODO' },
      Item.new{ headline = 'Task 2', todo_state = 'DONE' },
      Item.new{ headline = 'Task 3', todo_state = 'INVALID' },
    }
    local filtered = Filter.apply(items, {}, config.get())
    assert.equals(2, #filtered)
    assert.equals('Task 1', filtered[1].headline)
    assert.equals('Task 2', filtered[2].headline)
  end)

  it('includes events (no TODO state but has date)', function()
    local items = {
      Item.new{ headline = 'Event 1', todo_state = nil, scheduled = Date.new(2025, 8, 1) },
      Item.new{ headline = 'Event 2', todo_state = '', deadline = Date.new(2025, 8, 1) },
      Item.new{ headline = 'Invalid', todo_state = nil },
    }
    local filtered = Filter.apply(items, {}, config.get())
    assert.equals(2, #filtered)
    assert.equals('Event 1', filtered[1].headline)
    assert.equals('Event 2', filtered[2].headline)
  end)

  it('excludes items without valid state or dates', function()
    local items = {
      Item.new{ headline = 'Valid TODO', todo_state = 'TODO' },
      Item.new{ headline = 'Invalid', todo_state = 'INVALID' },
      Item.new{ headline = 'No state, no date', todo_state = nil },
    }
    local filtered = Filter.apply(items, {}, config.get())
    assert.equals(1, #filtered)
    assert.equals('Valid TODO', filtered[1].headline)
  end)

  it('matches headline against filename', function()
    local items = {
      Item.new{ headline = 'Task', todo_state = 'TODO', file = '/home/user/work.org' },
      Item.new{ headline = 'Task', todo_state = 'TODO', file = '/home/user/personal.org' },
    }
    local filtered = Filter.apply(items, { headline_filter = 'work' }, config.get())
    assert.equals(1, #filtered)
    assert.equals('/home/user/work.org', filtered[1].file)
  end)

  it('matches headline against tags', function()
    local items = {
      Item.new{ headline = 'Task', todo_state = 'TODO', tags = {'urgent', 'work'} },
      Item.new{ headline = 'Task', todo_state = 'TODO', tags = {'personal'} },
    }
    local filtered = Filter.apply(items, { headline_filter = 'urgent' }, config.get())
    assert.equals(1, #filtered)
    assert.is_true(filtered[1]:has_tag('urgent'))
  end)
end)
