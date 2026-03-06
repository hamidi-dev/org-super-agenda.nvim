local Group = require('org-super-agenda.core.group')
local Item = require('org-super-agenda.core.item')
local Date = require('org-super-agenda.core.date')

describe('group.group_items', function()
  it('groups items by matcher', function()
    local items = {
      Item.new({ headline = 'Work Task', todo_state = 'TODO', tags = { 'work' } }),
      Item.new({ headline = 'Personal Task', todo_state = 'TODO', tags = { 'personal' } }),
    }
    local spec = {
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
        {
          name = 'Personal',
          matcher = function(it)
            return it:has_tag('personal')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(2, #groups)
    assert.equals('Work', groups[1].name)
    assert.equals(1, #groups[1].items)
    assert.equals('Personal', groups[2].name)
    assert.equals(1, #groups[2].items)
  end)

  it('preserves sort field in group', function()
    local items = { Item.new({ headline = 'Task', todo_state = 'TODO' }) }
    local spec = {
      groups = {
        {
          name = 'Test',
          matcher = function()
            return true
          end,
          sort = { by = 'priority', order = 'desc' },
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.is_not_nil(groups[1].sort)
    assert.equals('priority', groups[1].sort.by)
    assert.equals('desc', groups[1].sort.order)
  end)

  it('places item in first matching group when duplicates disabled', function()
    local items = {
      Item.new({ headline = 'Task', todo_state = 'TODO', tags = { 'work', 'urgent' } }),
    }
    local spec = {
      allow_duplicates = false,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
        {
          name = 'Urgent',
          matcher = function(it)
            return it:has_tag('urgent')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(1, #groups[1].items)
    assert.equals(0, #groups[2].items)
  end)

  it('places item in all matching groups when duplicates enabled', function()
    local items = {
      Item.new({ headline = 'Task', todo_state = 'TODO', tags = { 'work', 'urgent' } }),
    }
    local spec = {
      allow_duplicates = true,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
        {
          name = 'Urgent',
          matcher = function(it)
            return it:has_tag('urgent')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(1, #groups[1].items)
    assert.equals(1, #groups[2].items)
  end)

  it('places unmatched items in Other group when show_other enabled', function()
    local items = {
      Item.new({ headline = 'Matched', todo_state = 'TODO', tags = { 'work' } }),
      Item.new({ headline = 'Unmatched', todo_state = 'TODO', tags = { 'personal' } }),
    }
    local spec = {
      show_other = true,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(2, #groups)
    assert.equals('Work', groups[1].name)
    assert.equals('Other', groups[2].name)
    assert.equals(1, #groups[2].items)
    assert.equals('Unmatched', groups[2].items[1].headline)
  end)

  it('uses custom other_name when provided', function()
    local items = {
      Item.new({ headline = 'Task', todo_state = 'TODO' }),
    }
    local spec = {
      show_other = true,
      other_name = 'Miscellaneous',
      groups = {},
    }
    local groups = Group.group_items(items, spec)
    assert.equals('Miscellaneous', groups[1].name)
  end)

  it('excludes DONE items from Other group', function()
    local items = {
      Item.new({ headline = 'TODO Task', todo_state = 'TODO' }),
      Item.new({ headline = 'DONE Task', todo_state = 'DONE' }),
    }
    local spec = {
      show_other = true,
      groups = {
        {
          name = 'Active',
          matcher = function(it)
            return it.todo_state == 'TODO'
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(2, #groups)
    assert.equals('Active', groups[1].name)
    assert.equals(1, #groups[1].items)
    assert.equals('TODO Task', groups[1].items[1].headline)
    assert.equals('Other', groups[2].name)
    assert.equals(0, #groups[2].items)
  end)

  it('hides empty groups when hide_empty enabled', function()
    local items = {
      Item.new({ headline = 'Work Task', todo_state = 'TODO', tags = { 'work' } }),
    }
    local spec = {
      hide_empty = true,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
        {
          name = 'Personal',
          matcher = function(it)
            return it:has_tag('personal')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(1, #groups)
    assert.equals('Work', groups[1].name)
  end)

  it('keeps empty groups when hide_empty disabled', function()
    local items = {
      Item.new({ headline = 'Work Task', todo_state = 'TODO', tags = { 'work' } }),
    }
    local spec = {
      hide_empty = false,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
        {
          name = 'Personal',
          matcher = function(it)
            return it:has_tag('personal')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(2, #groups)
    assert.equals('Work', groups[1].name)
    assert.equals('Personal', groups[2].name)
    assert.equals(0, #groups[2].items)
  end)

  it('returns empty list when no items and no groups', function()
    local groups = Group.group_items({}, { groups = {} })
    assert.equals(0, #groups)
  end)

  it('handles items with no matching groups and show_other disabled', function()
    local items = {
      Item.new({ headline = 'Task', todo_state = 'TODO' }),
    }
    local spec = {
      show_other = false,
      groups = {
        {
          name = 'Work',
          matcher = function(it)
            return it:has_tag('work')
          end,
        },
      },
    }
    local groups = Group.group_items(items, spec)
    assert.equals(1, #groups)
    assert.equals(0, #groups[1].items)
  end)
end)
