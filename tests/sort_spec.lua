local Sort = require('org-super-agenda.core.sort')
local Item = require('org-super-agenda.core.item')
local Date = require('org-super-agenda.core.date')
local config = require('org-super-agenda.config')

describe('sort.sort_items', function()
  before_each(function()
    config.setup({
      todo_states = {
        { name = 'TODO' },
        { name = 'NEXT' },
        { name = 'DONE' },
      },
    })
  end)

  it('sorts by scheduled date ascending', function()
    local items = {
      Item.new({ headline = 'a', scheduled = Date.new(2025, 8, 3) }),
      Item.new({ headline = 'b', scheduled = Date.new(2025, 8, 1) }),
      Item.new({ headline = 'c', scheduled = Date.new(2025, 8, 2) }),
    }
    local sorted = Sort.sort_items(items, { by = 'scheduled', order = 'asc' }, config.get())
    assert.equals('b', sorted[1].headline)
    assert.equals('c', sorted[2].headline)
    assert.equals('a', sorted[3].headline)
  end)

  it('sorts by scheduled date descending', function()
    local items = {
      Item.new({ headline = 'a', scheduled = Date.new(2025, 8, 1) }),
      Item.new({ headline = 'b', scheduled = Date.new(2025, 8, 3) }),
      Item.new({ headline = 'c', scheduled = Date.new(2025, 8, 2) }),
    }
    local sorted = Sort.sort_items(items, { by = 'scheduled', order = 'desc' }, config.get())
    assert.equals('b', sorted[1].headline)
    assert.equals('c', sorted[2].headline)
    assert.equals('a', sorted[3].headline)
  end)

  it('sorts by scheduled_time with hour/minute', function()
    local items = {
      Item.new({ headline = 'morning', scheduled = Date.new(2025, 8, 1, true, 9, 0) }),
      Item.new({ headline = 'afternoon', scheduled = Date.new(2025, 8, 1, true, 14, 30) }),
      Item.new({ headline = 'early', scheduled = Date.new(2025, 8, 1, true, 7, 15) }),
    }
    local sorted = Sort.sort_items(items, { by = 'scheduled_time', order = 'asc' }, config.get())
    assert.equals('early', sorted[1].headline)
    assert.equals('morning', sorted[2].headline)
    assert.equals('afternoon', sorted[3].headline)
  end)

  it('sorts by deadline_time with hour/minute', function()
    local items = {
      Item.new({ headline = 'late', deadline = Date.new(2025, 8, 1, true, 23, 59) }),
      Item.new({ headline = 'noon', deadline = Date.new(2025, 8, 1, true, 12, 0) }),
      Item.new({ headline = 'morning', deadline = Date.new(2025, 8, 1, true, 8, 30) }),
    }
    local sorted = Sort.sort_items(items, { by = 'deadline_time', order = 'asc' }, config.get())
    assert.equals('morning', sorted[1].headline)
    assert.equals('noon', sorted[2].headline)
    assert.equals('late', sorted[3].headline)
  end)

  it('sorts by priority', function()
    local items = {
      Item.new({ headline = 'b', priority = 'B' }),
      Item.new({ headline = 'none', priority = '' }),
      Item.new({ headline = 'a', priority = 'A' }),
      Item.new({ headline = 'c', priority = 'C' }),
    }
    local sorted = Sort.sort_items(items, { by = 'priority', order = 'desc' }, config.get())
    assert.equals('a', sorted[1].headline)
    assert.equals('b', sorted[2].headline)
    assert.equals('c', sorted[3].headline)
    assert.equals('none', sorted[4].headline)
  end)

  it('sorts by todo state order', function()
    local items = {
      Item.new({ headline = 'done', todo_state = 'DONE' }),
      Item.new({ headline = 'next', todo_state = 'NEXT' }),
      Item.new({ headline = 'todo', todo_state = 'TODO' }),
    }
    local sorted = Sort.sort_items(items, { by = 'todo', order = 'asc' }, config.get())
    assert.equals('todo', sorted[1].headline)
    assert.equals('next', sorted[2].headline)
    assert.equals('done', sorted[3].headline)
  end)

  it('sorts by custom todo state order from spec', function()
    local items = {
      Item.new({ headline = 'done', todo_state = 'DONE' }),
      Item.new({ headline = 'next', todo_state = 'NEXT' }),
      Item.new({ headline = 'todo', todo_state = 'TODO' }),
      Item.new({ headline = 'progress', todo_state = 'PROGRESS' }),
    }
    local sorted = Sort.sort_items(items, {
      by = 'todo',
      order = 'asc',
      todo_order = { 'PROGRESS', 'NEXT', 'TODO', 'DONE' },
    }, config.get())
    assert.equals('progress', sorted[1].headline)
    assert.equals('next', sorted[2].headline)
    assert.equals('todo', sorted[3].headline)
    assert.equals('done', sorted[4].headline)
  end)

  it('sorts by filename', function()
    local items = {
      Item.new({ headline = 'z', file = '/path/to/zebra.org' }),
      Item.new({ headline = 'a', file = '/path/to/apple.org' }),
      Item.new({ headline = 'm', file = '/path/to/mango.org' }),
    }
    local sorted = Sort.sort_items(items, { by = 'filename', order = 'asc' }, config.get())
    assert.equals('a', sorted[1].headline)
    assert.equals('m', sorted[2].headline)
    assert.equals('z', sorted[3].headline)
  end)

  it('sorts by headline alphabetically', function()
    local items = {
      Item.new({ headline = 'Zebra' }),
      Item.new({ headline = 'apple' }),
      Item.new({ headline = 'Mango' }),
    }
    local sorted = Sort.sort_items(items, { by = 'headline', order = 'asc' }, config.get())
    assert.equals('apple', sorted[1].headline)
    assert.equals('Mango', sorted[2].headline)
    assert.equals('Zebra', sorted[3].headline)
  end)

  it('sorts by date_nearest picks closest of scheduled/deadline', function()
    local today = Date.parse('2025-08-01')
    local items = {
      Item.new({ headline = 'both', scheduled = Date.new(2025, 8, 5), deadline = Date.new(2025, 8, 3) }),
      Item.new({ headline = 'sched_only', scheduled = Date.new(2025, 8, 2) }),
      Item.new({ headline = 'dead_only', deadline = Date.new(2025, 8, 4) }),
    }
    local sorted = Sort.sort_items(items, { by = 'date_nearest', order = 'asc' }, config.get())
    assert.equals('sched_only', sorted[1].headline)
    assert.equals('both', sorted[2].headline)
    assert.equals('dead_only', sorted[3].headline)
  end)

  it('uses tie-breaker: priority > filename > headline', function()
    local items = {
      Item.new({ headline = 'z', scheduled = Date.new(2025, 8, 1), priority = 'A', file = 'a.org' }),
      Item.new({ headline = 'a', scheduled = Date.new(2025, 8, 1), priority = 'B', file = 'b.org' }),
      Item.new({ headline = 'b', scheduled = Date.new(2025, 8, 1), priority = 'A', file = 'a.org' }),
    }
    local sorted = Sort.sort_items(items, { by = 'scheduled', order = 'asc' }, config.get())
    assert.equals('b', sorted[1].headline)
    assert.equals('z', sorted[2].headline)
    assert.equals('a', sorted[3].headline)
  end)

  it('handles items without dates by pushing to end', function()
    local items = {
      Item.new({ headline = 'no_date' }),
      Item.new({ headline = 'with_date', scheduled = Date.new(2025, 8, 1) }),
    }
    local sorted = Sort.sort_items(items, { by = 'scheduled', order = 'asc' }, config.get())
    assert.equals('with_date', sorted[1].headline)
    assert.equals('no_date', sorted[2].headline)
  end)

  it('defaults to date_nearest asc when no spec provided', function()
    local items = {
      Item.new({ headline = 'far', deadline = Date.new(2025, 8, 10) }),
      Item.new({ headline = 'near', scheduled = Date.new(2025, 8, 2) }),
    }
    local sorted = Sort.sort_items(items, nil, config.get())
    assert.equals('near', sorted[1].headline)
    assert.equals('far', sorted[2].headline)
  end)

  it('falls back to config.group_sort when spec incomplete', function()
    config.setup({
      group_sort = { by = 'priority', order = 'desc' },
    })
    local items = {
      Item.new({ headline = 'low', priority = 'C' }),
      Item.new({ headline = 'high', priority = 'A' }),
    }
    local sorted = Sort.sort_items(items, {}, config.get())
    assert.equals('high', sorted[1].headline)
    assert.equals('low', sorted[2].headline)
  end)
end)
