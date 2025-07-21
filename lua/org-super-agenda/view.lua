-- org-super-agenda – floating agenda view ------------------------------------
local get_cfg  = require('org-super-agenda.config').get
local utils    = require('org-super-agenda.utils')
local V        = {}
local hi_done  = false
local state_hl = {} -- name → { group = 'HL', fields = { headline=true … } }

-------------------------------------------------------------------------------
-- Highlight groups (config‑driven) -------------------------------------------
-------------------------------------------------------------------------------
local function hi()
  if hi_done then return end
  vim.cmd('highlight default OrgSA_Group gui=bold')

  for _, st in ipairs(get_cfg().todo_states or {}) do
    -- extract HL group & field‑set (supports both legacy + new keys)
    local hl_group, fields =
        (type(st.highlight) == 'string' and st.highlight) or st.hl_group,
        (type(st.highlight) == 'table' and st.highlight) or st.fields or {}
    if #fields == 0 then fields = { 'todo', 'headline' } end
    hl_group = hl_group or ('OrgSA_' .. st.name)

    -- define highlight
    local gui = st.strike_through and 'gui=bold,strikethrough' or 'gui=bold'
    if st.color then
      vim.cmd(string.format('highlight default %s guifg=%s %s', hl_group, st.color, gui))
    else
      vim.cmd(string.format('highlight default %s %s', hl_group, gui))
    end

    -- store config
    local set = {}
    for _, f in ipairs(fields) do set[f] = true end
    state_hl[st.name] = { group = hl_group, fields = set }
  end
  hi_done = true
end

local function want(state, field)
  local cfg = state_hl[state or ''] or {}
  return cfg.fields and cfg.fields[field]
end

local function add(t, s)
  table.insert(t, s); return #t
end

-------------------------------------------------------------------------------
-- Render ---------------------------------------------------------------------
-------------------------------------------------------------------------------
function V.render(groups, initial_cursor_pos)
  hi()
  local cfg       = get_cfg()
  local ui        = vim.api.nvim_list_uis()[1]
  local left      = cfg.window.margin_left or 0
  local right     = cfg.window.margin_right or 0
  local win_width = math.floor(ui.width * cfg.window.width) - left - right

  local buf       = vim.api.nvim_create_buf(false, true)
  local rows      = {}
  local hls       = {} -- {ln, c1, c2, group}
  local line_map  = {}

  ---------------------------------------------------------------------------
  -- Pass 1: longest prefix (indent + tokens) → meta alignment -------------
  ---------------------------------------------------------------------------
  local function prefix(it)
    local indent = string.rep(' ', it.level)
    local pri    = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
    local parts  = {
      filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
      todo     = it.todo_state,
      priority = pri,
      headline = utils.truncate(it.headline, cfg.heading_max_length),
    }
    local order  = vim.deepcopy(cfg.heading_order or { 'filename', 'todo', 'priority', 'headline' })
    local tok    = {}

    if parts.filename and order[1] == 'filename' then
      table.insert(tok, '[' .. parts.filename .. ']')
      table.remove(order, 1)
    end
    for _, k in ipairs(order) do
      if parts[k] and parts[k] ~= '' then table.insert(tok, parts[k]) end
    end
    return indent .. table.concat(tok, ' ')
  end

  local widest = 0
  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      local pre = prefix(it)
      if #pre > widest then widest = #pre end
    end
  end
  widest = widest + 1 -- at least one gap before meta

  ---------------------------------------------------------------------------
  -- Pass 2: build lines & highlights ---------------------------------------
  ---------------------------------------------------------------------------
  local ln = 0
  local function emit(s)
    add(rows, s); ln = ln + 1; return ln
  end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdr = emit(string.format(cfg.group_format or '* %s', grp.name))
      table.insert(hls, { hdr - 1, 0, -1, 'OrgSA_Group' })

      for _, it in ipairs(grp.items) do
        local indent      = string.rep(' ', it.level)
        local pri         = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil

        local sched_label = cfg.short_date_labels and 'S' or 'SCHEDULED'
        local dead_label  = cfg.short_date_labels and 'D' or 'DEADLINE'
        local meta        = {}
        if it.scheduled then table.insert(meta, sched_label .. ': <' .. tostring(it.scheduled) .. '>') end
        if it.deadline then table.insert(meta, dead_label .. ':  <' .. tostring(it.deadline) .. '>') end
        local meta_str = table.concat(meta, ' ')

        -------------------------------------------------------------------
        -- assemble prefix + remember spans for selective HL -------------
        -------------------------------------------------------------------
        local parts    = {
          filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
          todo     = it.todo_state,
          priority = pri,
          headline = utils.truncate(it.headline, cfg.heading_max_length),
        }
        local order    = vim.deepcopy(cfg.heading_order or { 'filename', 'todo', 'priority', 'headline' })

        local col      = #indent
        local spans    = {}
        local text     = indent

        local function push(field, txt)
          if not txt or txt == '' then return end
          if #text > 0 and text:sub(-1) ~= ' ' then
            text = text .. ' '; col = col + 1
          end
          local s = col
          text    = text .. txt
          col     = col + #txt
          table.insert(spans, { field = field, s = s, e = col })
        end

        if parts.filename and order[1] == 'filename' then
          push('filename', '[' .. parts.filename .. ']')
          table.remove(order, 1)
        end
        for _, k in ipairs(order) do push(k, parts[k]) end

        -- meta (aligned)
        if cfg.inline_dates and meta_str ~= '' then
          if #text < widest then
            text = text .. string.rep(' ', widest - #text)
            col  = widest
          else
            text = text .. ' '; col = col + 1
          end
          local ms = col
          text = text .. meta_str
          table.insert(spans, { field = 'date', s = ms, e = ms + #meta_str })
          col = col + #meta_str
        end

        -- tags (right‑aligned, optional)
        if cfg.show_tags and it.tags and #it.tags > 0 then
          local tag   = ':' .. table.concat(it.tags, ':') .. ':'
          local start = win_width - #tag - 1
          if #text + 1 < start then
            text = text .. string.rep(' ', start - #text) .. tag
          else
            text = text .. ' ' .. tag
          end
          table.insert(spans, { field = 'tags', s = #text - #tag, e = #text })
        end

        local line_no = emit(text)
        line_map[line_no] = it

        -- highlight selected fields --------------------------------------
        local hl_cfg = state_hl[it.todo_state] or { group = 'OrgSA_' .. (it.todo_state or 'TODO'), fields = {} }
        for _, seg in ipairs(spans) do
          if hl_cfg.fields[seg.field] then
            table.insert(hls, { line_no - 1, left + seg.s, left + seg.e, hl_cfg.group })
          end
        end

        -- inline_dates == false → own meta line
        if not cfg.inline_dates and meta_str ~= '' then
          local meta_ln = emit(indent .. '  ' .. meta_str)
          if want(it.todo_state, 'date') then
            table.insert(hls, { meta_ln - 1, left + #indent + 2, -1, hl_cfg.group })
          end
        end
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Write buffer + HL -------------------------------------------------------
  ---------------------------------------------------------------------------
  local padded = {}
  for _, l in ipairs(rows) do
    table.insert(padded, string.rep(' ', left) .. l .. string.rep(' ', right))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(buf, 0, hl[4], hl[1], hl[2], hl[3])
  end
  vim.api.nvim_buf_set_name(buf, 'Org Super Agenda')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'org')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  ---------------------------------------------------------------------------
  -- Floating window ---------------------------------------------------------
  ---------------------------------------------------------------------------
  local h   = math.floor(ui.height * cfg.window.height)
  local w   = win_width + left + right
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    style     = 'minimal',
    col       = math.floor((ui.width - w) / 2),
    row       = math.floor((ui.height - h) / 2),
    width     = w,
    height    = h,
    border    = cfg.window.border,
    title     = cfg.window.title,
    title_pos = cfg.window.title_pos,
  })
  vim.api.nvim_win_set_option(win, 'wrap', false)

  ---------------------------------------------------------------------------
  -- Keymaps / Navigation ----------------------------------------------------
  ---------------------------------------------------------------------------
  local function wipe()
    local b = vim.api.nvim_get_current_buf()
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end

  local function jump()
    local cur  = vim.api.nvim_win_get_cursor(0)
    local item = line_map[cur[1]]
    if not (item and item._src_line) then return end
    local agendab = vim.api.nvim_get_current_buf()

    vim.cmd('edit ' .. vim.fn.fnameescape(item.file))
    vim.api.nvim_win_set_cursor(0, { item._src_line, 0 })

    local filebuf = vim.api.nvim_get_current_buf()
    pcall(vim.api.nvim_buf_delete, agendab, { force = true })

    vim.api.nvim_create_autocmd('BufWinLeave', {
      buffer = filebuf,
      once = true,
      callback = function()
        vim.schedule(function()
          pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
          require('org-super-agenda').open(cur)
        end)
      end,
    })
    for _, k in ipairs({ 'q', '<Esc>' }) do
      vim.keymap.set('n', k, wipe, { buffer = filebuf, silent = true })
    end
  end

  -------------------------------------------------------------------------
  -- 🔄  Change SCHEDULED date in place (opens org‑mode datepicker)
  local function reschedule()
    local cur  = vim.api.nvim_win_get_cursor(0)
    local item = line_map[cur[1]]
    if not (item and item.file and item._src_line) then
      vim.notify('Kein Eintrag unter dem Cursor', vim.log.levels.WARN)
      return
    end

    local agenda_buf = vim.api.nvim_get_current_buf()

    local ok, api_root = pcall(require, 'orgmode.api')
    if not ok then return end
    local org_api = api_root.load and api_root or api_root.org
    local file    = org_api.load(item.file) -- liefert File oder {File}
    if vim.islist(file) then file = file[1] end
    if not (file and file.get_headline_on_line) then return end

    local hl = file:get_headline_on_line(item._src_line)
    if not hl then return end

    hl:set_scheduled()
        :next(function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(agenda_buf) then
              pcall(vim.api.nvim_buf_delete, agenda_buf, { force = true })
            end
            require('org-super-agenda').open(cur) -- Cursor bleibt grob gleich
          end)
        end)
  end

  local km = get_cfg().keymaps.reschedule
  vim.keymap.set('n', km, reschedule, { buffer = buf, silent = true })

  -- Change DEADLINE date in place (opens org‑mode datepicker)
  local function set_deadline()
    local cur  = vim.api.nvim_win_get_cursor(0)
    local item = line_map[cur[1]]
    if not (item and item.file and item._src_line) then
      vim.notify('Kein Eintrag unter dem Cursor', vim.log.levels.WARN)
      return
    end

    local agenda_buf = vim.api.nvim_get_current_buf()

    local ok, api_root = pcall(require, 'orgmode.api')
    if not ok then return end
    local org_api = api_root.load and api_root or api_root.org
    local file    = org_api.load(item.file)
    if vim.islist(file) then file = file[1] end
    if not (file and file.get_headline_on_line) then return end

    local hl = file:get_headline_on_line(item._src_line)
    if not hl then return end

    hl:set_deadline()
        :next(function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(agenda_buf) then
              pcall(vim.api.nvim_buf_delete, agenda_buf, { force = true })
            end
            require('org-super-agenda').open(cur)
          end)
        end)
  end

  local dk = get_cfg().keymaps.set_deadline
  vim.keymap.set('n', dk, set_deadline, { buffer = buf, silent = true })


  vim.keymap.set('n', '<CR>', jump, { buffer = buf, silent = true })
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, wipe, { buffer = buf, silent = true })
  end

  -- quick filters ---------------------------------------------------------
  for _, st in ipairs(get_cfg().todo_states or {}) do
    local km = st.keymap
    if km and type(km) == 'string' and st.name then
      vim.keymap.set('n', km, function()
        wipe()
        require('org-super-agenda').open(nil, { todo_filter = st.name })
      end, { buffer = buf, silent = true })
    end
  end

  local reset = get_cfg().keymaps.filter_reset
  if reset and type(reset) == 'string' then
    vim.keymap.set('n', reset, function()
      wipe()
      require('org-super-agenda').open(nil)
    end, { buffer = buf, silent = true })
  end

  -- restore agenda cursor
  if initial_cursor_pos then
    vim.schedule(function()
      pcall(vim.api.nvim_win_set_cursor, win, initial_cursor_pos)
    end)
  end
end

return V
