-- OpenForth without the space limitations --
-- supports double-quoted strings, with spaces, hackily
-- supports all numbers that lua can `tonumber`
-- skip to line 333 for the FORTH implementation, the other stuff is VT100 setup

-- object-based tty streams.  this is copied from a project of mine.
-- not really designed for this use-case but it works and it's fairly light.

do
  local colors = {
    0x000000,
    0xFF0000,
    0x00FF00,
    0xFFFF00,
    0x00AAFF,
    0xFF00FF,
    0x00FFFF,
    0xFFFFFF
  }

  -- pop characters from the end of a string
  local function pop(str, n)
    local ret = str:sub(1, n)
    local also = str:sub(#ret + 1, -1)
    return also, ret
  end

  local function wrap_cursor(self)
    while self.cx > self.w do
      self.cx, self.cy = self.cx - self.w, self.cy + 1
    end
    while self.cx < 1 do
      self.cx, self.cy = self.w + self.cx, self.cy - 1
    end
    while self.cy < 1 do
      self.cy = self.cy + 1
      self.gpu.copy(1, 1, self.w, self.h, 0, 1)
      self.gpu.fill(1, 1, self.w, 1, " ")
    end
    while self.cy > self.h do
      self.cy = self.cy - 1
      self.gpu.copy(1, 1, self.w, self.h, 0, -1)
      self.gpu.fill(1, self.h, self.w, 1, " ")
    end
  end

  local function writeline(self, rline)
    while #rline > 0 do
      local to_write
      rline, to_write = pop(rline, self.w - self.cx + 1)
      self.gpu.set(self.cx, self.cy, to_write)
      self.cx = self.cx + #to_write
      wrap_cursor(self)
    end
  end

  local function write(self, lines)
    while #lines > 0 do
      local next_nl = lines:find("\n")
      if next_nl then
        local ln
        lines, ln = pop(lines, next_nl - 1)
        lines = lines:sub(2) -- take off the newline
        writeline(self, ln)
        self.cx, self.cy = 1, self.cy + 1
        wrap_cursor(self)
      else
        writeline(self, lines)
        lines = ""
      end
    end
  end

  local commands, control = {}, {}
  local separators = {
    standard = "[",
    control = "("
  }

  -- move cursor up N[=1] lines
  function commands:A(args)
    local n = math.max(args[1] or 0, 1)
    self.cy = self.cy - n
  end

  -- move cursor down N[=1] lines
  function commands:B(args)
    local n = math.max(args[1] or 0, 1)
    self.cy = self.cy + n
  end

  -- move cursor right N[=1] lines
  function commands:C(args)
    local n = math.max(args[1] or 0, 1)
    self.cx = self.cx + n
  end

  -- move cursor left N[=1] lines
  function commands:D(args)
    local n = math.max(args[1] or 0, 1)
    self.cx = self.cx - n
  end

  function commands:G()
    self.cx = 1
  end

  function commands:H(args)
    local y, x = 1, 1
    y = args[1] or y
    x = args[2] or x
    self.cx = x
    self.cy = y
    wrap_cursor(self)
  end

  -- clear a portion of the screen
  function commands:J(args)
    local n = args[1] or 0
    if n == 0 then
      self.gpu.fill(1, self.cy, self.w, self.h, " ")
    elseif n == 1 then
      self.gpu.fill(1, 1, self.w, self.cy, " ")
    elseif n == 2 then
      self.gpu.fill(1, 1, self.w, self.h, " ")
    end
  end
  
  -- clear a portion of the current line
  function commands:K(args)
    local n = args[1] or 0
    if n == 0 then
      self.gpu.fill(self.cx, self.cy, self.w, 1, " ")
    elseif n == 1 then
      self.gpu.fill(1, self.cy, self.cx, 1, " ")
    elseif n == 2 then
      self.gpu.fill(1, self.cy, self.w, 1, " ")
    end
  end

  -- adjust terminal attributes
  function commands:m(args)
    args[1] = args[1] or 0
    for i=1, #args, 1 do
      local n = args[i]
      if n == 0 then
        self.fg = colors[8]
        self.bg = colors[1]
        self.attributes.echo = true
      elseif n == 8 then
        self.attributes.echo = false
      elseif n == 28 then
        self.attributes.echo = true
      elseif n > 29 and n < 38 then
        self.fg = colors[n - 29]
        self.gpu.setForeground(self.fg)
      elseif n > 39 and n < 48 then
        self.bg = colors[n - 39]
        self.gpu.setBackground(self.bg)
      end
    end
  end


  -- adjust more terminal attributes
  function control:c(args)
    args[1] = args[1] or 0
    for i=1, #args, 1 do
      local n = args[i]
      if n == 0 then -- (re)set configuration to sane defaults
        -- echo text that the user has entered
        self.attributes.echo = true
        -- buffer input by line
        self.attributes.line = true
        -- send raw key input data according to the VT100 spec
        self.attributes.raw = false
      -- these numbers aren't random - they're the ASCII codes of the most
      -- reasonable corresponding characters
      elseif n == 82 then
        self.attributes.raw = true
      elseif n == 114 then
        self.attributes.raw = false
      end
    end
  end

  local _stream = {}
  -- This is where most of the heavy lifting happens.  I've attempted to make
  --   this function fairly optimized, but there's only so much one can do given
  --   OpenComputers's call budget limits and wrapped string library.
  function _stream:write(str)
    local gpu = self.gpu
    -- TODO: cursor logic is a bit brute-force currently, there are certain
    -- TODO: scenarios where cursor manipulation is unnecessary
    local c, f, b = gpu.get(self.cx, self.cy)
    gpu.setForeground(b)
    gpu.setBackground(f)
    gpu.set(self.cx, self.cy, c)
    gpu.setForeground(self.fg)
    gpu.setBackground(self.bg)
    while #str > 0 do
      if self.in_esc then
        local esc_end = str:find("[a-zA-Z]")
        if not esc_end then
          self.esc = string.format("%s%s", self.esc, str)
        else
          self.in_esc = false
          local finish
          str, finish = pop(str, esc_end)
          local esc = string.format("%s%s", self.esc, finish)
          self.esc = ""
          local separator, raw_args, code = esc:match("\27([%[%(])([%d;]*)([a-zA-Z])")
          raw_args = raw_args or "0"
          local args = {}
          for arg in raw_args:gmatch("([^;]+)") do
            args[#args + 1] = tonumber(arg) or 0
          end
          if separator == separators.standard and commands[code] then
            commands[code](self, args)
          elseif separator == separators.control and control[code] then
            control[code](self, args)
          end
          wrap_cursor(self)
        end
      else
        local next_esc = str:find("\27")
        if next_esc then
          self.in_esc = true
          self.esc = ""
          local ln
          str, ln = pop(str, next_esc - 1)
          write(self, ln)
        else
          write(self, str)
          str = ""
        end
      end
    end

    c, f, b = gpu.get(self.cx, self.cy)
    gpu.setForeground(b)
    gpu.setBackground(f)
    gpu.set(self.cx, self.cy, c)
    gpu.setForeground(self.fg)
    gpu.setBackground(self.bg)
    return true
  end

  -- TODO: proper line buffering for output
  function _stream:flush()
    return true
  end

  -- aliases of key scan codes to key inputs
  local aliases = {
    [200] = "\27[A", -- up
    [208] = "\27[B", -- down
    [205] = "\27[C", -- right
    [203] = "\27[D", -- left
  }

  -- This function returns a single key press every time it is called.
  function _stream:read_key()
    local signal
    repeat
      signal = table.pack(computer.pullSignal())
    until signal[1] == "key_down" and self.keyboards[signal[2]]
                                  and (signal[3] > 0 or aliases[signal[4]])
    return aliases[signal[4]] or --                                   :)
              (signal[3] > 255 and unicode.char or string.char)(signal[3])
  end

  -- very basic readline function
  function _stream:read()
    local buffer = ""
    while true do
      local char = self:read_key()
      if char == "\8" and #buffer > 0 then
        char = "\27[D \27[D"
        buffer = buffer:sub(1, -2)
      elseif char == "\13" then
        self:write(" ")
        return buffer
      elseif string.byte(char) > 31 then
        buffer = buffer .. char
      else
        char = ""
      end
      self:write(char)
    end
  end

  local function closed()
    return nil, "stream closed"
  end

  function _stream:close()
    self.closed = true
    self.read = closed
    self.write = closed
    self.flush = closed
    self.close = closed
    return true
  end

  local function create_tty(gpu, screen)
    checkArg(1, gpu, "string")
    checkArg(2, screen, "string")
    local proxy = component.proxy(gpu)
    proxy.bind(screen)
    local new = setmetatable({
      attributes = {}, -- used by other things but not directly by this terminal
      keyboards = {}, -- all attached keyboards on terminal initialization
      in_esc = false,
      gpu = proxy,
      esc = "",
      cx = 1,
      cy = 1,
      fg = 0xFFFFFF,
      bg = 0,
    }, {__index = _stream})
    new.w, new.h = proxy.maxResolution()
    proxy.setResolution(new.w, new.h)
    proxy.fill(1, 1, new.w, new.h, " ")
    for _, keyboard in pairs(component.invoke(screen, "getKeyboards")) do
      new.keyboards[keyboard] = true
    end
    return new
  end

  _G.iostream = create_tty(component.list("gpu", true)(),
                            component.list("screen", true)())
end

-- The actual FORTH implementation starts now.

iostream:write("\27[32m*\27[37m Building component tree...")
local ctree = {}
for a, t in component.list() do
  ctree[#ctree + 1] = a
end
iostream:write("done\n")

iostream:write("\27[32m*\27[37m Setting up stacks")
-- parameter stack
local stack = {}
function stack:push(x)
  local n = #stack
  stack[n + 1] = x
  return true
end

function stack:pop()
  local n = #stack
  if n == 0 then
    error("stack underflow")
  end
  local x = stack[n]
  stack[n] = nil
  return x
end

-- loop control stack
local loop_stack = {
  push = function(self, v)
    self[#self + 1] = v
  end,
  pop = function(self)
    local n = #self
    local x = self[n]
    if not x then
      error("loop stack underflow")
    end
    self[n] = nil
    return x
  end,
}
iostream:write("...done\n")

iostream:write("\27[32m*\27[37m Registering base words...")
-- there are some words which aren't implemented through this table, but which
-- are still registered here so they'll show up in `words`.
-- TODO: maybe rework the implementation so they are? i.e. have loop_stack
-- provided as an argument.
local function bland() end
local words = {["do"] = bland, ["loop"] = bland}
local jump_then, jump_else, in_def
words["."] = function() iostream:write(tostring(stack:pop()):gsub("\\27", "\27")
                                                                  .. " ") end
words["<"] = function() stack:push(stack:pop() < stack:pop()) end
words[">"] = function() stack:push(stack:pop() > stack:pop()) end
words["="] = function() stack:push(stack:pop() == stack:pop()) end
words["+"] = function() local n1,n2=stack:pop(),stack:pop()stack:push(n1+n2) end
words["-"] = function() local n1,n2=stack:pop(),stack:pop()stack:push(n2-n1) end
words["*"] = function() local n1,n2=stack:pop(),stack:pop()stack:push(n1*n2) end
words["/"] = function() local n1,n2=stack:pop(),stack:pop()stack:push(n2/n1) end
words.mod = function() local n1,n2=stack:pop(),stack:pop()stack:push(n2%n1) end
words[":"] = function() if in_def then return nil, "unexpected ':'" end
                          in_def = true end
words[";"] = function() if not in_def then return nil, "unexpected ';'" end
                          in_def = false end
words["i"] = function() local n = loop_stack:pop()
                        loop_stack:push(n) stack:push(n) end
words["cr"] = function() iostream:write("\n") end
words["dup"] = function() local n = stack:pop() stack:push(n) stack:push(n) end
-- TODO: nested if/then/else will probably break, so may have to change these to
-- TODO: nest levels rather than booleans
words["if"] = function() if not stack:pop() then jump_else = true end end
words["else"] = function() if not jump_else then jump_then = true
                                            else jump_else = false end end
words["then"] = function() jump_then = false jump_else = false end
words["drop"] = function() stack:pop() end
words["swap"] = function() local x,y=stack:pop(),stack:pop()
                                                  stack:push(x)stack:push(y) end
words["words"] = function() iostream:write("\n") for k,v in pairs(words) do
                                                iostream:write(k .. " ") end end
iostream:write("Registering extension words...")
words["power"] = function() local n = stack:pop() computer.shutdown(n == 1) end
words["clist"] = function() for i=1, #ctree, 1 do iostream:write(
                string.format("%d=%s=%s\n",i,ctree[i],component.type(ctree[i]))
                                                                       ) end end

-- component.invoke wrapper for the FORTH interpreter
words["invoke"] = function()
  -- ARGS... NARGS METHOD N invoke
  local n, method, nargs = stack:pop(), stack:pop(), stack:pop()
  local args = {}
  for i=1, nargs, 1 do
    table.insert(args, stack:pop())
  end
  local result = table.pack(component.invoke(ctree[n], method,
                                                      table.unpack(args)))
  for i=1, #result, 1 do
    if type(result[i]) == "table" then
      for n=1, #result[i], 1 do
        stack:push(result[i][n])
      end
      stack:push(#result[i])
    else
      stack:push(result[i])
    end
  end
end
words["memfree"] = function()
  stack:push(computer.freeMemory())
end
words["memtotal"] = function()
  stack:push(computer.totalMemory())
end
words["read"] = function()
  local n = iostream:read()
  stack:push(tonumber(n) or n)
end
words["fread"] = function()
  -- copied from eval
  local fs, file = stack:pop(), stack:pop()
  local comp = assert(ctree[fs] and component.type(ctree[fs]) == "filesystem"
            and ctree[fs], -- this is so we can still have the fs address
                           -- because WEIRDNESS
              "specified component is not a filesystem or component not found")
  local handle = assert(component.invoke(comp, "open", file, "r"))
  local data = ""
  repeat
    local chunk = component.invoke(comp, "read", handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  component.invoke(comp, "close", handle)
  stack:push(data)
end
words["write"] = "."
words["split"] = function()
  local item = stack:pop()
  if type(item) == "number" then
    stack:push(item)
    return
  end
  local n = 0
  for word in item:reverse():gmatch("[^ ]+") do
    stack:push(tonumber(word:reverse()) or word:reverse())
    n = n + 1
  end
  stack:push(n)
end
-- load a FORTH file from a fs and execute it
local evaluate
words["eval"] = function()
  local fs, file = stack:pop(), stack:pop()
  local comp = assert(ctree[fs] and component.type(ctree[fs]) == "filesystem"
            and ctree[fs], -- this is so we can still have the fs address
                           -- because WEIRDNESS
              "specified component is not a filesystem or component not found")
  local handle = assert(component.invoke(comp, "open", file, "r"))
  local data = ""
  repeat
    local chunk = component.invoke(comp, "read", handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  component.invoke(comp, "close", handle)
  if file:match("%.lua$") then
    return assert(load(data, "=" .. file, "bt", _G))()
  end
  for line in data:gmatch("[^\n]+") do
    evaluate(line)
  end
end

words["beep"] = function()local h,l=stack:pop(),stack:pop()computer.beep(h,l)end
words["source"] = function()local w = stack:pop()iostream:write(tostring(words[w]).."\n")end
iostream:write("done\n")

local function call_word(word)
  if type(word) == "string" then
    word = word:lower()
  end
  if jump_else and word ~= "else" and word ~= "then" then return true end
  if jump_then then if word ~= "then" then return true end end
  if in_def and word ~= ";" and word ~= ":" then
    if type(in_def) == "boolean" then
      in_def = word
      words[word] = ""
    else
      words[in_def] = words[in_def] .. " " .. word
    end
    return true
  end
  if word:match("^(%.)\" (.+)\"$") then
    local str = word:match("%.\" (.+)\"$")
    stack:push(str)
    return call_word(".")
  end
  if not words[word] then
    return nil, word .. ": unrecognized word"
  end
  if type(words[word]) == "string" then
    return evaluate(words[word])
  else
    local ret, err = words[word]()
    return not err, err -- :^)
  end
  return true
end

local function split_words(line)
  local words = {}
  local in_str = false
  local in_cmt = false
  local word = ""
  for char in line:gmatch(".") do
    if not in_cmt and not in_str then
      if char == '"' then
        in_str = true
        word = word .. char
      elseif char == "(" then
        in_cmt = true
      elseif char == "\\" then -- \ comments out the rest of the line AIUI
        break
      elseif char == " " then
        if #word > 0 then
          words[#words + 1] = word
          word = ""
        end
      else
        word = word .. char
      end
    elseif in_cmt then
      if char == ")" then
        in_cmt = false
      end
    elseif in_str then
      if char == '"' then
        in_str = false
        words[#words + 1] = string.format("%s\"", word)
        word = ""
      else
        word = word .. char
      end
    end
  end
  if #word > 0 then
    words[#words + 1] = word
  end
  return words
end

evaluate = function(line)
  local tokens, i, do_loc = split_words(line), 1
  while tokens[i] do
    local word = tokens[i]
    word = tonumber(word) or word
    if (not in_def) and (type(word) == "number" or word:match("^\"(.+)\"$")) then
      if type(word) == "string" then
        stack:push(word:match("^\"(.+)\"$"))
      else
        stack:push(word)
      end
    elseif (not in_def) and (word == "do" or word == "loop") then
      if word == "do" then
        do_loc = i
        local index, limit = stack:pop(), stack:pop()
        loop_stack:push(limit)
        loop_stack:push(index)
      elseif word == "loop" then
        local index, limit = loop_stack:pop(), loop_stack:pop()
        if index + 1 < limit then
          i = do_loc
          index = index + 1
          loop_stack:push(limit)
          loop_stack:push(index)
        end
      end
    else
      local ok, err = call_word(word)
      if not ok then
        return nil, err
      end
    end
    i = i + 1
  end
  return true
end

iostream:write("\27[34m*\27[37m Welcome to \27[33mOpen Forth 2.0.7\27[37m\n")
evaluate("0.1 260 beep 0.1 330 beep 0.1 392 beep 0.5 523 beep")

while true do
  local x = iostream:read()
  local ok, ret, err = pcall(evaluate, x)
  if not ok then
    iostream:write("\27[31m" .. ret .. "\27[37m\n")
  elseif not ret then
    iostream:write("\27[31m" .. err .. "\27[37m\n")
  elseif in_def then
    iostream:write("\27[31mdef close expected but not found\27[37m\n")
    words[in_def] = nil
    in_def = false
  else
    iostream:write("\27[34mOK\27[37m\n")
  end
end
