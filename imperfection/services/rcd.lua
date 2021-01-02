-- rcd: more or less an init system --

local log, advance, gpu, ldsvc, bfs = ...

log("SETPREF", "[rcd]")

gpu.setForeground(0x004400)
log("Welcome to Imperfection!")
gpu.setForeground(0x000000)

local running = {
  rcd = true,
  urld = true,
  ipcd = true,
  componentd = true
}

-- TODO: make this configurable?
local services = {
  "fsd",
  "ttyd",
}
for i=1, #services, 1 do
  local sname = services[i]--:gsub("%.lua$", "")
  if not running[sname] then
    running[sname] = true
    log("Starting service:", sname)
    ldsvc(sname)
  end
end

log("Done")

while true do
  --[[local sig = table.pack(coroutine.yield())
  if sig[1] == "thread_died" then
    log(table.unpack(sig, 4))
  end--]]
  --log(coroutine.yield())
  coroutine.yield()
end
