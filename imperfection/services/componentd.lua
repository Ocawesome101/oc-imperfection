-- componentd: abstractions over components --

local log, advance, gpu = ...

log("componentd: initializing")

local capi = component
_G.component = nil

local function concat(tbl)
  local ret = ""
  for i=1, tbl.n, 1 do
    ret = ret .. tbl[i]
    if i < tbl.n then ret = ret .. "\02" end
  end
  return ret
end

local function create_handler(addr, stream)
  local stream = stream
  local proxy = comp.proxy(addr)
  local function handler()
    while true do
      local command, err = stream:read(1)
      if command == "C" or not command then
        break
      elseif command == "I" then
        local len = stream:read(4)
        local data = stream:read(tonumber(len))
        local args = {}
        for run in data:gmatch("[^\02]+") do -- delimited is \02
          local eval = load("return " .. run, "=comp_arg", "=bt", {})
          local ok, ret = pcall(eval)
          if ok then
            args[#args + 1] = ret
          end
        end
        local result = table.pack(comp.invoke(addr, args[1], table.unpack(args, 2)))
        local ret = concat(result)
        stream:write(ret)
      end
    end
  end
end

_G.component = {
  open = function(ctype)
    local addr
    if opened[ctype] then
      addr = opened[ctype]
    else
      addr = capi.list(ctype)()
      if not addr then
        return nil, "no component of type " .. ctype
      end
      opened[ctype] = addr
    end
    local socket = ipc.open("componentd")
    socket:write(addr)
    coroutine.yield(0.1)
    return socket
  end
}

log("componentd: registering with IPCD")
ipc.register("componentd")
while true do
  local stream = ipc.listen()
  local addr = stream:read(36)
  create_handler(addr, stream)
end
