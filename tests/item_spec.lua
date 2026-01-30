local Item = require('org-super-agenda.core.item')

describe('org_item', function()
  it('matches tags case-insensitively', function()
    local it = Item.new{ tags = {'Work','tEst'} }
    assert.is_true(it:has_tag('work'))
    assert.is_true(it:has_tag('TEST'))
    assert.is_nil(it:has_tag('other'))
  end)

  it('determines actionable state', function()
    assert.is_true(Item.new{ todo_state='TODO', tags={} }:is_actionable())
    assert.is_true(Item.new{ todo_state='', scheduled=true }:is_actionable())
    assert.is_nil(Item.new{ todo_state='DONE' }:is_actionable())
  end)
end)
