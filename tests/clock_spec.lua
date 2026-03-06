local Item = require('org-super-agenda.core.item')
local layout_classic = require('org-super-agenda.core.layout.classic')
local layout_compact = require('org-super-agenda.core.layout.compact')

describe('clock indicator rendering', function()
  local cfg = {
    group_format = '* %s',
    show_filename = false,
    show_tags = false,
    heading_max_length = 60,
    classic = { heading_order = { 'todo', 'headline' }, short_date_labels = false, inline_dates = false },
    compact = { filename_min_width = 8, label_min_width = 10 },
  }

  local function make_groups(it)
    return { { name = 'Today', items = { it }, sort = nil } }
  end

  it('shows clock indicator in classic layout for active item', function()
    local it = Item.new({ headline = 'Task', todo_state = 'TODO', file = '/org/work.org', _src_line = 3, clocked_in = true })
    local rows, hls, lm = layout_classic.build(make_groups(it), 80, cfg, {})
    local item_line, item_lnum
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
        item_lnum = ln
      end
    end
    assert.is_not_nil(item_line)
    assert.is_true(item_line:find('⏱ ', 1, true) ~= nil)

    local has_clock_hl = false
    for _, h in ipairs(hls) do
      if h[1] == item_lnum - 1 and h[4] == 'OrgSA_Clock' then
        has_clock_hl = true
      end
    end
    assert.is_true(has_clock_hl)
  end)

  it('shows clock indicator in compact layout for active item', function()
    local it = Item.new({ headline = 'Task', todo_state = 'TODO', file = '/org/work.org', _src_line = 3, clocked_in = true })
    local rows, hls, lm = layout_compact.build(make_groups(it), 80, cfg, {})
    local item_line, item_lnum
    for ln, entry in pairs(lm) do
      if entry == it then
        item_line = rows[ln]
        item_lnum = ln
      end
    end
    assert.is_not_nil(item_line)
    assert.is_true(item_line:find('⏱ ', 1, true) ~= nil)

    local has_clock_hl = false
    for _, h in ipairs(hls) do
      if h[1] == item_lnum - 1 and h[4] == 'OrgSA_Clock' then
        has_clock_hl = true
      end
    end
    assert.is_true(has_clock_hl)
  end)
end)
