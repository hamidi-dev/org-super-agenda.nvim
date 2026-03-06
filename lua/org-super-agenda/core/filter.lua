-- core/filter.lua
local Q = require('org-super-agenda.core.query')

local F = {}

local function headline_match(it, text, fuzzy, cfg)
  if not text or text == '' then
    return true
  end
  local fn = (it.file or ''):match('[^/]+$') or ''
  fn = fn:gsub('%.org$', '')
  local tags = (it.tags and #it.tags > 0) and (':' .. table.concat(it.tags, ':') .. ':') or ''
  local corpus = (table.concat({ it.headline or '', it.todo_state or '', fn, tags }, ' ')):lower()
  if fuzzy then
    return #vim.fn.matchfuzzy({ corpus }, text) > 0
  else
    return corpus:find(text:lower(), 1, true) ~= nil
  end
end

function F.apply(items, opts, cfg)
  local out = items

  -- todo_filter
  if opts.todo_filter then
    local wanted = {}
    if type(opts.todo_filter) == 'string' then
      wanted[opts.todo_filter] = true
    else
      for _, st in ipairs(opts.todo_filter) do
        wanted[st] = true
      end
    end
    local t = {}
    for _, it in ipairs(out) do
      if wanted[it.todo_state] then
        t[#t + 1] = it
      end
    end
    out = t
  end

  -- headline filter
  if opts.headline_filter and opts.headline_filter ~= '' then
    local t = {}
    for _, it in ipairs(out) do
      if headline_match(it, opts.headline_filter, opts.headline_fuzzy, cfg) then
        t[#t + 1] = it
      end
    end
    out = t
  end

  -- advanced query
  if opts.query and opts.query ~= '' then
    local AST = Q.parse(opts.query)
    if AST and AST.matches then
      local t = {}
      for _, it in ipairs(out) do
        if AST.matches(it) then
          t[#t + 1] = it
        end
      end
      out = t
    end
  end

  -- include:
  --   - valid TODO states from cfg
  --   - OR items with NO TODO but with a date (scheduled or deadline) => events
  local valid = {}
  for _, st in ipairs(cfg.todo_states or {}) do
    valid[st.name] = true
  end
  local t = {}
  for _, it in ipairs(out) do
    local state = it.todo_state
    if valid[state] then
      t[#t + 1] = it
    elseif (state == nil or state == '') and (it.scheduled or it.deadline) then
      t[#t + 1] = it
    end
  end
  return t
end

return F
