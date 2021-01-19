-- basic FORTH dialect for OpenComputers EEPROMs --

-- terminal interfacing code
local cx,cy=1,1
local gpu=component.proxy((assert(component.list("gpu", true)(),
                                          "no GPU found but one is required")))
gpu.bind((assert(component.list("screen", true)(), "no screen found but one is required")))
local w,h=gpu.maxResolution()
gpu.setResolution(w,h)
local function check()
  if cx>w then cx,cy=1,cy+1 end
  if cy>=h then cy=h-1 gpu.copy(1,1,w,h,0,-1)gpu.fill(1,h,w,1," ") end
  if cx<1 then cx=w+cx cy=cy-1 end
  if cy<1 then cy=1 end
end
local function wr(ln, cr)
  ln=ln:gsub("\n","")
  while #ln > 0 do
    local wl=ln:sub(1,w-cx+1)
    ln=ln:sub(#wl+1)
    gpu.set(cx, cy, wl)
    cx=cx+#wl
    check()
  end
  if not cr then cx,cy=1,cy+1 end
  check()
end

local function readline()
  local buf=""
  local csr=unicode.char(0x2588)
  local sx,sy=cx,cy
  local function redraw()
    local len=#buf
    if sy+math.max(1,math.ceil((#buf+2)/w))>h then
      sy=sy-1
    end
    cx,cy=sx,sy
    wr(buf..csr.." ")
  end
  while true do
    redraw()
    local e,_,key,code=computer.pullSignal()
    if e=="key_down" then
      if key==8 then
        buf=buf:sub(1, -2)
      elseif key==13 then
        csr=" "
        redraw()
        return buf
      elseif key>31 and key<127 then
        buf=buf..string.char(key)
      end
    end
  end
end

wr("OPEN FORTH 0.1.0")

local stack={push=function(val)table.insert(stack,1,val)end,
pop=function()return table.remove(stack,1)end}

local w={}
w["."]=function() local val=stack:pop()
  wr(tostring(val).." ",true) end

w["+"]=function()stack:push(stack:pop() + stack:pop())end
w["-"]=function()stack:push(stack:pop() - stack:pop())end
w["*"]=function()stack:push(stack:pop() * stack:pop())end
w["/"]=function()stack:push(stack:pop() / stack:pop())end
w["<"]=function()stack:push(stack:pop()==stack:pop())end
w.cr=function()wr("")end
w.dup=function()local v=stack:pop()stack:push(v)stack:push(v)end
w.pwr=function()computer.shutdown(not not stack:pop())end
w.drop=function()stack:pop()end

local d,id,ic,je,jt=()

local function e(exp)
  -- FORTH is extremely simple
  -- this isn't quite a fully compliant implementation
  -- and it's definitely minimal
  for _w in exp:gmatch("[^ ]+") do
    _w=_w:lower()
    if _w==":" and not ic then
      if not id then
        id=true
      else
        wr("unexpected: ':'")
        return
      end
    elseif _w==";" and not ic then
      if id then
        id=false
      else
        wr("unexpected: ';'")
        return
      end
    elseif id then
      if type(id)=="boolean" then
        id=_w
        d[id]=""
      else
        d[id]=d[id].." ".._w
      end
    elseif _w=="(" then
      ic=true
    elseif _w==")" then
      if not ic then
        wr("unexpected: ')'")
        return
      else
        ic=false
      end
    elseif not ic then
      if je then
        if _w=="else" then je=false end
      elseif jt then
        if _w=="then" then jt=false end
      elseif _w=="if" then
        je=not not stack:pop()
      elseif _w=="else" then
        jt=true
      elseif d[_w] then
        if not e(d[_w]) then return end
      elseif w[_w] then
        w[_w]()
      elseif tonumber(_w) then
        stack:push(tonumber(_w))
      elseif tonumber(_w, 16) then
        stack:push(tonumber(_w, 16))
      else
        wr(string.format("undefined: '%s'", tostring(_w)))
        return
      end
    end
  end
  return true
end

while true do
  wr("> ")
  -- hax
  cx,cy=3,cy-1
  local ret=readline()
  if #ret > 0 then
    if e(ret) then
      wr("ok")
    end
  end
end
