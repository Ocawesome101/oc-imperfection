-- ttyd: manage TTYs --

local log = ...

log("ttyd: Initializing")

local sets = {}

log("ttyd: Registering GPUs and screens")
repeat
  local gpu = urld.open("component://gpu/new")
  local screen = urld.open("component://screen/new")
  --log("ttyd:", gpu, screen)
  if gpu and screen then
    gpu:write("A")
    local gpuaddr = gpu:read(36)
    screen:write("A")
    local screenaddr = screen:read(36)
    log("ttyd: Registering GPU", gpuaddr)
    log("ttyd: Registering screen", screenaddr)
    gpu.address = gpuaddr
    screen.address = screenaddr
    sets[#sets + 1] = {
      gpu = gpu,
      screen = screen
    }
    gpu:write("I", "0045\"bind\"\02\""..screenaddr.."\"")
    gpu.rb = ""
    screen.rb = ""
  else
    if gpu then gpu:close() end
    if screen then screen:close() end
  end
until not (gpu and screen)

log("ttyd: Starting TTYs")
-- This is a fairly basic VT100 emulator.  Only 8 colors.
-- The only implemented commands are A, B, C, D, J, K, and {30-37,40-47}m
local colors = {}
local commands = {}
function commands:A(a)
  self.cy = math.min(1, self.cy - 1)
end
function commands:B()
end
function commands:C()
end
function commands:D()
end
function commands:J()
end
function commands:K()
end
function commands:m()
end

function commands:toggle()
  local ch, fg, bg = component.invoke(self.gpu, "get", self.cx, self.cy)
  component.invoke(self.gpu, "setForeground", bg)
  component.invoke(self.gpu, "setBackground", fg)
  component.invoke(self.gpu, "set", self.cx, self.cy, ch)
end

local function start(set)
  local gpu = set.gpu
  local screen = set.screen
  local w, h = component.invoke(gpu, "maxResolution")
  local vt_state = {
    w = w,
    h = h,
    cx = 1,
    cy = 1,
    fg = 0x000000,
    bg = 0xFFFFFF,
    gpu = gpu,
    mode = 0, -- 0 regular, 1 got ESC, 2 in sequence
    screen = screen,
  }
  setmetatable(vt_state, {__index = commands})
  local function handler(stream)
    while true do
      local data
    end
  end
end

for i=1, #sets, 1 do
  start(sets[i])
end

while true do
  coroutine.yield()
end
