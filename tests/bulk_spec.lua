local Store = require('org-super-agenda.app.store')
local Item = require('org-super-agenda.core.item')

local function make_item(file, src_line)
  return Item.new({ headline = 'Task', todo_state = 'TODO', file = file, _src_line = src_line })
end

local function item_key(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

describe('bulk marking (Store)', function()
  before_each(function()
    Store.mark_clear()
  end)

  it('marks an item', function()
    local it = make_item('/org/work.org', 10)
    local k = item_key(it)
    Store.mark_toggle(k)
    assert.is_true(Store.is_marked(k))
  end)

  it('toggles mark off on second call', function()
    local it = make_item('/org/work.org', 10)
    local k = item_key(it)
    Store.mark_toggle(k)
    Store.mark_toggle(k)
    assert.is_false(Store.is_marked(k))
  end)

  it('clears all marks with mark_clear', function()
    local it1 = make_item('/org/work.org', 10)
    local it2 = make_item('/org/work.org', 20)
    Store.mark_toggle(item_key(it1))
    Store.mark_toggle(item_key(it2))
    Store.mark_clear()
    assert.is_false(Store.is_marked(item_key(it1)))
    assert.is_false(Store.is_marked(item_key(it2)))
  end)

  it('get_marked returns all marked keys', function()
    local it1 = make_item('/org/work.org', 10)
    local it2 = make_item('/org/personal.org', 5)
    Store.mark_toggle(item_key(it1))
    Store.mark_toggle(item_key(it2))
    local marked = Store.get_marked()
    assert.equals(2, #marked)
  end)

  it('get_marked returns empty when nothing marked', function()
    local marked = Store.get_marked()
    assert.equals(0, #marked)
  end)

  it('marks are independent per item key', function()
    local it1 = make_item('/org/work.org', 10)
    local it2 = make_item('/org/work.org', 20)
    Store.mark_toggle(item_key(it1))
    assert.is_true(Store.is_marked(item_key(it1)))
    assert.is_false(Store.is_marked(item_key(it2)))
  end)
end)

describe('bulk marking (layout rendering)', function()
  local layout_classic = require('org-super-agenda.core.layout.classic')
  local layout_compact = require('org-super-agenda.core.layout.compact')
  local Date = require('org-super-agenda.core.date')

  local cfg = {
    group_format = '* %s',
    show_filename = false,
    show_tags = false,
    heading_max_length = 60,
    classic = { heading_order = { 'todo', 'headline' }, short_date_labels = false, inline_dates = false },
    compact = { filename_min_width = 8, label_min_width = 10 },
  }

  local function make_groups(items)
    return { { name = 'Test', items = items, sort = nil } }
  end

  it('classic: unmarked item has two-space indent prefix', function()
    local it = make_item('/org/work.org', 10)
    local groups = make_groups({ it })
    local rows, _, lm = layout_classic.build(groups, 80, cfg, {})
    local item_line
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
      end
    end
    assert.is_not_nil(item_line)
    assert.equals('  ', item_line:sub(1, 2))
  end)

  it('classic: marked item has ● prefix', function()
    local it = make_item('/org/work.org', 10)
    local marked = { [item_key(it)] = true }
    local groups = make_groups({ it })
    local rows, hls, lm = layout_classic.build(groups, 80, cfg, marked)
    local item_line
    local item_lnum
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
        item_lnum = ln
      end
    end
    assert.is_not_nil(item_line)
    assert.equals('● ', item_line:sub(1, 4))
    -- OrgSA_Marked highlight should exist for this line
    local has_mark_hl = false
    for _, h in ipairs(hls) do
      if h[1] == item_lnum - 1 and h[4] == 'OrgSA_Marked' then
        has_mark_hl = true
      end
    end
    assert.is_true(has_mark_hl)
  end)

  it('compact: unmarked item starts with two-space indent', function()
    local it = Item.new({ headline = 'Task', todo_state = 'TODO', file = '/org/work.org', _src_line = 10, scheduled = Date.new(2025, 1, 1) })
    local groups = make_groups({ it })
    local rows, _, lm = layout_compact.build(groups, 80, cfg, {})
    local item_line
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
      end
    end
    assert.is_not_nil(item_line)
    assert.equals('  ', item_line:sub(1, 2))
  end)

  it('compact: marked item has ● prefix', function()
    local it = Item.new({ headline = 'Task', todo_state = 'TODO', file = '/org/work.org', _src_line = 10, scheduled = Date.new(2025, 1, 1) })
    local marked = { [item_key(it)] = true }
    local groups = make_groups({ it })
    local rows, hls, lm = layout_compact.build(groups, 80, cfg, marked)
    local item_line
    local item_lnum
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
        item_lnum = ln
      end
    end
    assert.is_not_nil(item_line)
    assert.equals('● ', item_line:sub(1, 4))
    local has_mark_hl = false
    for _, h in ipairs(hls) do
      if h[1] == item_lnum - 1 and h[4] == 'OrgSA_Marked' then
        has_mark_hl = true
      end
    end
    assert.is_true(has_mark_hl)
  end)
end)
