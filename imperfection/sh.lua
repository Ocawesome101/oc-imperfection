-- sh ell --

local io = scheduler.info().state.term

if not io then
  return
end

local function invoke(method, ...)
  local write = ipc.pack_formatted(...)
  io:write(method)
  io:write_formatted(write)
  return ipc.unpack_formatted(io:read_formatted())
end

local w, h = invoke("G", "size")
local function read()
  local buffer = ""
  local x, y = invoke("G", "cpos")
  local in_esc = false
  repeat
    x, y = invoke("G", "cpos")
    local char = invoke("R")
    if string.byte(char) > 31 and string.byte(char) < 127 and not in_esc then
      buffer = buffer .. char
      if #buffer > 1 then
        invoke("C", x - 1, y)
      end
      invoke("W", char.."_")
    elseif char == "\8" and #buffer > 0 then
      buffer = buffer:sub(1, -2)
      if x == 1 then
        x = w
        y = y + 1
      else
        x = x - 1
      end
      invoke("C", x, y)
      invoke("W", "  ")
      if #buffer > 0 then
        invoke("C", x, y)
      elseif #buffer == 0 then
        invoke("C", x - 1, y)
      end
    elseif char == "\0" then
      in_esc = true
    elseif in_esc then
      in_esc = false
    end
  until char == "\13"
  invoke("C", 1, y + 1)
  invoke("W", " ")
end

invoke("C", 1, 1)
invoke("L", 1, 1, w, h, " ")
while true do
  invoke("W", "sh> ")
  local input = read()
end
