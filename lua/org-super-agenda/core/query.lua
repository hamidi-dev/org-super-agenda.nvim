-- core/query.lua -- parse & matcher
local Date = require('org-super-agenda.core.date')
local Q = {}

local function prio_rank(p) return ({ A=3, B=2, C=1 })[p or ''] or 0 end
local function cmp(num, op, ref)
  if num == nil or not op or ref == nil then return true end
  if     op == '<'  then return num <  ref
  elseif op == '<=' then return num <= ref
  elseif op == '>'  then return num >  ref
  elseif op == '>=' then return num >= ref
  elseif op == ':'  then return tostring(num) == tostring(ref)
  else return num == ref end
end

function Q.parse(q)
  if not q or q == '' then return nil end
  q = q:gsub('%s+', ' ')
  local P = {
    inc = {}, exc = {}, tags_inc = {}, tags_exc = {}, file_inc = {}, todo = {},
    prio = { op=nil, val=nil },
    due=nil, sched=nil, before=nil, after=nil, is_overdue=nil, is_done=nil, has_todo=nil,
  }
  local function splitbar(s) local r={}; for p in s:gmatch('[^|]+') do r[#r+1]=p end; return r end

  for tok in q:gmatch('%S+') do
    local neg = tok:sub(1,1) == '-'
    local t   = neg and tok:sub(2) or tok
    if t:match('^tag:') then
      for _, v in ipairs(splitbar(t:sub(5))) do (neg and P.tags_exc or P.tags_inc)[v:lower()] = true end
    elseif t:match('^file:') then
      P.file_inc[#P.file_inc + 1] = t:sub(6):lower()
    elseif t:match('^todo:') then
      for _, v in ipairs(splitbar(t:sub(6))) do P.todo[v] = true end
    elseif t:match('^prio[<>]=?') or t:match('^prio:') then
      local op, val = t:match('^prio([<>]=?)([ABC])')
      if not op then op = ':'; val = t:match('^prio:(%w+)') end
      P.prio = { op=op, val=val }
    elseif t:match('^due[<>=]') then
      local op, n = t:match('^due([<>=]=?)(%-?%d+)'); P.due = { op=op, n=tonumber(n) }
    elseif t:match('^sched[<>=]') or t:match('^sched=') then
      local op, n = t:match('^sched([<>=]=?)(%-?%d+)'); P.sched = { op=op, n=tonumber(n) }
    elseif t:match('^before:') then
      P.before = Date.parse(t:sub(8))
    elseif t:match('^after:') then
      P.after = Date.parse(t:sub(7))
    elseif t == 'is:overdue' then
      P.is_overdue = not neg
    elseif t == 'is:done' then
      P.is_done = not neg
    elseif t == 'has:todo' then
      P.has_todo = not neg
    else
      (neg and P.exc or P.inc)[#(neg and P.exc or P.inc) + 1] = t:lower()
    end
  end

  local function corpus(it)
    local fn   = (it.file or ''):match('[^/]+$') or ''
    fn = fn:gsub('%.org$', '')
    local tags = (it.tags and #it.tags > 0) and (':'..table.concat(it.tags,':')..':') or ''
    return (table.concat({ it.headline or '', it.todo_state or '', fn, tags }, ' ')):lower()
  end

  local function matches(it)
    local text = corpus(it)
    -- include tokens
    for _, w in ipairs(P.inc) do if not text:find(w, 1, true) then return false end end
    -- exclude tokens
    for _, w in ipairs(P.exc) do if text:find(w, 1, true) then return false end end
    -- tags
    if next(P.tags_inc) then
      local has=false
      for t,_ in pairs(P.tags_inc) do
        for _, it_tag in ipairs(it.tags or {}) do if it_tag:lower()==t then has=true end end
      end
      if not has then return false end
    end
    if next(P.tags_exc) then
      for t,_ in pairs(P.tags_exc) do
        for _, it_tag in ipairs(it.tags or {}) do if it_tag:lower()==t then return false end end
      end
    end
    -- files (all must match substring of filename)
    if #P.file_inc > 0 then
      local fn = ((it.file or ''):match('[^/]+$') or ''):lower()
      for _, sub in ipairs(P.file_inc) do if not fn:find(sub, 1, true) then return false end end
    end
    -- todo
    if next(P.todo) and not P.todo[it.todo_state or ''] then return false end
    -- prio
    if P.prio.op then
      if not cmp(prio_rank(it.priority), P.prio.op, prio_rank(P.prio.val)) then return false end
    end
    -- due/sched (relative in days)
    local function days(x) return x and x:days_from_today() or nil end
    if P.due   then local d = days(it.deadline);  if d == nil or not cmp(d, P.due.op,   P.due.n)   then return false end end
    if P.sched then local d = days(it.scheduled); if d == nil or not cmp(d, P.sched.op, P.sched.n) then return false end end
    -- absolute before/after
    if P.before and not (it.deadline and it.deadline:to_time() < P.before:to_time()) then return false end
    if P.after  and not (it.scheduled and it.scheduled:to_time() > P.after:to_time()) then return false end
    -- flags
    if P.is_overdue ~= nil then
      local over = (it.deadline and it.deadline:is_past()) or (it.scheduled and it.scheduled:is_past())
      if P.is_overdue and not over then return false end
      if not P.is_overdue and over then return false end
    end
    if P.is_done ~= nil then
      local done = (it.todo_state == 'DONE')
      if P.is_done and not done then return false end
      if not P.is_done and done then return false end
    end
    if P.has_todo ~= nil then
      local has = it.todo_state ~= nil and it.todo_state ~= ''
      if P.has_todo and not has then return false end
      if not P.has_todo and has then return false end
    end
    return true
  end

  return { matches = matches }
end

return Q

