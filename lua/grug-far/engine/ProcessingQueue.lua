local M = {}

M.__index = M

--- a processing queue processes each item pushed to it in sequence
--- until there are none. If more items are pushed it automatically starts
--- procesing again
---@param processCallback fun(item: any, on_done: fun())
function M.new(processCallback)
  local self = setmetatable({}, M)
  self.queue = {}
  self.processCallback = processCallback
  return self
end

function M:_processNext()
  local item = self.queue[1]
  self.processCallback(item, function()
    table.remove(self.queue, 1)
    if #self.queue > 0 then
      self:_processNext()
    end
  end)
end

--- adds item to be processed to the queue
--- automatically processes as necessary
---@param item any
function M:push(item)
  table.insert(self.queue, item)
  if #self.queue == 1 then
    self:_processNext()
  end
end

return M