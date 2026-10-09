-- adapters/neovim/backend.lua -- selects the org engine (nvim-orgmode or org.nvim)
local cfg = require('org-super-agenda.config').get

local M = {}

local MODULES = {
  orgmode = 'org-super-agenda.adapters.neovim.backends.orgmode',
  ['org.nvim'] = 'org-super-agenda.adapters.neovim.backends.org_nvim',
}

local ALIASES = {
  orgmode = 'orgmode',
  ['nvim-orgmode'] = 'orgmode',
  ['org.nvim'] = 'org.nvim',
  org_nvim = 'org.nvim',
}

function M.resolve_name(name)
  name = name or 'auto'
  if name == 'auto' then
    if require(MODULES.orgmode).available() then
      return 'orgmode'
    end
    if require(MODULES['org.nvim']).available() then
      return 'org.nvim'
    end
    error('org-super-agenda needs an org engine: install nvim-orgmode/orgmode or xheisenbugx/org.nvim', 0)
  end
  return ALIASES[name] or error(string.format("org-super-agenda: unknown backend '%s' (use 'auto', 'orgmode' or 'org.nvim')", tostring(name)))
end

function M.get()
  return require(MODULES[M.resolve_name(cfg().backend)])
end

-- SourcePort that follows the configured backend
M.source = {
  collect = function()
    return M.get().source.collect()
  end,
}

return M
