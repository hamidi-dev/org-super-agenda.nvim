-- adapters/neovim/guard.lua -- buffer state and swap-file checks shared by backends
local G = {}

function G.is_swap_error(err)
  local s = tostring(err or '')
  return s:find('Vim:E325', 1, true) ~= nil or s:find('E325:', 1, true) ~= nil
end

local function swap_glob_candidates(path)
  local abs = vim.fn.fnamemodify(path, ':p')
  local base = vim.fn.fnamemodify(abs, ':t')
  local candidates = {}

  local dir_entries = vim.opt.directory:get()
  if type(dir_entries) ~= 'table' then
    dir_entries = vim.split(vim.o.directory or '', ',', { plain = true, trimempty = true })
  end

  for _, entry in ipairs(dir_entries or {}) do
    if entry and entry ~= '' and entry ~= '.' then
      local expanded = vim.fn.expand(entry)
      if expanded:sub(-2) == '//' then
        local root = expanded:gsub('/+$', '')
        local mangled = abs:gsub('[:/\\]', '%%')
        candidates[#candidates + 1] = root .. '/' .. mangled .. '.sw?'
      else
        local root = expanded:gsub('/+$', '')
        candidates[#candidates + 1] = root .. '/.' .. vim.fn.escape(base, '[]^$\\.*') .. '.*.sw?'
      end
    end
  end

  local local_dir = vim.fn.fnamemodify(abs, ':h')
  candidates[#candidates + 1] = local_dir .. '/.' .. vim.fn.escape(base, '[]^$\\.*') .. '.*.sw?'
  return candidates
end

function G.has_swap_for(path)
  for _, patt in ipairs(swap_glob_candidates(path)) do
    if patt and patt ~= '' and vim.fn.glob(patt) ~= '' then
      return true
    end
  end
  return false
end

function G.buf_status_for(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    return { bufnr = -1, loaded = false, modified = false }
  end
  local loaded = vim.api.nvim_buf_is_loaded(bufnr)
  local modified = loaded and vim.api.nvim_buf_get_option(bufnr, 'modified') or false
  return { bufnr = bufnr, loaded = loaded, modified = modified }
end

-- nil when the file may be edited, else an error (string or swap_conflict table)
function G.check_editable(path)
  local st = G.buf_status_for(path)
  if st.loaded and st.modified then
    return 'File is open and modified in this Neovim; aborting to avoid data loss.'
  end
  if (not st.loaded) and G.has_swap_for(path) then
    return { kind = 'swap_conflict', path = path }
  end
  return nil
end

return G
