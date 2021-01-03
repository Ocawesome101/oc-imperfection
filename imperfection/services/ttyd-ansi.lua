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
    component.invoke(gpu, "setForeground", 0xD29A01)
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
      self.fg = colors[8]
      self.bg = colors[1]
    elseif a > 30 and a < 38 then
      self.fg = colors[a - 30]
    elseif a > 40 and a < 48 then
      self.bg = colors[a - 30]
    end
  end
end

function commands:toggle()
  --[[local ch, fg, bg = component.invoke(self.gpu, "get", self.cx, self.cy)
  component.invoke(self.gpu, "setForeground", bg)
  component.invoke(self.gpu, "setBackground", fg)
  component.invoke(self.gpu, "set", self.cx, self.cy, ch)
  component.invoke(self.gpu, "setForeground", self.fg)
  component.invoke(self.gpu, "setBackground", self.bg)]]
end

function commands:scroll()
  component.invoke(self.gpu, "copy", 1, 1, self.w, self.h, 0, -1)
  component.invoke(self.gpu, "fill", 1, self.h, self.w, 1, " ")
end

function commands:check_cursor()
  if self.cx > self.w then
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
    component.invoke(self.gpu, "set", self.cx, self.cy, ln or "")
    self.cx = self.cx + #ln
    self.wb = self.wb:sub(#ln + 1)
  end
end

local key_aliases = {
  [200] = "\27[A",
  [208] = "\27[B",
  [205] = "\27[C",
  [203] = "\27[D"
}

local function start(set)
  local gpu = set.gpu
  local screen = set.screen
  local w, h = component.invoke(gpu, "maxResolution")
  local keyboards = component.invoke(screen, "getKeyboards")
  for k, v in pairs(keyboards) do
    keyboards[v] = true
  end
  local vt_state = {
    w = w,
    h = h,
    cx = 1,
    cy = 1,
    wb = "",
    bg = 0x000000,
    fg = 0xFFFFFF,
    gpu = gpu,
    mode = 0, -- 0 regular, 1 got ESC, 2 in sequence
    screen = screen,
  }
  component.invoke(gpu, "setForeground", vt_state.fg)
  component.invoke(gpu, "setBackground", vt_state.bg)
  local nb = ""
  setmetatable(vt_state, {__index = commands})
  local stream
  local function handler()
    stream = ipc.listen()
    --log("vth: Opened stream from", stream.from)
    while true do
      local data = stream:read(1)
      if not data then break end
      if vt_state.mode == 0 then
        if data == "\27" then
          vt_state.mode = 1
        elseif data == "\n" or data == "\13" then
          vt_state:flush()
          vt_state.cx = 1
          vt_state:B({})
        elseif data == "\t" then
          vt_state.wb = vt_state.wb .. " "
        else
          vt_state.wb = vt_state.wb .. data
        end
        vt_state:flush()
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
          pcall(commands[data], vt_state, args)
          vt_state:toggle()
        end
      end
    end
  end

  local function key_handler()
    while true do
      local sig = table.pack(coroutine.yield())
      if stream and sig[1] == "key_down" then--and keyboards[sig[2]] then
        local char = string.char(sig[3])
        local code = sig[4]
        if char == "\13" then char = "\10" end
        if char == "\0" then
          if aliases[code] then
            stream:write(aliases[code])
            stream.rb = stream.rb .. aliases[code] .. "\2"
          end
        else
          stream:write(char)
          stream.rb = stream.rb .. char .. "\2"
        end
      end
    end
  end
  local pid = scheduler.create(handler, "vt:"..(tostring(set):gsub("table: ", "") or "nil"))
  scheduler.create(key_handler, "vt-kbd:"..(tostring(set):gsub("table: ", "") or "nil"))
  return pid
end

local handlers = {}
local used = {}
for i=1, #sets, 1 do
  log("ttyd: Registering", sets[i].gpu.address:sub(1,4), "+", sets[i].screen.address:sub(1,4))
  local new = start(sets[i])
  log("ttyd: Started as", new)
  handlers[#handlers + 1] = new
end

-- vt://1/ or vt://new/
local function resolver(new)
  new = tonumber(new) or new
  --log("ttyd: Got request for", new)
  if new == "new" then
    local n = 0
    repeat
      n = n + 1
    until n > #handlers or not used[n]
    used[n] = true
    if not handlers[n] then
      return nil, "no such terminal"
    end
    return ipc.open(handlers[n])
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
