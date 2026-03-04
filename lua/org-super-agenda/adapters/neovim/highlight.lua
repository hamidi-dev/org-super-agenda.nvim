-- adapters/neovim/highlight.lua
local get_cfg = require('org-super-agenda.config').get
local H = { _done = false, _state = {} }

function H.ensure()
  if H._done then return end
  vim.cmd('highlight default OrgSA_Group gui=bold')
  pcall(vim.cmd, 'highlight default OrgSA_NONE guifg=#A0A0A0 gui=bold')
  pcall(vim.cmd, 'highlight default OrgSA_Marked guifg=#FFB86C gui=bold')

  for _, st in ipairs(get_cfg().todo_states or {}) do
    local hl_group = st.hl_group or (type(st.highlight) == 'string' and st.highlight) or ('OrgSA_' .. st.name)
    local fields   = st.fields or (type(st.highlight) == 'table' and st.highlight) or { 'todo','headline','priority','date','tags','filename' }
    local gui      = st.strike_through and 'gui=bold,strikethrough' or 'gui=bold'
    local cmd      = st.color and string.format('highlight default %s guifg=%s %s', hl_group, st.color, gui)
                               or string.format('highlight default %s %s', hl_group, gui)
    vim.cmd(cmd)
    local set = {}; for _, f in ipairs(fields) do set[f] = true end
    H._state[st.name] = { group = hl_group, fields = set }
  end
  H._done = true
end

function H.want(state, field)
  local cfg = H._state[state or ''] or {}
  return cfg.fields and cfg.fields[field]
end

function H.group(state)
  if state == nil or state == '' then
    return 'OrgSA_NONE'
  end
  local hl = H._state[state] or {}
  return hl.group or ('OrgSA_' .. state)
end

return H

