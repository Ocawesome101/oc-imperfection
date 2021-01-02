-- fsd: filesystem management --

local log = ...
log("fsd: Initializing")

local mounts = {}

repeat
  local socket, err = urld.open("component://filesystem/new")
  if socket then
    socket:write("A")
    local addr = socket:read(36)
    log("fsd: Registering filesystem", addr)
    mounts[addr] = socket
  end
until not socket

local function concat_keys(t)
  local msg = ""
  for k, v in pairs(t) do
    msg = msg .. k .. "\02"
  end
  msg = msg:sub(1, -2)
  return msg
end

local function create_handler(addr, file, mode)
  local fs = mounts[addr]
  fs:write("O", string.format("%08d", #file), file, (mode:sub(1,1)))
  local fd = fs:read_formatted()
  local src_pid = scheduler.info().id
  local function handler()
    local socket = ipc.listen(src_pid)
    while true do
      local data = tonumber(socket:read(8))
      if mode == "r" then
        fs:write("R")
        fs:write_formatted(fd)
        fs:write(data)
      elseif mode == "w" or mode == "a" then
        local more = socket:read(#socket.rb)
        fs:write("W")
        fs:write_formatted(fd)
        fs:write_formatted(more)
      end
    end
  end
  local pid = scheduler.create(handler, "fshandler:"..file..":"..mode)
  return ipc.open(pid)
end

local call = component.invoke
local function resolver(addr, query)
  local data, socket
  if addr == "mounts" then
    data = concat_keys(mounts)
  else
    for k, v in pairs(mounts) do
      if k:sub(1, #addr) == addr then
        local addr = k
        -- e.g. fs://a342e6/type?file=/bin/sh.lua
        local op, file = query:match("^(.+)%?file=(.+)$")
        if not (op and file) then
          data = ""
        end
        if op == "type" then
          data = ipcd.pack_formatted(call(mounts[addr], "isDirectory", file))
        elseif op == "open" then
          -- e.g. fs://a4e32b9c/open?file=/bin/sh.lua?r
          local mode = file:sub(-1)
          file = file:sub(-2)
          if mode ~= "r" and mode ~= "w" and mode ~= "a" then
            mode = "r"
          end
          socket = create_handler(addr, file, mode)
        elseif op == "mkdir" then
          data = concat(table.pack(call(mounts[addr], "makeDirectory", file)))
        elseif op == "remove" then
          data = concat(table.pack(call(mounts[addr], "remove", file)))
        end
      end
    end
  end
  if not socket then
    local len = string.format("%08d", #data)
    socket = {
      read = function(self)
        if len then
          local tmp = len
          len = nil
          return tmp
        elseif data then
          local tmp = data
          data = nil
          return tmp
        end
      end,
      write = function() end
    }
  end
  return socket
end

log("fsd: Registering with IPCD")
ipc.register("fsd")

log("fsd: Registering with URLD")
urld.register("fs", resolver)

function _G.loadfile(file, mode, env)
  checkArg(1, file, "string")
  checkArg(2, mode, "string", "nil")
  checkArg(3, env, "table", "nil")
  local socket, err = urld.open(file.."?r")
  if not socket then
    return nil, err
  end
  socket:write()
end

while true do
  coroutine.yield()
end
