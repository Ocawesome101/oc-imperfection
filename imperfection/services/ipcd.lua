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
  --log("ipcd: read", n, "bytes from stream", self.id, "half", self.half)
  if state[self.id] == "closed" then
    return nil, "stream closed"
  end
  if not n then
    while state[self.id] == "open" and not self.rb:find("\n") do
      coroutine.yield(1)
    end
    local n = self.rb:find("\n") or #self.rb
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
  if state[self.id] == "closed" then
    return nil, "stream closed"
  end
  for i=1, args.n, 1 do
    mesg = string.format("%s%s", mesg, tostring(args[i]))
  end
  api.sendmsg(self.dest, "stream_write", self.id, self.half, mesg)
end

function _stream:read_formatted()
  return self:read(tonumber(self:read(8)))
end

function _stream:write_formatted(...)
  local args = table.pack(...)
  local mesg = ""
  for i=1, args.n, 1 do
    mesg = string.format("%s%s", mesg, tostring(args[i]))
  end
  local len = string.format("%08d", #mesg)
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
  --log("ipcd: Creating socket to", dest, "with id", id, "from", scheduler.info().id)
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
  local current = scheduler.info().id
  if id then
    repeat
      sig = table.pack(coroutine.yield(1))
    until sig[1] == "ipc_message" and sig[2] == id and sig[3] == current and sig[4] == "open"
  else
    repeat
      sig = table.pack(coroutine.yield(1))
    until sig[1] == "ipc_message" and sig[3] == current and sig[4] == "open"
  end
  --log("ipcd: got request for opening socket from " .. sig[2])
  api.sendmsg(sig[2], "confirm_open", sig[5])
  local new = create(sig[2], sig[5], 2)
  new.from = sig[2]
  return new
end

function api.pack_formatted(...)
  local args = table.pack(...)
  local mesg = ""
  for i=1, args.n, 1 do
    local final = args[i]
    if type(final) == "string" then
      final = string.format("\"%s\"", final)
    elseif type(final) == "table" then
      local tmp = "{"
      -- this Should(tm) work
      for k, v in pairs(final) do
        if type(v) == "string" then
          v = v:gsub("\"+", "\\\"")
          v = string.format("\"%s\"", v)
        else
          v = tostring(v)
        end
        if type(k) == "string" then
          k = k:gsub("\"+", "\\\"")
          k = string.format("\"%s\"", k)
        else
          k = tostring(k)
        end
        tmp = string.format("%s[%s]=%s,", tmp, k, v)
      end
      tmp = tmp .. "}"
      final = tmp
    else
      final = tostring(final)
    end
    mesg = mesg .. final
    if i < args.n then mesg = mesg .. "\02" end
  end
  return mesg
end

local function deser(v)
  if tonumber(v) then
    return true, tonumber(v)
  elseif v == "true" then
    return true, true
  elseif v == "false" then
    return true, false
  elseif v:match("^\"(.+)\"$") then
    return true, (v:sub(2, -2))
  else
    local ok, err = load("return " .. v, "=deserializing", "bt", {})
    if not ok then
      return nil, err
    end
    return pcall(ok)
  end
end

function api.unpack_formatted(data)
  local args = {}
  local n = 1
  for val in data:gmatch("[^\02]+") do -- delimited is \02
    local ok, ret = deser(val)
    if ok then
      args[n] = ret
      n = n + 1
    end
  end
  return table.unpack(args, 1, n)
end

_G.ipc = api

log("ipcd: Registering with URLD")
local function resolve(pid)
  checkArg(1, pid, "string", "number")
  return ipc.open(tonumber(pid) or pid)
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
      --log("ipcd: Write", data, "to", sid, "half", sh, "state", state[sid])
      streams[sid][sh].rb = streams[sid][sh].rb .. tostring(data)
    end
  end
end
