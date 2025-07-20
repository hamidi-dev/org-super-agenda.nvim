local M = {}

M.defaults = {
  ---------------------------------------------------------------------------
  -- where to look for org files
  org_files           = {}, -- explicit file paths
  org_directories     = {}, -- recurse for *.org
  todo_keywords       = { 'TODO', 'PROGRESS', 'WAITING', 'DONE' },

  ---------------------------------------------------------------------------
  todo_states         = {
    {
      name           = 'TODO',
      color          = '#FF5555',
      strike_through = false,
      fields         = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' },
    },
    {
      name           = 'PROGRESS',
      color          = '#FFAA00',
      strike_through = false,
      fields         = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' },
    },
    {
      name           = 'WAITING',
      color          = '#BD93F9',
      strike_through = false,
      fields         = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' },
    },
    {
      name           = 'DONE',
      color          = '#50FA7B',
      strike_through = true,
      fields         = { 'filename', 'todo', 'headline', 'priority', 'date', 'tags' },
    },
  },

  ---------------------------------------------------------------------------
  -- NOTE: group specification. Order matters!. First matcher wins!
  groups              = {
    { name = "📅 Today",       matcher = function(i) return i.scheduled and i.scheduled:is_today() end },
    { name = "🗓️ Tomorrow", matcher = function(i) return i.scheduled and i.scheduled:days_from_today() == 1 end, },
    -- { name = "⏰ Deadlines", matcher = function(i) return i.deadline ~= nil end },
    {
      name = "⏰ Deadlines",
      matcher = function(i)
        return i.deadline ~= nil and i.todo_state ~= 'DONE' and
            not i:has_tag("personal")
      end,
    },
    {
      name = "⭐ Important",
      matcher = function(i)
        return i.priority == "A" and
            (i.deadline ~= nil or i.scheduled ~= nil)
      end
    },
    {
      name = '⏳ Overdue',
      matcher = function(it)
        return it.todo_state ~= 'DONE' and (
          (it.deadline and it.deadline:is_past()) or
          (it.scheduled and it.scheduled:is_past())
        )
      end
    },
    { name = "🏠 Personal", matcher = function(item) return item:has_tag("personal") end },
    { name = "💼 Work",     matcher = function(item) return item:has_tag("work") end },
    {
      name = "📆 Upcoming",
      matcher = function(it)
        local days = require('org-super-agenda.config').get().upcoming_days or 10
        local deadline_ok = it.deadline and it.deadline:days_from_today() >= 0 and
            it.deadline:days_from_today() <= days
        local sched_ok = it.scheduled and it.scheduled:days_from_today() >= 0 and
            it.scheduled:days_from_today() <= days
        return deadline_ok or sched_ok
      end
    },
  },

  ---------------------------------------------------------------------------
  -- floating‑window style
  window              = {
    width        = 0.8,
    height       = 0.7,
    border       = 'rounded',
    title        = 'Org Super Agenda',
    title_pos    = 'center',
    margin_left  = 0, -- increasing this breaks stuff for now, so use with care
    margin_right = 0, -- increasing this is fine
  },

  ---------------------------------------------------------------------------
  -- misc
  upcoming_days       = 10,
  hide_empty_groups   = false,   -- set true to drop blank sections
  keep_order          = false,   -- keep original org‑agenda sort
  allow_unsafe_groups = true,    -- for :pred / :auto-map later
  group_format        = '* %s',  -- header text for groups
  other_group_name    = 'Other', -- title for catchall group
  show_other_group    = false,   -- disable to remove catchall group
  show_tags           = true,    -- display headline tags aligned right
  inline_dates        = true,    -- show SCHEDULED/DEADLINE info before TODO
  show_filename       = true,    -- append the source file name to headings
  heading_order       = { 'filename', 'todo', 'headline', 'priority', 'date' },
}

local cfg = vim.deepcopy(M.defaults)

function M.setup(user_opts)
  cfg = vim.tbl_deep_extend('force', cfg, user_opts or {})
  return cfg
end

function M.get() return cfg end

return M
