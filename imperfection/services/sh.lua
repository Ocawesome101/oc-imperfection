-- sh: make sure the shell is running on all terminals --

local log = ...
local boot = computer.getBootAddress()
log("sh: Loading /imperfection/sh.lua")
local sh, err = loadfile(boot.."//imperfection/sh.lua")
if not sh then
  log("sh: Failed:", err)
  while true do coroutine.yield() end
end

scheduler.create(sh, "shell")

while true do coroutine.yield() end
