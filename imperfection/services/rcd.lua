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

local svc_path = "/imperfection/services/"
log("Getting list of services from " .. svc_path)

local files = bfs.list(svc_path)
if files then
  for i=1, #files, 1 do
    local sname = files[i]:gsub("%.lua$", "")
    if not running[sname] then
      running[sname] = true
      log("Starting service:", sname)
      ldsvc(sname)
    end
  end
end

log("Done")

while true do
  -- log(coroutine.yield())
  coroutine.yield()
end
