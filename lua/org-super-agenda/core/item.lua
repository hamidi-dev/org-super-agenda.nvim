-- core/item.lua
local Item = {}
Item.__index = Item
function Item.new(o)
  return setmetatable(o, Item)
end
function Item:has_tag(tag)
  for _, t in ipairs(self.tags or {}) do
    if t:lower() == (tag or ''):lower() then
      return true
    end
  end
end
function Item:is_actionable()
  local todo = { TODO = true, PROGRESS = true, WAITING = true }
  return todo[self.todo_state] or self.scheduled or self.deadline
end
return Item
