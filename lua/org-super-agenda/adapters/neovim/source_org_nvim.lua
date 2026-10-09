-- adapters/neovim/source_org_nvim.lua -- implements SourcePort on org.nvim's public API (org.api)
local common = require('org-super-agenda.adapters.neovim.source_common')
local Date = require('org-super-agenda.core.date')
local Item = require('org-super-agenda.core.item')

local S = {}

function S.api()
  local ok, api = pcall(require, 'org.api')
  if not ok or type(api) ~= 'table' or type(api.has) ~= 'function' or not api.has('1.0') then
    error('org.nvim is required but not found. Please install xheisenbugx/org.nvim')
  end
  return api
end

function S.to_date(d)
  if not d then
    return nil
  end
  local timestamp_end
  if d.hour and d.end_hour then
    timestamp_end = os.time({ year = d.year, month = d.month, day = d.day, hour = d.end_hour, min = d.end_min or 0 })
  end
  return Date.new(d.year, d.month, d.day, d.active ~= false, d.hour, d.min, d.hour == nil, timestamp_end)
end

local function lower_keys(props)
  local out = {}
  for k, v in pairs(props or {}) do
    out[k:lower()] = v
  end
  return out
end

local function load_files(api)
  local loaded
  if common.has_overrides() then
    local paths = common.configured_paths()
    loaded = #paths > 0 and api.load(paths) or {}
  else
    loaded = api.load()
  end
  local excluded = common.exclusion()
  local files = {}
  for _, f in ipairs(loaded or {}) do
    if f.file and not excluded(f.file) then
      files[#files + 1] = f
    end
  end
  return files
end

local function clocked_key(api)
  local ok, status = pcall(api.clock.status)
  local h = ok and status and status.headline
  if not (h and h.file and h.line) then
    return nil
  end
  return common.normalize_path(h.file) .. ':' .. h.line
end

function S.collect()
  local api = S.api()
  local cache = common.new_cache()
  local clocked = clocked_key(api)
  local items = {}

  for _, file in ipairs(load_files(api)) do
    local fname = file.file
    local stack, nodes = {}, {}
    for _, h in ipairs(file.headlines or {}) do
      while #stack > 0 and stack[#stack].h.level >= h.level do
        table.remove(stack)
      end
      local parents = {}
      for i = #stack, 1, -1 do
        local p = stack[i].h
        parents[#parents + 1] = {
          key = string.format('%s:%s', fname, p.line),
          headline = p.title,
          level = p.level,
          todo_state = p.todo,
          file = fname,
          _src_line = p.line,
        }
      end
      if #stack > 0 then
        stack[#stack].has_children = true
      end
      local node = { h = h, parents = parents }
      stack[#stack + 1] = node
      nodes[#nodes + 1] = node
    end

    for _, node in ipairs(nodes) do
      local h = node.h
      local item = Item.new({
        headline = h.title,
        level = h.level,
        tags = vim.deepcopy(h.all_tags or h.tags or {}),
        priority = h.priority,
        todo_state = h.todo,
        scheduled = S.to_date(h.scheduled),
        deadline = S.to_date(h.deadline),
        properties = lower_keys(h.properties),
        file = fname,
        _src_line = h.line,
        clocked_in = clocked ~= nil and clocked == (common.normalize_path(fname) .. ':' .. h.line),
        has_more = common.has_more(cache, fname, h.line, node.has_children),
        is_archived = h.archived or false,
      })
      item.parents = node.parents
      items[#items + 1] = item
    end
  end

  return common.finalize(items)
end

return S
