-- ttyd 2: VT boogaloo --

local log = ...

log("vtd: Initializing")

local sets = {}
repeat
  local gpu = urld.open("component://gpu/new")
  local screen = urld.open("component://screen/new")
  --log("ttyd-ansi:", gpu, screen)
  if gpu and screen then
    gpu:write("A")
    local gpuaddr = gpu:read(36)
    screen:write("A")
    local screenaddr = screen:read(36)
    log("vtd: Registering GPU", gpuaddr)
    log("vtd: Registering screen", screenaddr)
    gpu.address = gpuaddr
    screen.address = screenaddr
    sets[#sets + 1] = setmetatable({
      gpu = gpu,
      screen = screen
    }, {__name = "vt"})
    component.invoke(gpu, "bind", screenaddr)
    component.invoke(gpu, "setForeground", 0xFF8100)
    screen.rb = ""
  else
    if gpu then gpu:close() end
    if screen then screen:close() end
  end
until not (screen and gpu)

local streams = {}

local _vt = {}

function _vt:B(col)
  return component.invoke(self.gpu, "setBackground", col or 0)
end
function _vt:C(x, y)
  self.cx = x
  self.cy = y
  return true
end
function _vt:F(col)
  return component.invoke(self.gpu, "setForeground", col or 0xFF8100)
end
function _vt:G(attr)
  if attr == "size" then
    return self.w, self.h
  elseif attr == "cpos" then
    return self.cx, self.cy
  elseif attr == "foreground" then
    return component.invoke(self.gpu, "getForeground")
  elseif attr == "background" then
    return component.invoke(self.gpu, "getBackground")
  else
    return nil, "no such attribute"
  end
end
function _vt:L(x, y, w, h, char)
  component.invoke(self.gpu, "fill", x, y, w, h, char)
  return true
end
function _vt:R()
  while #self.rb == 0 do
    coroutine.yield(1)
  end
  local c = self.rb:sub(1,1)
  self.rb = self.rb:sub(2)
  return c
end
function _vt:S(n)
  component.invoke(self.gpu, "copy", 1, 1, self.w, self.h, 0, -n)
  self:L(1, self.h - n + 1, self.w, n, " ")
  return true
end
function _vt:W(text)
  while #text > 0 do
    local ln = text:sub(1, self.w - self.cx + 1)
    text = text:sub(#ln + 1)
    component.invoke(self.gpu, "set", self.cx, self.cy, ln)
    self.cx = self.cx + #ln
    if self.cx >= self.w then
      self.cx = 1
      self.cy = self.cy + 1
      if self.cy >= self.h then
        self:S(1)
        self.cy = self.h - 1
      end
    end
  end
  return true
end
function _vt:init()
  local w, h = component.invoke(self.gpu, "maxResolution")
  self.w = w
  self.h = h
  self.cx = 1
  self.cy = 1
  return true
end

local function open(set, n)
  local cur = scheduler.info().id
  local cmd_obj = setmetatable({gpu=set.gpu,screen=set.screen,rb=""}, {__index=_vt})
  cmd_obj:init()
  local function handler()
    local stream = ipc.listen(cur)
    while true do
      local command = stream:read(1)
      if not command then break end
      if _vt[command] then
        local data = stream:read_formatted()
        local result = table.pack(pcall(cmd_obj[command], cmd_obj,
                                                  ipc.unpack_formatted(data)))
        if not result[1] then
          stream:write_formatted(ipc.pack_formatted(nil, result[2]))
        else
          stream:write_formatted(ipc.pack_formatted(table.unpack(result, 2, result.n)))
        end
      end
    end
  end
  local function key_listener()
    while true do
      local sig = table.pack(coroutine.yield())
      if sig[1] == "key_down" then
        local c = string.char(sig[3] > 0 and sig[3] or sig[4])
        if sig[3] == 10 or sig[3] == 8 or (sig[3] > 31 and sig[3] < 127) then
          cmd_obj.rb = cmd_obj.rb .. c
        end
      end
    end
  end
  local pid = scheduler.create(handler, tostring(sets[n]) or "vtobj")
  scheduler.create(key_listener, "vtkls")
  local new = ipc.open(pid)
  streams[n] = new
  return new
end

local function resolver(field)
  if field == "new" then
    local n = 0
    repeat
      n = n + 1
    until n > #sets or not streams[n]
    if sets[n] then
      return open(sets[n], n)
    end
    return nil, "no more available VTs"
  else
    field = tonumber(field) or 0
    return streams[field], "no such VT"
  end
end

log("vtd: Registering with URLD")
urld.register("vt", resolver)

while true do coroutine.yield() end
