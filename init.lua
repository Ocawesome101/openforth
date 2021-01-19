-- basic FORTH dialect for OpenComputers EEPROMs --

-- terminal interfacing code
local g=component.proxy((assert(component.list("gpu", true)(),
                                          "no GPU found but one is required")))
g.bind((assert(component.list("screen", true)(), "no screen found but one is required")))
local cx,cy,w,h=1,1,g.maxResolution()
g.setResolution(w,h)
g.fill(1,1,w,h," ")
local function check()
  if cx>w then cx,cy=1,cy+1 end
  if cy>=h then cy=h-1 g.copy(1,1,w,h,0,-1)g.fill(1,h,w,1," ") end
  if cx<1 then cx=w+cx cy=cy-1 end
  if cy<1 then cy=1 end
end
local function wr(ln, cr)
  ln=ln:gsub("\n","")
  while #ln>0 do
    local wl=ln:sub(1,w-cx+1)
    ln=ln:sub(#wl+1)
    g.set(cx, cy, wl)
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

wr("OPEN FORTH 0.3.0")

local stack={push=function(s,v)table.insert(s,1,v)end,
pop=function(s)return table.remove(s,1)end}

local w,d,f,id,ic,je,jt={},{},{}
wr("FSTREE...",true)
for a,c in component.list("filesystem")do f[#f+1]=a end
wr("OK")
w["."]=function()local val=stack:pop()wr(tostring(val).." ",true) end
w["+"]=function()stack:push(stack:pop()+stack:pop())end
w["-"]=function()stack:push(stack:pop()-stack:pop())end
w["*"]=function()stack:push(stack:pop()*stack:pop())end
w["/"]=function()stack:push(stack:pop()/stack:pop())end
w["<"]=function()stack:push(stack:pop()==stack:pop())end
w.cr=function()wr("")end
w.dup=function()local v=stack:pop()stack:push(v)stack:push(v)end
w.pwr=function()computer.shutdown(not not stack:pop())end
w.drop=function()stack:pop()end
w.fls=function()for i=1,#f,1 do wr(tostring(i),true)wr("="..f[i])end end
w.ldi=function()local n,d,c,x,h=stack:pop(),"";x=component.proxy(f[n]);h=x.open("init.lua");if not x then return end repeat c=x.read(h,math.huge)d=d..(c or"")until not c local ok,err=load(d,"=init.lua")if not ok then wr(err)return else ok() end end
w.words=function()for k in pairs(w) do wr(k.." ",true) end for k in pairs(d) do wr(k.." ",true) end end

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
  --wr("",true)
  local ret=readline()
  if #ret>0 then
    if e(ret) then
      wr("OK")
    end
  end
end
