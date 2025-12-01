-- config/config.lua
local M = {}

M.defaults = {
  org_files           = {},
  org_directories     = {},
  exclude_files       = {},
  exclude_directories = {},
  keymaps             = {
    filter_reset      = 'oa',
    filter            = 'of',
    filter_fuzzy      = 'oz',
    filter_query      = 'oq',
    undo              = 'u',
    toggle_other      = 'oo',
    reschedule        = 'cs',
    set_deadline      = 'cd',
    priority_up       = '+',
    priority_down     = '-',
    priority_clear    = '0',
    priority_A        = 'A',
    priority_B        = 'B',
    priority_C        = 'C',
    cycle_todo        = 't',
    reload            = 'r',
    refile            = 'R',
    hide_item         = 'x',
    preview           = 'K',
    reset_hidden      = 'X',
    toggle_duplicates = 'D',
    cycle_view        = 'ov',
  },

  todo_states         = {
    { name = 'TODO',     keymap = 'ot', color = '#FF5555', strike_through = false, fields = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' } },
    { name = 'PROGRESS', keymap = 'op', color = '#FFAA00', strike_through = false, fields = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' } },
    { name = 'WAITING',  keymap = 'ow', color = '#BD93F9', strike_through = false, fields = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' } },
    { name = 'DONE',     keymap = 'od', color = '#50FA7B', strike_through = true,  fields = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' } },
  },

  -- You can add per-group { sort = { by='deadline'|'scheduled'|'priority'|'todo'|'filename'|'headline'|'date_nearest', order='asc'|'desc' } }
  groups              = {
    {
      name = "📅 Today",
      matcher = function(i) return i.scheduled and i.scheduled:is_today() end,
      sort = { by = 'priority', order = 'desc' }
    },
    {
      name = "🗓️ Tomorrow",
      matcher = function(i) return i.scheduled and i.scheduled:days_from_today() == 1 end
    },
    {
      name = "☠️ Deadlines",
      matcher = function(i) return i.deadline and i.todo_state ~= 'DONE' and not i:has_tag("personal") end,
      sort = { by = 'deadline', order = 'asc' }
    },
    {
      name = "⭐ Important",
      matcher = function(i) return i.priority == "A" and (i.deadline or i.scheduled) end,
      sort = { by = 'date_nearest', order = 'asc' }
    },
    {
      name = "⏳ Overdue",
      matcher = function(i)
        return i.todo_state ~= 'DONE' and (
          (i.deadline and i.deadline:is_past()) or
          (i.scheduled and i.scheduled:is_past())
        )
      end,
      sort = { by = 'date_nearest', order = 'asc' }
    },
    { name = "🏠 Personal", matcher = function(item) return item:has_tag("personal") end },
    { name = "💼 Work", matcher = function(item) return item:has_tag("work") end },
    {
      name = "📆 Upcoming",
      matcher = function(it)
        local days = (require('org-super-agenda.config').get().upcoming_days or 10)
        local d1 = it.deadline and it.deadline:days_from_today()
        local d2 = it.scheduled and it.scheduled:days_from_today()
        local ok1 = d1 and d1 >= 0 and d1 <= days
        local ok2 = d2 and d2 >= 0 and d2 <= days
        return ok1 or ok2
      end,
      sort = { by = 'date_nearest', order = 'asc' }
    },
  },

  window              = {
    width             = 0.8,
    height            = 0.7,
    border            = 'rounded',
    title             = 'Org Super Agenda',
    title_pos         = 'center',
    margin_left       = 0,
    margin_right      = 0,
    fullscreen_border = 'none', -- used when fullscreen=true
  },

  upcoming_days       = 10,
  hide_empty_groups   = true,
  keep_order          = false,
  allow_duplicates    = false,
  group_format        = '* %s',
  other_group_name    = 'Other',
  show_other_group    = false,
  show_tags           = true,
  show_filename       = true,
  heading_max_length  = 70,
  persist_hidden      = false,
  view_mode           = 'classic',
  classic             = { heading_order = { 'filename', 'todo', 'priority', 'headline' }, short_date_labels = false, inline_dates = true },
  compact             = { filename_min_width = 10, label_min_width = 12 },

  -- Global fallback sort for groups that don't specify their own `sort`
  group_sort          = { by = 'date_nearest', order = 'asc' },

  -- Popup mode: when enabled, 'q' detaches from tmux instead of closing the buffer
  popup_mode          = {
    enabled      = false,
    hide_command = nil, -- e.g., "tmux detach-client"
  },

  debug               = false,
}

local cfg = vim.deepcopy(M.defaults)
function M.setup(user)
  cfg = vim.tbl_deep_extend('force', cfg, user or {}); return cfg
end

function M.get() return cfg end

return M
