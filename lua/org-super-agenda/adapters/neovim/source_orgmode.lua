-- adapters/neovim/source_orgmode.lua -- implements SourcePort (with tag inheritance)
local common = require('org-super-agenda.adapters.neovim.source_common')
local Date = require('org-super-agenda.core.date')
local Item = require('org-super-agenda.core.item')

local S = {}

local function load_configured_files(org_api)
  local files = {}
  for _, path in ipairs(common.configured_paths()) do
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
  local ok_api, api_root = pcall(require, 'orgmode.api')
  local org_api = ok_api and (api_root.load and api_root or api_root.org) or nil
  if not org_api or not org_api.load then
    error('nvim-orgmode is required but not found. Please install nvim-orgmode/orgmode')
  end

  local all_files
  if common.has_overrides() then
    all_files = load_configured_files(org_api)
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

  local excluded = common.exclusion()
  local files = {}
  for _, f in ipairs(all_files) do
    local path = f.filename or (f._file and f._file.filename)
    if path and not excluded(path) then
      if f.reload then
        local reloaded = f:reload()
        files[#files + 1] = reloaded or f
      else
        files[#files + 1] = f
      end
    end
  end

  return files
end

local merge_tags = common.merge_tags
local cache = common.new_cache()

local function headline_has_more(h)
  local fname = (h.file and h.file.filename) or h.filename
  local start_l = h.position and h.position.start_line or nil
  return common.has_more(cache, fname, start_l, h.headlines and #h.headlines > 0)
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
  cache = common.new_cache()

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
  for _, f in ipairs(files) do
    local fname = (f.file and f.file.filename) or f.filename
    if fname then
      common.file_lines(cache, fname)
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

  return common.finalize(items)
end

return S
