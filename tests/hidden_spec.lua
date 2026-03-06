local config = require('org-super-agenda.config')
local store = require('org-super-agenda.app.store')
local services = require('org-super-agenda.app.services')
local pipeline = require('org-super-agenda.app.pipeline')

describe('hidden items', function()
  before_each(function()
    services.setup({
      cfg = config,
      store = store,
      source = {
        collect_items = function()
          return {}
        end,
      },
      view = {
        is_open = function()
          return false
        end,
      },
      pipeline = pipeline,
    })
    store.reset_hidden()
  end)

  it('clears hidden items on close when not persistent', function()
    store.hide('a:1')
    config.setup({ persist_hidden = false })
    services.agenda.on_close()
    assert.is_nil(next(store.get().hidden))
  end)

  it('keeps hidden items on close when persistent', function()
    store.hide('a:1')
    config.setup({ persist_hidden = true })
    services.agenda.on_close()
    assert.is_true(store.get().hidden['a:1'])
    config.setup({ persist_hidden = false })
  end)
end)
