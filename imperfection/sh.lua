-- sh ell --

local io = assert(urld.open("vt://new"))

if not io then
  return
end

io:write("\27[2J\27[1;1H")
while true do
  io:write("\27[31msh> \27[37m")
  local input = io:read()
end
