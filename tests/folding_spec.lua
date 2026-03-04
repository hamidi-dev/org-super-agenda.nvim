local Store = require('org-super-agenda.app.store')
local Item = require('org-super-agenda.core.item')
local layout_classic = require('org-super-agenda.core.layout.classic')
local layout_compact = require('org-super-agenda.core.layout.compact')

describe('group folding (Store)', function()
  before_each(function()
    Store.unfold_all_groups()
  end)

  it('toggles collapsed state for a group', function()
    assert.is_false(Store.is_group_collapsed('Today'))
    Store.toggle_group('Today')
    assert.is_true(Store.is_group_collapsed('Today'))
    Store.toggle_group('Today')
    assert.is_false(Store.is_group_collapsed('Today'))
  end)

  it('folds multiple groups and can unfold all', function()
    Store.fold_groups({ 'Today', 'Work' })
    assert.is_true(Store.is_group_collapsed('Today'))
    assert.is_true(Store.is_group_collapsed('Work'))
    Store.unfold_all_groups()
    assert.is_false(Store.is_group_collapsed('Today'))
    assert.is_false(Store.is_group_collapsed('Work'))
  end)
end)

describe('group folding (layout)', function()
  local cfg = {
    group_format = '* %s',
    show_filename = false,
    show_tags = false,
    heading_max_length = 80,
    classic = { heading_order = { 'todo', 'headline' }, short_date_labels = false, inline_dates = false },
    compact = { filename_min_width = 8, label_min_width = 10 },
  }

  local function make_item(headline, line)
    return Item.new{
      headline = headline,
      todo_state = 'TODO',
      file = '/org/test.org',
      _src_line = line,
    }
  end

  it('shows item count in classic group header', function()
    local groups = {
      {
        name = 'Today',
        collapsed = false,
        items = { make_item('Task A', 10), make_item('Task B', 11) },
      },
    }
    local rows = layout_classic.build(groups, 80, cfg, {})
    assert.equals('* Today (2 items)', rows[2])
  end)

  it('hides group items when collapsed in classic layout', function()
    local groups = {
      {
        name = 'Today',
        collapsed = true,
        items = { make_item('Task A', 10), make_item('Task B', 11) },
      },
    }
    local rows, _, line_map = layout_classic.build(groups, 80, cfg, {})
    assert.equals('* Today (2 items)', rows[2])
    assert.is_nil(rows[3])
    assert.equals('group_header', line_map[2]._kind)
    assert.equals('Today', line_map[2].group_name)
  end)

  it('hides group items when collapsed in compact layout', function()
    local groups = {
      {
        name = 'Inbox',
        collapsed = true,
        items = { make_item('Task A', 10) },
      },
    }
    local rows, _, line_map = layout_compact.build(groups, 80, cfg, {})
    assert.equals('* Inbox (1 item)', rows[2])
    assert.is_nil(rows[3])
    assert.equals('group_header', line_map[2]._kind)
    assert.equals('Inbox', line_map[2].group_name)
  end)
end)
