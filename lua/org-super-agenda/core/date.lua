-- core/date.lua
local Date = {}
Date.__index = Date

function Date.new(y, m, d, active, hour, min, date_only, timestamp_end)
  return setmetatable({
    year=y,
    month=m,
    day=d,
    active=(active~=false),
    hour=hour,
    min=min,
    date_only=date_only,
    timestamp_end=timestamp_end
  }, Date)
end
function Date.parse(str)
  local y,m,d = tostring(str):match('(%d%d%d%d)-(%d%d)-(%d%d)')
  return y and Date.new(tonumber(y), tonumber(m), tonumber(d), true) or nil
end
function Date.from_orgdate(orgdate)
  if not orgdate then return nil end
  local is_active = orgdate.active ~= false
  return Date.new(
    orgdate.year,
    orgdate.month,
    orgdate.day,
    is_active,
    orgdate.hour,
    orgdate.min,
    orgdate.date_only,
    orgdate.timestamp_end
  )
end
function Date:is_today()
  local t = os.date('*t'); return self.year==t.year and self.month==t.month and self.day==t.day
end
function Date:to_time() 
  return os.time{ 
    year=self.year, 
    month=self.month, 
    day=self.day, 
    hour=self.hour or 0, 
    min=self.min or 0 
  } 
end
function Date:is_past()
  local t = os.date('*t')
  local today = os.time{ year=t.year, month=t.month, day=t.day, hour=0 }
  local self_day = os.time{ year=self.year, month=self.month, day=self.day, hour=0 }
  return self_day < today
end
function Date:days_from_today()
  local t = os.date('*t')
  local today = os.time{ year=t.year, month=t.month, day=t.day, hour=0 }
  local self_day = os.time{ year=self.year, month=self.month, day=self.day, hour=0 }
  return math.floor((self_day - today) / 86400)
end
function Date:__tostring()
  local date_str = string.format('%04d-%02d-%02d', self.year, self.month, self.day)
  if not self.date_only and self.hour and self.min then
    date_str = date_str .. string.format(' %02d:%02d', self.hour, self.min)
    if self.timestamp_end then
      local end_time = os.date('*t', self.timestamp_end)
      date_str = date_str .. string.format('-%02d:%02d', end_time.hour, end_time.min)
    end
  end
  return date_str
end
return Date

