-- sh: make sure the shell is running on all terminals --

local log = ...
local boot = computer.getBootAddress()
log("sh: Loading /imperfection/sh.lua")
local sh, err = loadfile(boot.."//imperfection/sh.lua")
if not sh then
  log("sh: Failed:", err)
  while true do coroutine.yield() end
end

repeat
  local term, err = urld.open("vt://new")
  if term then
    scheduler.info().state.term = term
    scheduler.create(sh, "shell")
  end
until not term

while true do coroutine.yield() end
