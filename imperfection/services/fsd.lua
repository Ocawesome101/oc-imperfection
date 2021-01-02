-- fsd: filesystem management --

local log = ...
log("fsd: Initializing")

local mounts = {}

log("fsd: Registering filesystems")
repeat
  local socket, err = urld.open("component://filesystem/new")
  if socket then
    -- we have to yield here, otherwise we steal the address from componentd,
    --   which causes things to break badly.
    -- at least, i think we do.  even if we don't, well, better safe than sorry.
    coroutine.yield(0.1)
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

local function concat(t)
  local msg = ""
  for i=1, t.n or #t, 1 do
    msg = msg .. tostring(t[i]) .. "\02"
  end
  msg = msg:sub(1, -2)
  return msg
end

local function unpack(data)
  local args = {}
  for run in data:gmatch("[^\02]+") do -- delimited is \02
    local eval = load("return " .. run, "=unpack_field", "=bt", {})
    local ok, ret = pcall(eval)
    if ok then
      args[#args + 1] = ret
    end
  end
  return table.unpack(args)
end

local function call(sock, method, ...)
  local args = table.pack(method, ...)
  sock:write(args[1])
  local len = sock:read(4)
  len = tonumber(len)
  local data = sock:read(len)
  return unpack(data)
end

local function create_handler(addr, file, mode)
  local fs = mounts[addr]
  fs:write("O", string.format("%04d", #file), file, (mode:sub(1,1)))
  local fd = fs:read(tonumber(fs:read(4)))
  local src_pid = scheduler.info().id
  local function handler()
    local socket = ipc.listen()
    while true do
      local data = tonumber(socket:read(4))
      if mode == "r" then
        fs:write("R", string.format("%04d", #fd), fd, data)
      elseif mode == "w" or mode == "a" then
        local more = socket:read(#socket.rb)
        fs:write("W", string.format("%04d", #fd), fd, string.format("%04d", #more), more)
      end
    end
  end
  local pid = scheduler.create(handler, "fshandler:"..file..":"..mode)
  return ipc.open(pid)
end

local function resolver(addr, query)
  local data, socket
  if addr == "mounts" then
    data = concat(mounts)
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
          data = concat(table.pack(call(mounts[addr], "isDirectory", file)))
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
    local len = string.format("%04d", #data)
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
      end
    }
  end
  return socket
end

log("fsd: Registering with IPCD")
ipc.register("fsd")

log("fsd: Registering with URLD")
urld.register("fs", resolver)

while true do
  local socket = ipc.listen()
end
