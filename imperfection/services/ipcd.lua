-- ipcd: manages cross-thread communication through signals --

local log, advance, gpu = ...
log("ipcd: Initializing API")

local api = {}
local computer = computer

local aliases = {}

function api.register(name)
  checkArg(1, name, "string")
  aliases[name] = scheduler.info().id
end

local _stream = {}
local state = {}
local streams = {}
function _stream:read(n)
  checkArg(1, n, "number", "nil")
--  log("ipcd: read", n, "bytes from stream", self.id, "half", self.half)
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
    mesg = string.format("%s%s", mesg, tostring(args[i]))
  end
  api.sendmsg(self.dest, "stream_write", self.id, self.half, mesg)
end

function _stream:read_formatted()
  return self:read(tonumber(self:read(4)))
end

function _stream:write_formatted(...)
  local args = table.pack(...)
  local mesg = ""
  for i=1, args.n, 1 do
    mesg = string.format("%s%s", mesg, tostring(args[i]))
  end
  local len = string.format("%04d", #mesg)
  return self:write(len, mesg)
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
  state[id] = "open"
  streams[id] = streams[id] or {}
  streams[id][half] = new
  setmetatable(new, {__name = "pipe", __index = _stream, __metatable = {}})
  return new
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
--  log("ipcd: Creating socket to", dest, "with id", id)
  local msg, rid = api.recvmsg(dest, "open", id)
  if msg == "confirm_open" then
    if rid ~= id then
      return nil, "receiver returned invalid ID (expected "..id..", got "..rid..")"
    end
    state[rid] = "open"
    return create(dest, rid, 1)
  elseif not msg then
    return nil, rid
  end
end

function api.listen(id)
  local sig
  repeat
    sig = table.pack(coroutine.yield(1))
  until sig[1] == "ipc_message" and (id and sig[2] == id or true) and sig[4] == "open"
--  log("ipcd: got request for opening socket from " .. sig[2])
  api.sendmsg(sig[2], "confirm_open", sig[5])
  return create(sig[2], sig[5], 2)
end

_G.ipc = api

log("ipcd: Registering with URLD")
local function resolve(pid)
  return ipc.open(pid)
end
urld.register("ipc", resolve)

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
--      log("ipcd: Write", data, "to", sid, "half", sh, "state", state[sid])
      streams[sid][sh].rb = streams[sid][sh].rb .. tostring(data)
    end
  end
end
