local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = table.concat({
  root .. '/lua/?.lua',
  root .. '/lua/?/init.lua',
  package.path,
}, ';')

-- --- orgmode‑Stubs ----------------------------------------------------
package.preload['orgmode'] = function()
  return { reload = function() end }
end
package.preload['orgmode.api'] = function()
  local function load(_)
    return {}
  end
  return { load = load, org = { load = load } }
end

require('org-super-agenda').setup({
  org_files = {},
  org_directories = {},
})

if vim.islist == nil then
  vim.islist = vim.tbl_islist
end
