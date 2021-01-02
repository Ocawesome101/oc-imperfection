-- urld: URL resolution --

local log, advance, gpu = ...

log("urld: Initializing API")

local api = {}

local registered = {}

-- resolver(host, body) -> socket or nil, err
function api.register(proto, resolver)
  checkArg(1, proto, "string")
  checkArg(2, resolver, "function")
  if registered[proto] then
    return true
  end
  --log("urld: Registering protocol", proto)
  registered[proto] = resolver
  return true
end

-- URL -> socket or nil, err
local function resolve(url)
  local proto, host, body = url:match("^(.+)://(.-)/(.+)$")
  if not (proto and host and body) then
    return nil, "invalid URL"
  end
  if not registered[proto] then
    return nil, "protocol not registered: " .. proto
  end
  local func = registered[proto]
  local ok, ret, err = pcall(func, host, body)
  if (not ok and ret) or (ok and err and not ret) then
    return nil, ret or err
  end
  return ret
end

function api.open(url)
  checkArg(1, url, "string")
  local ok, err = resolve(url)
  if not ok then
    return nil, err
  end
  return ok
end

_G.urld = api

while true do
  coroutine.yield()
end
