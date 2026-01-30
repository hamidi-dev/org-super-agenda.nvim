local hi = require('org-super-agenda.adapters.neovim.highlight')

describe('highlight', function()
  before_each(function()
    hi._done = false
    hi._state = {}
  end)

  it('creates highlight state', function()
    hi.ensure()
    assert.is_table(hi._state['TODO'])
    assert.is_true(hi.want('TODO', 'todo'))
  end)

  it('returns highlight group name', function()
    hi.ensure()
    assert.equals('OrgSA_TODO', hi.group('TODO'))
    assert.equals('OrgSA_UNKNOWN', hi.group('UNKNOWN'))
  end)
end)
