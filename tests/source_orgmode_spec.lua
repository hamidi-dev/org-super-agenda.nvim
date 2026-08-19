local config = require('org-super-agenda.config')
local source = require('org-super-agenda.adapters.neovim.source_orgmode')

describe('orgmode source files', function()
  local defaults = vim.deepcopy(config.defaults)
  local original_orgmode
  local original_api
  local temp_paths = {}

  local function temp_directory()
    local directory = vim.fn.tempname()
    vim.fn.mkdir(directory, 'p')
    temp_paths[#temp_paths + 1] = directory
    return directory
  end

  local function write_org(directory, name)
    vim.fn.mkdir(directory, 'p')
    local path = directory .. '/' .. name
    vim.fn.writefile({ '* TODO Test task' }, path)
    return path
  end

  local function org_file(path)
    local internal = {
      filename = path,
      get_filetags = function()
        return {}
      end,
    }
    local file = {
      filename = path,
      _file = internal,
      headlines = {
        {
          title = 'Test task',
          level = 1,
          tags = {},
          todo_value = 'TODO',
          properties = {},
          file = { filename = path },
          position = { start_line = 1 },
          headlines = {},
        },
      },
    }
    function file:reload()
      return self
    end
    return file
  end

  before_each(function()
    original_orgmode = package.loaded['orgmode']
    original_api = package.loaded['orgmode.api']
    config.setup(vim.deepcopy(defaults))
  end)

  after_each(function()
    package.loaded['orgmode'] = original_orgmode
    package.loaded['orgmode.api'] = original_api
    for _, path in ipairs(temp_paths) do
      vim.fn.delete(path, 'rf')
    end
    temp_paths = {}
    config.setup(vim.deepcopy(defaults))
  end)

  it('uses nvim-orgmode agenda files by default', function()
    local directory = temp_directory()
    local path = write_org(directory, 'agenda.org')
    local file = org_file(path)
    local load_sync_calls = 0

    package.loaded['orgmode'] = {
      files = {
        load_sync = function()
          load_sync_calls = load_sync_calls + 1
        end,
      },
    }
    package.loaded['orgmode.api'] = {
      load = function(requested)
        assert.is_nil(requested)
        return { file }
      end,
    }

    local items = source.collect()

    assert.equals(1, load_sync_calls)
    assert.equals(1, #items)
    assert.equals(path, items[1].file)
  end)

  it('keeps org_files as an explicit compatibility override', function()
    local directory = temp_directory()
    local path = write_org(directory, 'explicit.org')
    local file = org_file(path)
    local requested_paths = {}

    config.setup({ org_files = { path } })
    package.loaded['orgmode'] = {
      files = {
        load_sync = function()
          error('agenda files should not load when an override is configured')
        end,
      },
    }
    package.loaded['orgmode.api'] = {
      load = function(requested)
        requested_paths[#requested_paths + 1] = requested
        return file
      end,
    }

    local items = source.collect()

    assert.same({ vim.fn.resolve(path) }, requested_paths)
    assert.equals(1, #items)
  end)

  it('keeps recursive org_directories compatibility overrides', function()
    local directory = temp_directory()
    local path = write_org(directory .. '/nested', 'nested.org')
    local file = org_file(path)

    config.setup({ org_directories = { directory } })
    package.loaded['orgmode'] = { files = { load_sync = function() end } }
    package.loaded['orgmode.api'] = {
      load = function(requested)
        assert.equals(vim.fn.resolve(path), requested)
        return file
      end,
    }

    local items = source.collect()

    assert.equals(1, #items)
    assert.equals(path, items[1].file)
  end)

  it('normalizes exclusions and respects directory boundaries', function()
    local directory = temp_directory()
    local excluded_path = write_org(directory .. '/work', 'private.org')
    local included_path = write_org(directory .. '/workshop', 'public.org')
    local files = {
      org_file(excluded_path),
      org_file(included_path),
    }

    config.setup({ exclude_directories = { directory .. '/work/' } })
    package.loaded['orgmode'] = { files = { load_sync = function() end } }
    package.loaded['orgmode.api'] = {
      load = function()
        return files
      end,
    }

    local items = source.collect()

    assert.equals(1, #items)
    assert.equals(included_path, items[1].file)
  end)

  it('matches relative exclude_files against normalized filenames', function()
    local directory = vim.fn.getcwd() .. '/tests/.tmp-source-' .. vim.fn.getpid()
    vim.fn.mkdir(directory, 'p')
    temp_paths[#temp_paths + 1] = directory
    local path = write_org(directory, 'relative.org')
    local relative_path = vim.fn.fnamemodify(path, ':.')

    config.setup({ exclude_files = { relative_path } })
    package.loaded['orgmode'] = { files = { load_sync = function() end } }
    package.loaded['orgmode.api'] = {
      load = function()
        return { org_file(path) }
      end,
    }

    local items = source.collect()

    assert.equals(0, #items)
  end)

  it('matches symlinked exclusions against resolved filenames', function()
    local directory = temp_directory()
    local path = write_org(directory, 'real.org')
    local link = directory .. '/linked.org'
    local uv = vim.uv or vim.loop
    assert.is_true(uv.fs_symlink(path, link))

    config.setup({ exclude_files = { link } })
    package.loaded['orgmode'] = { files = { load_sync = function() end } }
    package.loaded['orgmode.api'] = {
      load = function()
        return { org_file(path) }
      end,
    }

    local items = source.collect()

    assert.equals(0, #items)
  end)

  it('supports the older nested orgmode api shape', function()
    local directory = temp_directory()
    local path = write_org(directory, 'legacy-api.org')
    local file = org_file(path)

    config.setup({ org_files = { path } })
    package.loaded['orgmode'] = {}
    package.loaded['orgmode.api'] = {
      org = {
        load = function(requested)
          assert.equals(vim.fn.resolve(path), requested)
          return file
        end,
      },
    }

    local items = source.collect()

    assert.equals(1, #items)
  end)
end)
