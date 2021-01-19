-- basic FORTH dialect for OpenComputers --

-- terminal interfacing code
local cx, cy = 1, 1
local gpu = component.proxy((assert(component.list("gpu", true)(),
                                          "no GPU found but one is required")))
gpu.bind((assert(component.list("screen", true)(), "no screen found but one is required")))
local w, h = gpu.maxResolution()
gpu.setResolution(w, h)
local function check()
  if cx > w then cx, cy = 1, cy + 1 end
  if cy >= h then cy = h - 1 gpu.copy(1, 1, w, h, 0, -1) gpu.fill(1, h, w, 1, " ") end
  if cx < 1 then cx = w + cx cy = cy - 1 end
  if cy < 1 then cy = 1 end
end
local function write(ln, cr)
  ln = ln:gsub("\n", "")
  while #ln > 0 do
    local wl = ln:sub(1, w - cx + 1)
    ln = ln:sub(#wl + 1)
    gpu.set(cx, cy, wl)
    cx = cx + #wl
    check()
  end
  if not cr then cx, cy = 1, cy + 1 end
  check()
end

local cursor = unicode.char(0x2588)
local function readline()
  local buf = ""
  local csr = cursor
  local sx, sy = cx, cy
  local function redraw()
    local len = #buf
    if sy + math.max(1, math.ceil((#buf + 2) / w)) > h then
      sy = sy - 1
    end
    cx, cy = sx, sy
    write(buf .. csr .. " ")
  end
  while true do
    redraw()
    local e, _, key, code = computer.pullSignal()
    if e == "key_down" then
      if key == 8 then
        buf = buf:sub(1, -2)
      elseif key == 13 then
        csr = " "
        redraw()
        return buf
      elseif key > 31 and key < 127 then
        buf = buf .. string.char(key)
      end
    end
  end
end

write("OPEN FORTH 0.1.0")

local stack = {}
function stack:push(val)
  table.insert(stack, 1, val)
end
function stack:pop()
  return table.remove(stack, 1)
end

local words = {}
words["."] = function()
  local val = stack:pop()
  write(tostring(val) .. " ", true)
end

words["+"] = function() stack:push(stack:pop() + stack:pop()) end
words["-"] = function() stack:push(stack:pop() - stack:pop()) end
words["*"] = function() stack:push(stack:pop() * stack:pop()) end
words["/"] = function() stack:push(stack:pop() / stack:pop()) end
words["<"] = function() stack:push(stack:pop() == stack:pop()) end
words.cr = function() write("") end
words.dup = function() local v = stack:pop() stack:push(v) stack:push(v) end
words.pwr = function() computer.shutdown(not not stack:pop()) end


local defs = {}
local indef, incmt

local function eval(exp)
  -- FORTH is extremely simple - watch this
  for word in exp:gmatch("[^ ]+") do
    word = word:lower()
    if word == ":" and not incmt then
      if not indef then
        indef = true
      else
        write("unexpected: ':'")
        return
      end
    elseif word == ";" and not incmt then
      if indef then
        indef = false
      else
        write("unexpected: ';'")
        return
      end
    elseif indef then
      if type(indef) == "boolean" then
        indef = word
      else
        defs[indef] = defs[indef] .. " " .. word
      end
    elseif word == "(" then
      incmt = true
    elseif word == ")" then
      if not incmt then
        write("unexpected: ')'")
        return
      else
        incmt = false
      end
    elseif not incmt then
      if jelse then
        if word == "else" then jelse = false end
      elseif word == "if" then
        jelse = not not stack:pop()
      elseif defs[word] then
        if not eval(defs[word]) then return end
      elseif words[word] then
        words[word]()
      elseif tonumber(word) then
        stack:push(tonumber(word))
      elseif tonumber(word, 16) then
        stack:push(tonumber(word, 16))
      else
        write(string.format("undefined: '%s'", tostring(word)))
        return
      end
    end
  end
  return true
end

while true do
  write("> ")
  -- hax
  cx, cy = 3, cy - 1
  local ret = readline()
  if #ret > 0 then
    if eval(ret) then
      write("ok")
    end
  end
end
