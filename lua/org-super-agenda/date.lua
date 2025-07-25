local Date = {}   -- lightweight, Y‑M‑D only
Date.__index = Date

function Date.new(y, m, d) return setmetatable({year=y, month=m, day=d}, Date) end

function Date.parse(str)                         -- "2025-07-20"
  local y,m,d = tostring(str):match('(%d%d%d%d)-(%d%d)-(%d%d)')
  return y and Date.new(tonumber(y), tonumber(m), tonumber(d)) or nil
end

function Date.from_orgdate(orgdate)              -- convert OrgDate object
  return orgdate and Date.new(orgdate.year, orgdate.month, orgdate.day) or nil
end

function Date:is_today()
  local t = os.date('*t')
  return self.year==t.year and self.month==t.month and self.day==t.day
end

function Date:to_time()
  return os.time{ year=self.year, month=self.month, day=self.day, hour=0 }
end

function Date:is_past()
  local t = os.date('*t')
  local today = os.time{ year=t.year, month=t.month, day=t.day, hour=0 }
  return self:to_time() < today
end

function Date:days_from_today()
  local t = os.date('*t')
  local today = os.time{ year=t.year, month=t.month, day=t.day, hour=0 }
  return math.floor((self:to_time() - today) / 86400)
end

function Date:__tostring() return string.format('%04d-%02d-%02d', self.year, self.month, self.day) end

return Date

