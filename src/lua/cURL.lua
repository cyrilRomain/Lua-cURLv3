--
-- Implementation of Lua-cURL http://msva.github.io/lua-curl
--

local curl = require "lcurl"

local function wrap_function(k)
  return function(self, ...)
    local ok, err = self._handle[k](self._handle, ...)
    if ok == self._handle then return self end
    return ok, err
  end
end

local function wrap_setopt_flags(k, flags)
  k = "setopt_" .. k
  return function(self, v)
    v = assert(flags[v], "Unsupported value " .. tostring(v))
    local ok, err = self._handle[k](self._handle, v)
    if ok == self._handle then return self end
    return ok, err
  end
end

-------------------------------------------
local Easy = {} do

Easy.__index = function(self, k)
  local fn = Easy[k]
 
  if not fn and self._handle[k] then
    fn = wrap_function(k)
    self[k] = fn
  end
  return fn
end

function Easy:new()
  local h, err = curl.easy()
  if not h then return nil, err end

  local o = setmetatable({
    _handle = h
  }, self)

  return o
end

function Easy:handle()
  return self._handle
end

local perform      = wrap_function("perform")
local setopt_share = wrap_function("setopt_share")

function Easy:perform(opt)
  local e = self:handle()

  local oerror = opt.errorfunction or function(err) return nil, err end

  if opt.readfunction then
    local ok, err = e:setopt_readfunction(opt.readfunction)
    if not ok then return oerror(err) end
  end

  if opt.writefunction then
    local ok, err = e:setopt_writefunction(opt.writefunction)
    if not ok then return oerror(err) end
  end

  if opt.headerfunction then
    local ok, err = e:setopt_headerfunction(opt.headerfunction)
    if not ok then return oerror(err) end
  end

  local ok, err = perform(self)
  if ok then return oerror(err) end

  return self 
end

function Easy:post(data)
  local form = curl.form()
  local ok, err = true

  for k, v in pairs(data) do
    if type(v) == "string" then
      ok, err = form:add_content(k, v)
    else
      assert(type(v) == "table")
      if v.stream_length then
        form:free()
        error("Stream does not support")
      end
      if v.data then
        ok, err = form:add_buffer(k, v.file, v.data, v.type, v.headers)
      else
        ok, err = form:add_file(k, v.file, v.data, v.type, v.filename, v.headers)
      end
    end
    if not ok then break end
  end

  if not ok then
    form:free()
    return nil, err
  end

  ok, err = e:setopt_httppost(form)
  if not ok then
    form:free()
    return nil, err
  end

  return self
end

function Easy:setopt_share(s)
  return setopt_share(self, s:handle())
end

Easy.setopt_proxytype = wrap_setopt_flags("proxytype", {
  ["HTTP"            ] = curl.PROXY_HTTP;
  ["HTTP_1_0"        ] = curl.PROXY_HTTP_1_0;
  ["SOCKS4"          ] = curl.PROXY_SOCKS4;
  ["SOCKS5"          ] = curl.PROXY_SOCKS5;
  ["SOCKS4A"         ] = curl.PROXY_SOCKS4A;
  ["SOCKS5_HOSTNAME" ] = curl.PROXY_SOCKS5_HOSTNAME;
})

end
-------------------------------------------

-------------------------------------------
local Multi = {} do

Multi.__index = function(self, k)
  local fn = Multi[k]
 
  if not fn and self._handle[k] then
    fn = wrap_function(k)
    self[k] = fn
  end
  return fn
end

function Multi:new()
  local h, err = curl.multi()
  if not h then return nil, err end

  local o = setmetatable({
    _handle = h;
    _easy   = {};
  }, self)

  return o
end

function Multi:handle()
  return self._handle
end

local perform       = wrap_function("perform")
local add_handle    = wrap_function("add_handle")
local remove_handle = wrap_function("remove_handle")

local function make_iterator(self)
  local curl = require "lcurl.safe"

  local buffers = {_ = {}} do

  function buffers:append(e, ...)
    local b = self._[e] or {}
    self._[e] = b
    b[#b + 1] = {...}
  end

  function buffers:next()
    for e, t in pairs(self._) do
      local m = table.remove(t, 1)
      if m then return e, m end
    end
  end

  end

  local remain = #self._easy
  for _, e in ipairs(self._easy) do
    e:setopt_writefunction (function(str) buffers:append(e, "data",   str) end)
    e:setopt_headerfunction(function(str) buffers:append(e, "header", str) end)
  end

  assert(perform(self))

  return function()
    while true do
      local e, t = buffers:next()
      if t then return t[2], t[1], e end
      if remain == 0 then break end

      self:wait()

      local n, err = assert(perform(self))

      if n <= remain then
        while true do
          local e, ok, err = assert(self:info_read())
          if e == 0 then break end
          if ok then buffers:append(e, "done", ok)
          else buffers:append(e, "error", err) end
        end
        remain = n
      end

    end
  end
end

function Multi:perform()
  return make_iterator(self)
end

function Multi:add_handle(e)
  self._easy[#self._easy + 1] = e
  return add_handle(self, e:handle())
end

function Multi:remove_handle(e)
  self._easy[#self._easy + 1] = e
  return remove_handle(self, e:handle())
end

end
-------------------------------------------

-------------------------------------------
local Share = {} do

Share.__index = function(self, k)
  local fn = Share[k]
 
  if not fn and self._handle[k] then
    fn = wrap_function(k)
    self[k] = fn
  end
  return fn
end

function Share:new()
  local h, err = curl.easy()
  if not h then return nil, err end

  local o = setmetatable({
    _handle = h
  }, self)

  return o
end

function Share:handle()
  return self._handle
end

Share.setopt_share = wrap_setopt_flags("share", {
  [ "COOKIE"      ] = curl.LOCK_DATA_COOKIE;
  [ "DNS"         ] = curl.LOCK_DATA_DNS;
  [ "SSL_SESSION" ] = curl.LOCK_DATA_SSL_SESSION;
})

end
-------------------------------------------

local cURL = {}

function cURL.version() return curl.version() end

function cURL.easy_init()  return Easy:new()  end

function cURL.multi_init() return Multi:new() end

function cURL.share_init() return Share:new() end

return cURL
