-- the Imperfect kernel --

local gpu, advance, fs = ...
local log = function()end

if gpu then
  local w, h = gpu.getResolution()
  local pref = "->"
  log = function(...)
    local args = table.pack(...)
    local msg = pref
    if args[1] == "SETPREF" then
      pref = args[2]
      return
    end
    for i=1, args.n, 1 do
      msg = string.format("%s %s", msg, tostring(args[i]))
    end
    gpu.copy(1, 3, w, h, 0, -1)
    gpu.fill(1, h, w, 1, " ")
    gpu.set(1, h, msg)
    advance()
  end
end

log("Starting Imperfect")
log("Total system memory:", string.format("%dK", computer.totalMemory()/1024))
log("SETPREF", "[knl]")
log("Wrapping computer.{push,pull}Signal")
do
  local psh, pop = computer.pushSignal, computer.pullSignal
  local sig_buf = {}
  function computer.pullSignal(timeout)
    if #sig_buf > 0 then
      return table.unpack(table.remove(sig_buf, 1))
    end
    return pop(timeout)
  end
  function computer.pushSignal(...)
    sig_buf[#sig_buf + 1] = table.pack(...)
    return true
  end
end
log("Initializing scheduler")
do
  local threads = {}
  local api = {}
  local last = 0
  local current = 0
  function api.create(func, name)
    checkArg(1, func, "function")
    checkArg(2, name, "string", "nil")
    name = name or tostring(func)
    local new = {
      coro = coroutine.create(func),
      name = name,
      timeout = 0,
      handles = {},
      state = {},
      dead = false
    }
    if threads[current] then
      for k, v in pairs(threads[current].state) do
        new.state[k] = v
      end
    end
    last = last + 1
    threads[last] = new
    return last
  end

  function api.info()
    local t = threads[current] or {}
    return {
      id = current,
      state = t.state or {},
      handles = t.handles or {},
      deadline = t.timeout or computer.uptime()
    }
  end

  function api.list()
    local t = {}
    for i, p in pairs(threads) do
      t[#t + 1] = i
    end
    return t
  end

  function api.remove(pid)
    threads[pid] = nil
  end

  function api.loop()
    log("Starting scheduler")
    api.loop = nil
    while true do
      local uptime = computer.uptime()
      local timeout = math.huge
      for i, t in pairs(threads) do
        if t.dead then
          threads[i] = nil
        else
          if t.timeout - uptime < timeout then
            timeout = t.timeout - uptime
          end
          if timeout <= 0 then
            timeout = 0
            break
          end
        end
      end

      local signal = table.pack(computer.pullSignal(timeout))
      for i, t in ipairs(threads) do
        if signal.n > 0 or t.timeout <= uptime then
          current = i
          local result = table.pack(coroutine.resume(t.coro, table.unpack(signal)))
          if not result[1] then
            computer.pushSignal("thread_died", i, t.name, tostring(result[2]))
            t.dead = true
          elseif type(result[2]) == "number" then
            t.timeout = computer.uptime() + result[2]
          else
            t.timeout = math.huge
          end
        end
      end
    end
  end

  _G.scheduler = api
end

do
  local start = {
    "urld",
    "ipcd",
    "componentd",
    "rcd"
  }
  local load_service
  load_service = function(s)
    local handle = assert(fs.open("/imperfection/services/"..s..".lua"))
    local data = ""
    repeat
      local chunk = fs.read(handle, math.huge)
      advance()
      data = data .. (chunk or "")
    until not chunk
    fs.close(handle)
    local func = assert(load(data, "="..s, "bt", _G))
    scheduler.create(function()
      func(log, advance, gpu, s == "rcd" and load_service or nil,
                                        s == "rcd" and fs or nil)
    end, s)
  end
  for i=1, #start, 1 do
    log("Starting", start[i])
    load_service(start[i])
  end
end

scheduler.loop()
