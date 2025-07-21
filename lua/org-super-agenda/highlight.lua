-- org-super-agenda.highlight -----------------------------------------------
local get_cfg = require('org-super-agenda.config').get
local H       = { _done = false, _state = {} }

-- public --------------------------------------------------------------------
function H.ensure()
  if H._done then return end
  vim.cmd('highlight default OrgSA_Group gui=bold')

  for _, st in ipairs(get_cfg().todo_states or {}) do
    local hl_group = st.hl_group
        or (type(st.highlight) == 'string' and st.highlight)
        or ('OrgSA_' .. st.name)

    local fields = st.fields
        or (type(st.highlight) == 'table' and st.highlight)
        or { 'todo', 'headline' }

    local gui = st.strike_through and 'gui=bold,strikethrough' or 'gui=bold'
    local cmd = st.color
        and string.format('highlight default %s guifg=%s %s', hl_group, st.color, gui)
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
  local hl = H._state[state or ''] or {}
  return hl.group or ('OrgSA_' .. (state or 'TODO'))
end

return H
