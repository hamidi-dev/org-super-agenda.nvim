-- adapters/neovim/source_orgmode.lua -- implements SourcePort (with tag inheritance)
local utils = require('org-super-agenda.adapters.neovim.utils')
local cfg = require('org-super-agenda.config').get
local Date = require('org-super-agenda.core.date')
local Item = require('org-super-agenda.core.item')

local S = {}

local function normalize_path(path)
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

local function load_configured_files(C, org_api)
  local paths = {}
  local function add(path)
    if path and path ~= '' then
      paths[normalize_path(path)] = true
    end
  end

  for _, path in ipairs(C.org_files or {}) do
    add(path)
  end
  for _, directory in ipairs(C.org_directories or {}) do
    for _, path in ipairs(vim.fn.globpath(utils.expand(directory), '**/*.org', false, true)) do
      add(path)
    end
  end

  local files = {}
  for path in pairs(paths) do
    local ok, loaded = pcall(org_api.load, path)
    if ok and loaded then
      if loaded.filename or loaded._file then
        files[#files + 1] = loaded
      elseif vim.islist(loaded) then
        vim.list_extend(files, loaded)
      end
    end
  end
  return files
end

-- Load configured compatibility overrides, or nvim-orgmode's agenda files.
local function load_org_files()
  local C = cfg()

  local ok_api, api_root = pcall(require, 'orgmode.api')
  local org_api = ok_api and (api_root.load and api_root or api_root.org) or nil
  if not org_api or not org_api.load then
    error('nvim-orgmode is required but not found. Please install nvim-orgmode/orgmode')
  end

  local all_files
  if #(C.org_files or {}) > 0 or #(C.org_directories or {}) > 0 then
    all_files = load_configured_files(C, org_api)
  else
    local ok_org, orgmode = pcall(require, 'orgmode')
    if not ok_org or not orgmode or not orgmode.files or not orgmode.files.load_sync then
      error('nvim-orgmode is required but not found. Please install nvim-orgmode/orgmode')
    end

    -- Ensure orgmode has fully loaded agenda files before reading them.
    -- Without this, orgmode.api.load() can return an empty/partial list on first open.
    pcall(function()
      orgmode.files:load_sync(false, 20000)
    end)

    -- orgmode.api.load() with no args returns all agenda files already resolved.
    local ok, loaded = pcall(org_api.load)
    if not ok or not loaded then
      return {}
    end
    all_files = loaded
  end

  -- Build exclusion set
  local skip = {}
  for _, f in ipairs(C.exclude_files or {}) do
    if f and f ~= '' then
      skip[normalize_path(f)] = true
    end
  end
  local skip_dirs = {}
  for _, d in ipairs(C.exclude_directories or {}) do
    if d and d ~= '' then
      skip_dirs[#skip_dirs + 1] = normalize_path(d)
    end
  end

  local files = {}
  for _, f in ipairs(all_files) do
    local path = f.filename or (f._file and f._file.filename)
    local normalized_path = path and normalize_path(path) or nil
    if normalized_path and not skip[normalized_path] then
      local excluded = false
      for _, d in ipairs(skip_dirs) do
        if is_in_directory(normalized_path, d) then
          excluded = true
          break
        end
      end
      if not excluded then
        if f.reload then
          local reloaded = f:reload()
          files[#files + 1] = reloaded or f
        else
          files[#files + 1] = f
        end
      end
    end
  end

  return files
end

-- Merge tags with no duplicates (order: inherited first, then own tags)
local function merge_tags(inherited, own)
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

local HAS_MORE_CACHE = {}
local FILE_LINES = {} -- [filename] -> { lines... }

local function cache_key(h)
  local f = (h.file and h.file.filename) or h.filename or ''
  local ln = (h.position and h.position.start_line) or 0
  return f .. ':' .. tostring(ln)
end

local function get_file_lines(fname)
  if FILE_LINES[fname] then
    return FILE_LINES[fname]
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
  FILE_LINES[fname] = lines
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
  -- Drawer-Start/Ende
  if s:match('^:%u+:%s*$') then
    -- z.B. :PROPERTIES: oder :LOGBOOK:
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
  -- CLOCK / reine Planning / reine Timestamp
  if s:match('^CLOCK:%s*') then
    return true, drawer_state
  end
  if strip_planning_only(s) == '' then
    return true, drawer_state
  end
  return false, drawer_state
end

local function headline_has_more(h)
  local key = cache_key(h)
  if HAS_MORE_CACHE[key] ~= nil then
    return HAS_MORE_CACHE[key]
  end

  -- Kinder? → sofort ja
  if h.headlines and #h.headlines > 0 then
    HAS_MORE_CACHE[key] = true
    return true
  end

  local fname = (h.file and h.file.filename) or h.filename
  local start_l = h.position and h.position.start_line or nil
  if not (fname and start_l) then
    HAS_MORE_CACHE[key] = false
    return false
  end

  local lines = get_file_lines(fname)
  local s, e = section_range(lines, start_l)
  if not s then
    HAS_MORE_CACHE[key] = false
    return false
  end

  local drawer_state = { open = false }
  -- Inhalt beginnt typischerweise ab s+1
  for i = s + 1, e do
    local raw = lines[i] or ''
    local trimmed = raw:gsub('^%s+', '')
    local meta, new_state = is_meta_line(trimmed, drawer_state)
    drawer_state = new_state
    if not meta then
      HAS_MORE_CACHE[key] = true
      return true
    end
  end

  HAS_MORE_CACHE[key] = false
  return false
end

-- Convert orgmode headline → Item, honoring inherited tags
local function headline_to_item(h, inherited_tags)
  return Item.new({
    headline = h.title,
    level = h.level,
    tags = merge_tags(inherited_tags, h.tags or {}),
    priority = h.priority,
    todo_state = h.todo_value, -- may be nil/'' for events
    scheduled = Date.from_orgdate(h.scheduled),
    deadline = Date.from_orgdate(h.deadline),
    properties = h.properties or {},
    file = h.file and h.file.filename or h.filename,
    _src_line = h.position and h.position.start_line,
    clocked_in = (h._section and h._section.is_clocked_in and h._section:is_clocked_in()) or false,
    has_more = headline_has_more(h),
    is_archived = h.is_archived or false,
  })
end

function S.collect()
  -- Reset Caches pro Lauf
  HAS_MORE_CACHE = {}
  FILE_LINES = {}

  local items = {}

  -- Walk the tree, passing accumulated (inherited) tags and ancestry downwards
  local function walk(hl, inherited_tags, ancestry)
    local all_tags = merge_tags(inherited_tags, hl.tags or {})
    local item = headline_to_item(hl, inherited_tags)
    -- ancestor chain, nearest parent first (used by the tree view)
    local parents = {}
    for i = #ancestry, 1, -1 do
      parents[#parents + 1] = ancestry[i]
    end
    item.parents = parents
    items[#items + 1] = item

    local child_ancestry = vim.list_slice(ancestry, 1, #ancestry)
    child_ancestry[#child_ancestry + 1] = {
      key = string.format('%s:%s', item.file or '', item._src_line or 0),
      headline = hl.title,
      level = hl.level,
      todo_state = hl.todo_value,
      file = item.file,
      _src_line = item._src_line,
    }
    for _, c in ipairs(hl.headlines or {}) do
      walk(c, all_tags, child_ancestry)
    end
  end

  local files = load_org_files()
  -- Optional: Vorab Lines-Cache füllen (einmal pro Datei)
  for _, f in ipairs(files) do
    local fname = (f.file and f.file.filename) or f.filename
    if fname and not FILE_LINES[fname] then
      get_file_lines(fname)
    end
  end

  for _, file in ipairs(files) do
    -- Get filetags from the internal file object to pass as initial inherited tags
    local filetags = file._file:get_filetags() or {}

    for _, hl in ipairs(file.headlines or {}) do
      -- Top-level headlines inherit filetags
      walk(hl, filetags, {})
    end
  end

  -- Dedupe by file:line
  local seen, uniq = {}, {}
  for _, it in ipairs(items) do
    local key = string.format('%s:%s', it.file or '', it._src_line or 0)
    if not seen[key] then
      seen[key] = true
      uniq[#uniq + 1] = it
    end
  end

  -- Keep either:
  --  • items with a known TODO state, OR
  --  • items with NO TODO but with a date (scheduled/deadline)  ← events
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

return S
