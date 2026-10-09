-- adapters/neovim/source_common.lua -- helpers shared by the SourcePort backends
local utils = require('org-super-agenda.adapters.neovim.utils')
local cfg = require('org-super-agenda.config').get

local C = {}

function C.normalize_path(path)
  local absolute = vim.fn.fnamemodify(utils.expand(path), ':p')
  local normalized = vim.fn.resolve(absolute):gsub('\\', '/')
  if normalized ~= '/' and not normalized:match('^%a:/$') then
    normalized = normalized:gsub('/+$', '')
  end
  return normalized
end

local function is_in_directory(path, directory)
  return path == directory or path:sub(1, #directory + 1) == directory .. '/'
end

function C.has_overrides()
  local c = cfg()
  return #(c.org_files or {}) > 0 or #(c.org_directories or {}) > 0
end

-- Normalized paths from org_files + org_directories
function C.configured_paths()
  local c = cfg()
  local seen, paths = {}, {}
  local function add(path)
    if path and path ~= '' then
      local p = C.normalize_path(path)
      if not seen[p] then
        seen[p] = true
        paths[#paths + 1] = p
      end
    end
  end
  for _, path in ipairs(c.org_files or {}) do
    add(path)
  end
  for _, directory in ipairs(c.org_directories or {}) do
    for _, path in ipairs(vim.fn.globpath(utils.expand(directory), '**/*.org', false, true)) do
      add(path)
    end
  end
  return paths
end

-- Predicate: is this path excluded by exclude_files / exclude_directories?
function C.exclusion()
  local c = cfg()
  local skip = {}
  for _, f in ipairs(c.exclude_files or {}) do
    if f and f ~= '' then
      skip[C.normalize_path(f)] = true
    end
  end
  local skip_dirs = {}
  for _, d in ipairs(c.exclude_directories or {}) do
    if d and d ~= '' then
      skip_dirs[#skip_dirs + 1] = C.normalize_path(d)
    end
  end
  return function(path)
    if not path then
      return true
    end
    local p = C.normalize_path(path)
    if skip[p] then
      return true
    end
    for _, d in ipairs(skip_dirs) do
      if is_in_directory(p, d) then
        return true
      end
    end
    return false
  end
end

-- Merge tags with no duplicates (order: inherited first, then own tags)
function C.merge_tags(inherited, own)
  local seen, out = {}, {}
  for _, t in ipairs(inherited or {}) do
    if t ~= '' and not seen[t] then
      seen[t] = true
      out[#out + 1] = t
    end
  end
  for _, t in ipairs(own or {}) do
    if t ~= '' and not seen[t] then
      seen[t] = true
      out[#out + 1] = t
    end
  end
  return out
end

-- Per-run cache of file lines and "has more content" answers
function C.new_cache()
  return { lines = {}, has_more = {} }
end

function C.file_lines(cache, fname)
  if cache.lines[fname] then
    return cache.lines[fname]
  end
  local bufnr = vim.fn.bufnr(fname)
  local lines
  if bufnr ~= -1 then
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    lines = vim.fn.readfile(fname)
  end
  cache.lines[fname] = lines
  return lines
end

local function section_range(lines, pos_start)
  local start = pos_start
  while start > 0 and not (lines[start] or ''):match('^%*+') do
    start = start - 1
  end
  if start == 0 then
    return nil
  end
  local lvl = #((lines[start] or ''):match('^(%*+)') or '')
  local stop = #lines
  for i = start + 1, #lines do
    local s = (lines[i] or ''):match('^(%*+)')
    if s and #s <= lvl then
      stop = i - 1
      break
    end
  end
  return start, stop, lvl
end

local function strip_planning_only(s)
  local before
  repeat
    before = s
    s = s:gsub('%s*SCHEDULED:%s*<[^>]+>', '')
      :gsub('%s*DEADLINE:%s*<[^>]+>', '')
      :gsub('%s*CLOSED:%s*%[[^%]]+%]', '')
      :gsub('^%s*<%d%d%d%d%-%d%d%-%d%d[^>]*>%s*$', '')
  until s == before
  return (s:gsub('%s+', ''))
end

local function is_meta_line(s, drawer_state)
  if s == '' then
    return true, drawer_state
  end
  if s:match('^:%u+:%s*$') then
    drawer_state.open = true
    return true, drawer_state
  end
  if s:match('^:END:%s*$') then
    drawer_state.open = false
    return true, drawer_state
  end
  if drawer_state.open then
    return true, drawer_state
  end
  if s:match('^CLOCK:%s*') then
    return true, drawer_state
  end
  if strip_planning_only(s) == '' then
    return true, drawer_state
  end
  return false, drawer_state
end

-- Does the headline at fname:start_line have children or body text beyond planning/drawers?
function C.has_more(cache, fname, start_line, has_children)
  local key = (fname or '') .. ':' .. tostring(start_line or 0)
  if cache.has_more[key] ~= nil then
    return cache.has_more[key]
  end
  local function done(v)
    cache.has_more[key] = v
    return v
  end

  if has_children then
    return done(true)
  end
  if not (fname and start_line) then
    return done(false)
  end

  local lines = C.file_lines(cache, fname)
  local s, e = section_range(lines, start_line)
  if not s then
    return done(false)
  end

  local drawer_state = { open = false }
  for i = s + 1, e do
    local trimmed = (lines[i] or ''):gsub('^%s+', '')
    local meta, new_state = is_meta_line(trimmed, drawer_state)
    drawer_state = new_state
    if not meta then
      return done(true)
    end
  end
  return done(false)
end

-- Dedupe by file:line, then keep items with a configured TODO state or dated events
function C.finalize(items)
  local seen, uniq = {}, {}
  for _, it in ipairs(items) do
    local key = string.format('%s:%s', it.file or '', it._src_line or 0)
    if not seen[key] then
      seen[key] = true
      uniq[#uniq + 1] = it
    end
  end

  local valid = {}
  for _, st in ipairs(cfg().todo_states or {}) do
    valid[st.name] = true
  end
  local out = {}
  for _, it in ipairs(uniq) do
    local state = it.todo_state
    if valid[state] then
      out[#out + 1] = it
    elseif (state == nil or state == '') and (it.scheduled or it.deadline) then
      out[#out + 1] = it
    end
  end
  return out
end

return C
