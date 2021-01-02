-- ipcd: manages cross-thread communication through signals --

local log, advance, gpu = ...
log("ipcd: initializing API")

local api = {}
local computer = computer

local aliases = {}

function api.register(name)
  checkArg(1, name, "string")
  aliases[name] = scheduler.info().id
end

local _stream = {}
local state = {}
local streams
function _stream:read(n)
  checkArg(1, n, "number", "nil")
  if not n then
    while state[self.id] == "open" and not self.rb:find("\n") do
      coroutine.yield(1)
    end
    local n = self.rb:find("\n") or #rb
    local ret = self.rb:sub(1, n)
    self.rb = self.rb:sub(#ret + 1)
    return ret
  else
    while state[self.id] == "open" and #self.rb < n do
      coroutine.yield(1)
    end
    local ret = self.rb:sub(1, n)
    self.rb = self.rb:sub(#ret + 1)
    return ret
  end
end

function _stream:write(...)
  local args = table.pack(...)
  local mesg = ""
  for i=1, args.n, 1 do
    mesg = string.format("%s%s", tostring(args[i]))
  end
  api.sendmsg(self.dest, "stream_write", self.id, self.half, mesg)
end

function _stream:close()
  state[self.id] = "closed"
end

local function create(dest, id, half)
  local new = {
    id = id,
    rb = "",
    dest = dest,
    half = half,
  }
  return setmetatable(new, {__name = "pipe", __index = _stream, __metatable = {}})
end

function api.sendmsg(dest, ...)
  checkArg(1, dest, "string", "number")
  if aliases[dest] then dest = aliases[dest] end
  computer.pushSignal("ipc_message", scheduler.info().id, dest, ...)
end

function api.recvmsg(dest, ...)
  checkArg(1, dest, "string", "number")
  if aliases[dest] then dest = aliases[dest] end
  if select("#", ...) > 0 then
    api.sendmsg(dest, ...)
  end
  local current = scheduler.info().id
  local sig
  local timeout = computer.uptime() + 5
  repeat
    sig = table.pack(coroutine.yield(timeout - computer.uptime()))
    if computer.uptime() >= timeout then
      return nil, "timed out"
    end
  until sig[1] == "ipc_message" and sig[2] == dest and sig[3] == current
  return table.unpack(sig, 4, sig.n)
end

function api.open(dest)
  local id = math.random(1, 9999999999999999)
  local msg, rid = api.sendmsg(desg, "open", id)
  if msg == "confirm_open" then
    if rid ~= id then
      return nil, "receiver returned invalid ID"
    end
    streams[rid] = {}
    streams[rid][1] = create(dest, rid, 1)
    return streams[rid][1]
  end
end

function api.listen(id)
  local sig
  repeat
    sig = table.pack(coroutine.yield())
  until sig[1] == "ipc_message" and sig[2] == id and sig[4] == "open"
  api.sendmsg(sig[3], "confirm_open", sig[5])
  streams[sig[5]] = {}
  streams[sig[5]][2] = create(sig[3], sig[5], 2)
  return streams[sig[5]][2]
end

_G.ipc = api

while true do
  local sig = table.pack(coroutine.yield())
  if sig[1] == "ipc_message" and sig[4] == "stream_write" then
    local sid, sh, data = sig[5], sig[6], sig[7]
    if sh == 1 then
      sh = 2
    elseif sh == 2 then
      sh = 1
    end
    if sid and sh and data and streams[sid] and streams[sid][sh] then
      streams[sid][sh].rb = streams[sid][sh].rb .. tostring(data)
    end
  end
end
