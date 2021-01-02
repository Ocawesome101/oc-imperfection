-- componentd: abstractions over components --

local log, advance, gpu = ...

log("componentd: Initializing")

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
--  log("componentd: start handler for", addr)
  local stream = stream
  local proxy = capi.proxy(addr)
  local open = {}
  local function handler()
--    log("componentd: start component handler")
    while true do
--      log("chandler: read cmd")
      local command, err = stream:read(1)
--      log("chandler:", command, err)
      if command == "Q" or not command then
        stream:close()
        break
      elseif command == "A" then
        stream:write(addr)
      elseif command == "I" then
        local data = stream:read_formatted()
        local args = {}
        for run in data:gmatch("[^\02]+") do -- delimited is \02
          local eval = load("return " .. run, "=comp_arg", "=bt", {})
          local ok, ret = pcall(eval)
          if ok then
            args[#args + 1] = ret
          end
        end
        local result = table.pack(capi.invoke(addr, args[1], table.unpack(args, 2)))
        local ret = concat(result)
        stream:write_formatted(ret)
      elseif capi.type(addr) == "filesystem" then
        if command == "O" then
          local fname = stream:read_formatted()
          local mode = stream:read(1)
          local handle, err = capi.invoke(addr, "open", fname, mode)
          local fdesc = math.random(1, 9999999999999999999)
          open[fdesc] = fd
          fdesc = tostring(fdesc)
          stream:write_formatted(fdesc)
        elseif command == "R" or command == "W" or command == "C" then
          local data = tonumber(stream:read_formatted())
          if command == "C" then
            capi.invoke(addr, "close", open[fdesc])
            open[fdesc] = nil
          else
            local rlen = tonumber(stream:read(4))
            if command == "R" then
              local data = ""
              repeat
                local chunk = capi.invoke(addr, "read", rlen - #data)
                data = data .. (chunk or "")
              until #data >= rlen or not chunk
              stream:write_formatted(data)
            elseif command == "W" then
              local data = stream:read(rlen)
              capi.invoke(addr, "write", data)
            end
          end
        end
      end
    end
  end
--  log("CD: starting component handler")
  local pid = scheduler.create(handler, "chandler:"..addr)
end

local opened = {}
local open = function(ctype, new)
  checkArg(1, ctype, "string")
  checkArg(2, new, "boolean", "nil")
  local addr
  opened[ctype] = opened[ctype] or {}
  if opened[ctype] and not new then
    addr = next(opened[ctype])
  else
    local list = capi.list(ctype)
    addr = true
    while addr and opened[ctype][addr] or type(addr) == "boolean" do
      addr = list()
    end
    if not addr then
      return nil, "no component of type " .. ctype
    end
    opened[ctype][addr] = true
  end
  --[[if type(addr) ~= "string" then
    return nil, "invalid address type"
  end]]
  local socket, err = ipc.open("componentd")
  if not socket then
    return nil, err
  end
  --log("componentd-connect: opened connection; writing address")
  socket:write(addr)
  coroutine.yield(0.1)
  return socket
end

log("componentd: Registering with IPCD")
ipc.register("componentd")

-- component://gpu/new or component://gpu
local function resolver(ctype, flags)
  return open(ctype, flags == "new")
end

log("componentd: Registering with URLD")
urld.register("component", resolver)

while true do
  local stream = ipc.listen()
--  log("componentd: Accepted connection on", stream.half, " - reading address")
  local addr = stream:read(36)
  create_handler(addr, stream)
end
