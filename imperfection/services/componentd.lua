-- componentd: abstractions over components --

local log, advance, gpu = ...

log("componentd: Initializing")

local capi = component
_G.component = nil

local function concat(tbl)
  local ret = ""
  for i=1, tbl.n, 1 do
    if type(tbl[i]) == "string" then
      tbl[i] = string.format("\"%s\"", tbl[i])
    end
    ret = ret .. tostring(tbl[i])
    if i < tbl.n then ret = ret .. "\02" end
  end
  return ret
end

local function create_handler(addr, from)
  --log("componentd: start handler for", addr)
  local proxy = capi.proxy(addr)
  local open = {}
  local function handler()
    --log("componentd: start component handler")
    local stream = ipc.listen(from)
    --log("comphandler", addr, "got connection from", from)
    coroutine.yield(0.1)
    while true do
      --log("chandler: read cmd")
      local command, err = stream:read(1)
      --log("chandler", addr, command, err)
      if command == "Q" or command == "" or not command then
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
          else
            --log("chandler:", ret)
          end
        end
        if #args > 0 then
          local result = table.pack(capi.invoke(addr, args[1], table.unpack(args, 2)))
          local ret = concat(result)
          stream:write_formatted(ret)
        end
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
  --log("CD: starting component handler")
  return scheduler.create(handler, "chandler:"..addr)
end

local opened = {}
local open = function(ctype, new)
  checkArg(1, ctype, "string")
  checkArg(2, new, "boolean", "nil")
  local requesting = scheduler.info().id
  local addr
  opened[ctype] = opened[ctype] or {}
  if not new then
    addr = next(opened[ctype])
  end
  if not addr then
    --log("componentd: Got request for component of type", ctype, "from", requesting)
    local list = capi.list(ctype)
    for k, v in pairs(list) do
      if not opened[ctype][k] then
        addr = k
        break
      end
    end
    opened[ctype][addr] = true
  end
  --log("componentd: Opening socket for component", addr, "on", scheduler.info().id)
  local pid = create_handler(addr, scheduler.info().id)
  local socket, err = ipc.open(pid)
  if not socket then
    --log("componentd: failed opening socket to", pid, "because")
    --log("           ", err)
    return nil, err
  end
  --log("componentd: Returning socket for", addr, "to", scheduler.info().id)
--  coroutine.yield(0.1)
  return socket
end

-- component://gpu/new or component://gpu
local function resolver(ctype, flags)
  return open(ctype, flags == "new")
end

log("componentd: Registering with URLD")
urld.register("component", resolver)

_G.component = {}
function component.invoke(stream, field, ...)
  checkArg(1, stream, "table")
  checkArg(2, field, "string")
  local mesg = ipcd.pack_formatted(field, ...)
  stream:write_formatted(mesg)
  local result = stream:read_formatted()
  return unpack(result)
end

while true do
  coroutine.yield()
end
