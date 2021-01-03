-- Imperfection: the OpenComputers microkernel of your nightmares --

do
  local old_err = error
  function _G.error(err, lvl)
    err = tostring(err)
    old_err("Imperfection has crashed because it is imperfect.\nHere's the error anyway:\n"..err, lvl)
  end
  function _G.assert(yes, no)
    if not yes then
      error(no)
    end
    return yes
  end
end

computer.setArchitecture("Lua 5.3")

load([[
-- message displayed at the top of the screen
local msg = "Starting Imperfection"

do
  local function advance()end
  local bgpu
  do
    local gpu, screen = component.list("gpu", true)(), component.list("screen", true)()
    if gpu and screen then
      gpu = component.proxy(gpu)
      bgpu = gpu
      gpu.bind(screen)
      local w, h = gpu.maxResolution()
      gpu.setForeground(0xD29A01)
      gpu.setBackground(0x000000)
      gpu.setResolution(w, h)
      gpu.fill(1, 1, w, h, " ")
      gpu.set(1, 1, msg.."...\\")
      local stages = {"\\","|","/","-"}
      local n = 1
      local time = computer.uptime()
      advance = function()
        if computer.uptime() - time > 0.1 then
          time = computer.uptime()
          n=n+1
          if n>4 then n=1 end
          gpu.set(#msg+4, 1, stages[n])
        end
      end
    end
  end
  local fs = component.proxy(computer.getBootAddress())
  local handle = assert(fs.open("/imperfection/kernel.lua"), "failed opening /imperfection/kernel.lua")
  local data = ""
  repeat
    local chunk = fs.read(handle, math.huge)
    data = data .. (chunk or "")
    advance()
  until not chunk
  fs.close(handle)
  local call = assert(load(data, "=imperfect", "bt", _G))
  call(bgpu, advance, fs)
  --assert(xpcall(call, debug.traceback, bgpu, advance, fs))
end

while true do computer.pullSignal() end]], "=init.lua")()
