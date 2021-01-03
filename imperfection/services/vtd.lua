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
  local stream = setmetatable({gpu=set.gpu,screen=set.screen,rb=""}, {__index=_vt})
  stream:init()
  local function key_listener()
    while true do
      local sig = table.pack(coroutine.yield())
      if sig[1] == "key_down" then
        local c = string.char(sig[3] > 0 and sig[3] or sig[4])
        if sig[3] == 0 then cmd_obj.rb = cmd_obj.rb .. "\0" end
        cmd_obj.rb = cmd_obj.rb .. c
      end
    end
  end
  local pid = scheduler.create(key_listener, tostring(sets[n]) or "vtobj")
  streams[n] = stream
  return stream
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
