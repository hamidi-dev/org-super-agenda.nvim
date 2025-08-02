local M = {}

-- borrow helpers (self-contained, trimmed for our use)
local function heading_range(lines, pos)
  local start = pos
  while start > 0 and not lines[start]:match("^%*+") do
    start = start - 1
  end
  if start == 0 then return nil end
  local lvl = #(lines[start]:match("^(%*+)"))
  local stop = #lines
  for i = start + 1, #lines do
    local s = lines[i]:match("^(%*+)")
    if s and #s <= lvl then
      stop = i - 1; break
    end
  end
  return start, stop, lvl
end

local function adjust_levels(seg, diff)
  if diff == 0 then return seg end
  local res = {}
  for _, l in ipairs(seg) do
    local stars, rest = l:match("^(%*+)(.*)")
    if stars then
      table.insert(res, string.rep("*", #stars + diff) .. rest)
    else
      table.insert(res, l)
    end
  end
  return res
end

local function reload_if_open(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == path
        and not vim.api.nvim_buf_get_option(b, "modified") then
      vim.api.nvim_buf_call(b, function() vim.cmd("edit!") end)
      break
    end
  end
end

local function move_segment(src, s_line, e_line, target_file, insert_pos, diff)
  local lines   = vim.fn.readfile(src)
  local segment = vim.list_slice(lines, s_line, e_line)
  for i = e_line, s_line, -1 do table.remove(lines, i) end
  vim.fn.writefile(lines, src)

  local tlines = vim.fn.readfile(target_file)
  segment      = adjust_levels(segment, diff)
  insert_pos   = insert_pos or (#tlines + 1)
  for i, l in ipairs(segment) do
    table.insert(tlines, insert_pos + i - 1, l)
  end
  vim.fn.writefile(tlines, target_file)

  reload_if_open(src)
  reload_if_open(target_file)
end

-- Build Telescope pickers using org-telescope scanner for target options
local function open_picker(params)
  local ok_ts, telescope_pickers = pcall(require, "telescope.pickers")
  local ok_sc, scanner           = pcall(require, "org-telescope.scanner")
  if not ok_ts or not ok_sc then
    vim.notify("Refile requires telescope + org-telescope.", vim.log.levels.WARN)
    return
  end
  local customPickers = (pcall(require, "org-telescope.pickers") and require("org-telescope.pickers")) or nil
  if customPickers and customPickers.highlight_groups then customPickers.highlight_groups() end

  local finders, conf, actions, action_state =
      require("telescope.finders"),
      require("telescope.config").values,
      require("telescope.actions"),
      require("telescope.actions.state")

  local all_headlines = scanner.scan() -- { file, line, level, text, ... }

  local files_set = {}
  for _, h in ipairs(all_headlines) do files_set[h.file] = true end
  local files = {}
  for f, _ in pairs(files_set) do table.insert(files, f) end
  table.sort(files)

  local function make_file_entries()
    local tbl = {}
    for i, f in ipairs(files) do
      tbl[i] = {
        value = { file = f, line = 1, level = 0 },
        display = vim.fn.fnamemodify(f, ":t"),
        ordinal = f,
      }
    end
    return tbl
  end

  local function make_headline_entries()
    local tbl = {}
    for i, h in ipairs(all_headlines) do
      local indent = string.rep("  ", (h.level or 1) - 1)
      tbl[i] = {
        value   = h,
        display = indent .. (h.text or "") .. " (" .. vim.fn.fnamemodify(h.file, ":t") .. ")",
        ordinal = (h.text or "") .. " " .. h.file,
      }
    end
    return tbl
  end

  local mode = "file"
  local function build_picker(entries, title)
    return telescope_pickers.new({
      prompt_title = title,
    }, {
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          return { value = e.value, display = e.display, ordinal = e.ordinal }
        end,
      },
      sorter = conf.generic_sorter({}),
      previewer = (customPickers and customPickers.custom_previewer and customPickers.custom_previewer()) or nil,
      attach_mappings = function(bufnr, map)
        local function toggle()
          actions.close(bufnr)
          mode = (mode == "file") and "heading" or "file"
          local p = (mode == "file")
              and build_picker(make_file_entries(), "Select Target File")
              or build_picker(make_headline_entries(), "Select Target Heading")
          p:find()
        end
        map("i", "<C-Space>", toggle); map("n", "<C-Space>", toggle)

        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(bufnr)
          if not sel or not sel.value then return end
          if mode == "file" then
            move_segment(params.src_file, params.s, params.e, sel.value.file, nil, 0)
          else
            local tlines      = vim.fn.readfile(sel.value.file)
            local _, tstop    = heading_range(tlines, sel.value.line)
            local insert_line = (tstop or #tlines) + 1
            local diff        = (sel.value.level + 1) - params.src_level
            move_segment(params.src_file, params.s, params.e, sel.value.file, insert_line, diff)
          end
          -- refresh agenda view afterwards
          local ok_ag, osa = pcall(require, "org-super-agenda")
          if ok_ag then osa.refresh(vim.api.nvim_win_get_cursor(0)) end
        end)
        return true
      end,
    })
  end

  local picker = build_picker(make_file_entries(), "Select Target File")
  picker:find()
end

-- public: start a refile for known src info (file + start/end + level)
function M.start_refile(src_file, start_line, end_line, src_level)
  if not (src_file and start_line and end_line and src_level) then
    return vim.notify("Invalid refile request (missing positions).", vim.log.levels.ERROR)
  end
  open_picker({
    src_file  = src_file,
    s         = start_line,
    e         = end_line,
    src_level = src_level,
  })
end

return M
