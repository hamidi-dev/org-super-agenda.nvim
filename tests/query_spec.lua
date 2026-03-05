local Query = require('org-super-agenda.core.query')
local Item = require('org-super-agenda.core.item')
local Date = require('org-super-agenda.core.date')

describe('query.parse', function()
  it('returns nil for empty query', function()
    assert.is_nil(Query.parse(''))
    assert.is_nil(Query.parse(nil))
  end)

  it('matches headline text case-insensitively', function()
    local q = Query.parse('meeting')
    local item1 = Item.new{ headline = 'Team Meeting' }
    local item2 = Item.new{ headline = 'Review code' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches multiple include tokens', function()
    local q = Query.parse('project alpha')
    local item1 = Item.new{ headline = 'Project Alpha Review' }
    local item2 = Item.new{ headline = 'Project Beta Review' }
    local item3 = Item.new{ headline = 'Alpha Team Meeting' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('excludes items with minus prefix', function()
    local q = Query.parse('project -meeting')
    local item1 = Item.new{ headline = 'Project Review' }
    local item2 = Item.new{ headline = 'Project Meeting' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches tags with tag: prefix', function()
    local q = Query.parse('tag:work')
    local item1 = Item.new{ headline = 'Task', tags = {'work', 'urgent'} }
    local item2 = Item.new{ headline = 'Task', tags = {'personal'} }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches multiple tags with pipe separator', function()
    local q = Query.parse('tag:work|urgent')
    local item1 = Item.new{ headline = 'Task', tags = {'work'} }
    local item2 = Item.new{ headline = 'Task', tags = {'urgent'} }
    local item3 = Item.new{ headline = 'Task', tags = {'personal'} }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('excludes tags with -tag: prefix', function()
    local q = Query.parse('-tag:spam')
    local item1 = Item.new{ headline = 'Task', tags = {'work'} }
    local item2 = Item.new{ headline = 'Task', tags = {'spam'} }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches filename with file: prefix', function()
    local q = Query.parse('file:work')
    local item1 = Item.new{ headline = 'Task', file = '/home/user/work.org' }
    local item2 = Item.new{ headline = 'Task', file = '/home/user/personal.org' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches todo state with todo: prefix', function()
    local q = Query.parse('todo:TODO|NEXT')
    local item1 = Item.new{ headline = 'Task', todo_state = 'TODO' }
    local item2 = Item.new{ headline = 'Task', todo_state = 'NEXT' }
    local item3 = Item.new{ headline = 'Task', todo_state = 'DONE' }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('matches priority with prio: prefix', function()
    local q = Query.parse('prio:A')
    local item1 = Item.new{ headline = 'Task', priority = 'A' }
    local item2 = Item.new{ headline = 'Task', priority = 'B' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches priority with comparison operators', function()
    local q_gte = Query.parse('prio>=B')
    local q_lt = Query.parse('prio<B')
    local itemA = Item.new{ headline = 'Task', priority = 'A' }
    local itemB = Item.new{ headline = 'Task', priority = 'B' }
    local itemC = Item.new{ headline = 'Task', priority = 'C' }
    assert.is_true(q_gte.matches(itemA))
    assert.is_true(q_gte.matches(itemB))
    assert.is_false(q_gte.matches(itemC))
    assert.is_false(q_lt.matches(itemA))
    assert.is_false(q_lt.matches(itemB))
    assert.is_true(q_lt.matches(itemC))
  end)

  it('matches deadline with due< operator', function()
    local q = Query.parse('due<3')
    local tomorrow = os.date('*t')
    tomorrow.day = tomorrow.day + 1
    local next_week = os.date('*t')
    next_week.day = next_week.day + 7
    local item1 = Item.new{ headline = 'Task', deadline = Date.new(tomorrow.year, tomorrow.month, tomorrow.day) }
    local item2 = Item.new{ headline = 'Task', deadline = Date.new(next_week.year, next_week.month, next_week.day) }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches scheduled with sched<= operator', function()
    local q = Query.parse('sched<=0')
    local yesterday = os.date('*t')
    yesterday.day = yesterday.day - 1
    local tomorrow = os.date('*t')
    tomorrow.day = tomorrow.day + 1
    local item1 = Item.new{ headline = 'Task', scheduled = Date.new(yesterday.year, yesterday.month, yesterday.day) }
    local item2 = Item.new{ headline = 'Task', scheduled = Date.new(tomorrow.year, tomorrow.month, tomorrow.day) }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches with before: absolute date', function()
    local q = Query.parse('before:2025-08-10')
    local item1 = Item.new{ headline = 'Task', deadline = Date.new(2025, 8, 5) }
    local item2 = Item.new{ headline = 'Task', deadline = Date.new(2025, 8, 15) }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches with after: absolute date', function()
    local q = Query.parse('after:2025-08-01')
    local item1 = Item.new{ headline = 'Task', scheduled = Date.new(2025, 8, 5) }
    local item2 = Item.new{ headline = 'Task', scheduled = Date.new(2025, 7, 30) }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('matches overdue items with is:overdue', function()
    local q = Query.parse('is:overdue')
    local last_month = os.date('*t')
    last_month.month = last_month.month - 1
    local next_month = os.date('*t')
    next_month.month = next_month.month + 1
    local item1 = Item.new{ headline = 'Task', deadline = Date.new(last_month.year, last_month.month, last_month.day) }
    local item2 = Item.new{ headline = 'Task', scheduled = Date.new(last_month.year, last_month.month, last_month.day) }
    local item3 = Item.new{ headline = 'Task', deadline = Date.new(next_month.year, next_month.month, next_month.day) }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('matches done items with is:done', function()
    local q = Query.parse('is:done')
    local item1 = Item.new{ headline = 'Task', todo_state = 'DONE' }
    local item2 = Item.new{ headline = 'Task', todo_state = 'TODO' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
  end)

  it('excludes done items with -is:done', function()
    local q = Query.parse('-is:done')
    local item1 = Item.new{ headline = 'Task', todo_state = 'TODO' }
    local item2 = Item.new{ headline = 'Task', todo_state = 'PROGRESS' }
    local item3 = Item.new{ headline = 'Task', todo_state = 'DONE' }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('excludes overdue items with -is:overdue', function()
    local q = Query.parse('-is:overdue')
    local last_month = os.date('*t')
    last_month.month = last_month.month - 1
    local next_month = os.date('*t')
    next_month.month = next_month.month + 1
    local item1 = Item.new{ headline = 'Overdue', deadline = Date.new(last_month.year, last_month.month, last_month.day) }
    local item2 = Item.new{ headline = 'Future', deadline = Date.new(next_month.year, next_month.month, next_month.day) }
    assert.is_false(q.matches(item1))
    assert.is_true(q.matches(item2))
  end)

  it('matches items with TODO state using has:todo', function()
    local q = Query.parse('has:todo')
    local item1 = Item.new{ headline = 'Task', todo_state = 'TODO' }
    local item2 = Item.new{ headline = 'Task', todo_state = 'DONE' }
    local item3 = Item.new{ headline = 'Task', todo_state = 'NEXT' }
    local item4 = Item.new{ headline = 'Event', todo_state = nil }
    local item5 = Item.new{ headline = 'Event', todo_state = '' }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_true(q.matches(item3))
    assert.is_false(q.matches(item4))
    assert.is_false(q.matches(item5))
  end)

  it('excludes items with TODO state using -has:todo', function()
    local q = Query.parse('-has:todo')
    local item1 = Item.new{ headline = 'Event', todo_state = nil }
    local item2 = Item.new{ headline = 'Event', todo_state = '' }
    local item3 = Item.new{ headline = 'Task', todo_state = 'TODO' }
    local item4 = Item.new{ headline = 'Task', todo_state = 'DONE' }
    assert.is_true(q.matches(item1))
    assert.is_true(q.matches(item2))
    assert.is_false(q.matches(item3))
    assert.is_false(q.matches(item4))
  end)

  it('combines has:todo with other conditions', function()
    local q = Query.parse('has:todo tag:work')
    local item1 = Item.new{ headline = 'Work Task', todo_state = 'TODO', tags = {'work'} }
    local item2 = Item.new{ headline = 'Work Event', todo_state = nil, tags = {'work'} }
    local item3 = Item.new{ headline = 'Personal Task', todo_state = 'TODO', tags = {'personal'} }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('combines -has:todo with other conditions', function()
    local q = Query.parse('-has:todo tag:personal')
    local item1 = Item.new{ headline = 'Personal Event', todo_state = nil, tags = {'personal'} }
    local item2 = Item.new{ headline = 'Personal Task', todo_state = 'TODO', tags = {'personal'} }
    local item3 = Item.new{ headline = 'Work Event', todo_state = nil, tags = {'work'} }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('combines multiple query conditions with AND logic', function()
    local q = Query.parse('meeting tag:work prio:A')
    local item1 = Item.new{ headline = 'Work Meeting', tags = {'work'}, priority = 'A' }
    local item2 = Item.new{ headline = 'Work Meeting', tags = {'work'}, priority = 'B' }
    local item3 = Item.new{ headline = 'Team Sync', tags = {'work'}, priority = 'A' }
    assert.is_true(q.matches(item1))
    assert.is_false(q.matches(item2))
    assert.is_false(q.matches(item3))
  end)

  it('strips extra whitespace from query', function()
    local q = Query.parse('  meeting    tag:work  ')
    local item = Item.new{ headline = 'Work Meeting', tags = {'work'} }
    assert.is_true(q.matches(item))
  end)

  it('returns false for items without deadline when due< used', function()
    local q = Query.parse('due<3')
    local item = Item.new{ headline = 'Task' }
    assert.is_false(q.matches(item))
  end)

  it('returns false for items without scheduled when sched< used', function()
    local q = Query.parse('sched<0')
    local item = Item.new{ headline = 'Task' }
    assert.is_false(q.matches(item))
  end)
end)
