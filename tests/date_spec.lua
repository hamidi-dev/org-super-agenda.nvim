local Date = require('org-super-agenda.core.date')

describe('Date helpers', function()
  it('detects today', function()
    local t = os.date('*t')
    local d = Date.new(t.year, t.month, t.day)
    assert.is_true(d:is_today())
  end)

  it('stringifies correctly', function()
    local d = Date.new(2025, 07, 23)
    assert.equals('2025-07-23', tostring(d))
  end)

  it('past vs. future', function()
    local past  = Date.parse('2000-01-01')
    local future = Date.parse('2999-12-31')
    assert.is_true(past:is_past())
    assert.is_false(future:is_past())
  end)

  describe('PR #4: active/inactive dates', function()
    it('defaults active to true when not specified', function()
      local d = Date.new(2026, 1, 30)
      assert.is_true(d.active)
    end)

    it('accepts active=true', function()
      local d = Date.new(2026, 1, 30, true)
      assert.is_true(d.active)
    end)

    it('accepts active=false', function()
      local d = Date.new(2026, 1, 30, false)
      assert.is_false(d.active)
    end)

    it('Date.parse() creates active dates', function()
      local d = Date.parse('2026-01-30')
      assert.is_true(d.active)
    end)

    it('Date.from_orgdate() reads active field', function()
      local orgdate_active = { year = 2026, month = 1, day = 30, active = true }
      local d1 = Date.from_orgdate(orgdate_active)
      assert.is_true(d1.active)

      local orgdate_inactive = { year = 2026, month = 1, day = 30, active = false }
      local d2 = Date.from_orgdate(orgdate_inactive)
      assert.is_false(d2.active)
    end)

    it('Date.from_orgdate() defaults to true if active missing', function()
      local orgdate_no_active = { year = 2026, month = 1, day = 30 }
      local d = Date.from_orgdate(orgdate_no_active)
      assert.is_true(d.active)
    end)
  end)

  describe('Issue #7: time support', function()
    it('stores time fields', function()
      local d = Date.new(2026, 1, 30, true, 9, 30)
      assert.equals(9, d.hour)
      assert.equals(30, d.min)
    end)

    it('formats date without time when date_only', function()
      local d = Date.new(2026, 1, 30, true, 0, 0, true)
      assert.equals('2026-01-30', tostring(d))
    end)

    it('formats date with time when not date_only', function()
      local d = Date.new(2026, 1, 30, true, 9, 30, false)
      assert.equals('2026-01-30 09:30', tostring(d))
    end)

    it('formats time range when timestamp_end present', function()
      local start_ts = os.time({ year=2026, month=1, day=30, hour=14, min=30 })
      local end_ts = os.time({ year=2026, month=1, day=30, hour=15, min=30 })
      local d = Date.new(2026, 1, 30, true, 14, 30, false, end_ts)
      assert.equals('2026-01-30 14:30-15:30', tostring(d))
    end)

    it('Date.from_orgdate() captures time fields', function()
      local orgdate = {
        year = 2026, month = 1, day = 30,
        hour = 14, min = 30,
        active = true,
        date_only = false
      }
      local d = Date.from_orgdate(orgdate)
      assert.equals(14, d.hour)
      assert.equals(30, d.min)
      assert.is_false(d.date_only)
      assert.equals('2026-01-30 14:30', tostring(d))
    end)

    it('to_time() includes hour and minute', function()
      local d = Date.new(2026, 1, 30, true, 9, 30)
      local expected = os.time({ year=2026, month=1, day=30, hour=9, min=30 })
      assert.equals(expected, d:to_time())
    end)

    it('to_time() defaults to midnight when no time', function()
      local d = Date.new(2026, 1, 30)
      local expected = os.time({ year=2026, month=1, day=30, hour=0, min=0 })
      assert.equals(expected, d:to_time())
    end)

    it('is_past() compares dates only, ignoring time', function()
      local now = os.date('*t')
      local today_morning = Date.new(now.year, now.month, now.day, true, 8, 0, false)
      local today_evening = Date.new(now.year, now.month, now.day, true, 20, 0, false)
      assert.is_false(today_morning:is_past(), 'today with time should not be past')
      assert.is_false(today_evening:is_past(), 'today with time should not be past')
    end)

    it('days_from_today() compares dates only, ignoring time', function()
      local now = os.date('*t')
      local today_morning = Date.new(now.year, now.month, now.day, true, 8, 0, false)
      local today_evening = Date.new(now.year, now.month, now.day, true, 20, 0, false)
      assert.equals(0, today_morning:days_from_today())
      assert.equals(0, today_evening:days_from_today())
    end)
  end)
end)

