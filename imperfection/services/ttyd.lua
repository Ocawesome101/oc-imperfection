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
    component.invoke(gpu, "bind", screenaddr)
    component.invoke(gpu, "setForeground", 0x000000)
    component.invoke(gpu, "setBackground", 0xFFFFFF)
    screen.rb = ""
  else
    if gpu then gpu:close() end
    if screen then screen:close() end
  end
until not (gpu and screen)

log("ttyd: Starting TTYs")
-- This is a fairly basic VT100 emulator.  Only 8 colors.
-- The only implemented commands are A, B, C, D, H, J, K, and {0,30-37,40-47}m
local colors = {
  0x000000,
  0xFF0000,
  0x00FF00,
  0xFFFF00,
  0x0000FF,
  0xFF00FF,
  0x00FFFF,
  0xFFFFFF
}
local commands = {}
function commands:A(a)
  a = a[1] or 1
  self.cy = math.min(1, self.cy - a)
end
function commands:B(a)
  a = a[1] or 1
  if self.cy + 1 > self.h then
    self:scroll()
  end
  self.cy = math.max(self.h, self.cy + a)
end
function commands:C(a)
  a = a[1] or 1
  self.cx = math.max(self.w, self.cx + 1)
end
function commands:D(a)
  a = a[1] or 1
end
function commands:H(a)
  self.cx = math.max(1, math.min(self.w, a[2] or 1))
  self.cy = math.max(1, math.min(self.h, a[1] or 1))
end
function commands:J(a)
  a = a[1] or 0
  if a == 0 then
    component.invoke(self.gpu, "fill", self.cx, self.cy, self.w, 1, " ")
    component.invoke(self.gpu, "fill", 1, self.cy + 1, self.w, self.h, " ")
  elseif a == 1 then
    component.invoke(self.gpu, "fill", 1, 1, self.w, self.cy - 1, " ")
    component.invoke(self.gpu, "fill", self.cx, self.cy, self.w, 1, " ")
  elseif a == 2 then
    component.invoke(self.gpu, "fill", 1, 1, self.w, self.h, " ")
  end
end
function commands:K(a)
  a = a[1] or 0
  if a == 0 then
    component.invoke(self.gpu, "fill", self.cx, self.cy, self.w, 1, " ")
  elseif a == 1 then
    component.invoke(self.gpu, "fill", 1, self.cy, self.cx, 1, " ")
  elseif a == 2 then
    component.invoke(self.gpu, "fill", 1, self.cy, self.w, 1, " ")
  end
end
function commands:m(p)
  p[1] = p[1] or 0
  for _, a in ipairs(p) do
    if a == 0 then
      self.fg = colors[1]
      self.bg = colors[8]
    elseif a > 30 and a < 38 then
      self.fg = colors[a - 30]
    elseif a > 40 and a < 48 then
      self.bg = colors[a - 30]
    end
  end
end

function commands:toggle()
  local ch, fg, bg = component.invoke(self.gpu, "get", self.cx, self.cy)
  component.invoke(self.gpu, "setForeground", bg)
  component.invoke(self.gpu, "setBackground", fg)
  component.invoke(self.gpu, "set", self.cx, self.cy, ch)
  component.invoke(self.gpu, "setForeground", self.fg)
  component.invoke(self.gpu, "setBackground", self.bg)
end

function commands:scroll()
  component.invoke(self.gpu, "copy", 1, 1, self.w, self.h, 0, -1)
  component.invoke(self.gpu, "fill", 1, self.h, self.w, 1, " ")
end

function commands:check_cursor()
  if self.cx > w then
    self.cx, self.cy = 1, self.cy + 1
  end
  if self.cy >= self.h then
    self.cy = self.h
    self:scroll()
  end
  self.cx = math.max(1, math.min(self.w, self.cx))
  self.cy = math.max(1, math.min(self.h, self.cy))
end

function commands:flush()
  while #self.wb > 0 do
    self:check_cursor()
    local ln = self.wb:sub(1, self.w - self.cx + 1)
    component.invoke(self.gpu, "set", self.cx, self.cy, ln)
    self.cx = self.cx + #ln
  end
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
    wb = "",
    fg = 0x000000,
    bg = 0xFFFFFF,
    gpu = gpu,
    mode = 0, -- 0 regular, 1 got ESC, 2 in sequence
    screen = screen,
  }
  local nb = ""
  setmetatable(vt_state, {__index = commands})
  local function handler()
    local stream = ipc.listen()
    while true do
      local data = stream:read(1)
      if not data then break end
      self:toggle()
      if vt_state.mode == 0 then
        if data == "\27" then
          vt_state:toggle()
          vt_state:flush()
          vt_state:toggle()
          vt_state.mode = 1
        elseif data == "\n" then
          vt_state:toggle()
          vt_state:flush()
          vt_state:toggle()
          vt_state.cx = 1
          vt_state:B({})
        elseif data == "\t" then
          vt_state.wb = vt_state.wb .. " "
        else
          vt_state.wb = vt_state.wb .. data
        end
      elseif vt_state.mode == 1 then
        if data == "[" then
          vt_state.mode = 2
        else
          vt_state.mode = 0
        end
      elseif vt_state.mode == 2 then
        if data:match("[%d;]") then
          nb = nb .. data
        elseif commands[data] then
          vt_state.mode = 0
          local args = {}
          for c in nb:gmatch("[^;]+") do
            args[#args + 1] = tonumber(c) or 0
          end
          nb = ""
          vt_state:toggle()
          pcall(commands[data], args)
          vt_state:toggle()
        end
      end
    end
  end
  local pid = scheduler.create(handler, "vt:"..(tostring(set):gsub("table: ", "") or "nil"))
  return pid
end

local handlers = {}
local used = {}
for i=1, #sets, 1 do
  log("ttyd: Registering", sets[i].gpu.address:sub(1,4), "+", sets[i].screen.address:sub(1,4))
  local new = start(sets[i])
  handlers[#handlers + 1] = new
end

log("ttyd: Done")

-- vt://1/ or vt://new/
local function resolver(new)
  new = tonumber(new) or new
  if new == "new" then
    local n = 0
    repeat
      n = n + 1
    until n > #handlers or not used[n]
    used[n] = true
    return handlers[n], "no such terminal"
  elseif type(new) == "number" and handlers[new] then
    used[new] = true
    return ipc.open(handlers[new])
  else
    return nil, "no such terminal"
  end
end

log("ttyd: Registering with URLD")
urld.register("vt", resolver)

while true do
  coroutine.yield()
end
