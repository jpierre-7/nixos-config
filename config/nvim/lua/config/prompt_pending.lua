-- The pending call of the prompt pane (config/prompt.lua): the tool call Claude is blocked on,
-- drawn for the viewer from the transcript, and the numbered options of the dialog
-- asking about it, read off Claude's screen so an answer is checked before it's sent.
-- Claude can hold a call back from the transcript until it's answered, so the dialog as
-- its screen shows it stands in until then.
local M = {}

-- A fence longer than any backtick run in `lines`, so their own fences can't close it.
local function fenced(lang, lines)
  local longest = 2
  for _, line in ipairs(lines) do
    for run in line:gmatch("`+") do
      longest = math.max(longest, #run)
    end
  end
  local fence = ("`"):rep(longest + 1)
  local out = { fence .. lang }
  vim.list_extend(out, lines)
  table.insert(out, fence)
  return out
end

local function split(text)
  return vim.split(type(text) == "string" and text or "", "\n", { plain = true })
end

-- old → new as diff lines. A whole file keeps its hunk headers; an Edit's fragment is
-- shown whole, its line numbers meaning nothing outside it.
local function diff(old, new, whole)
  old, new = type(old) == "string" and old or "", type(new) == "string" and new or ""
  local function nl(s)
    return (s == "" or s:sub(-1) == "\n") and s or s .. "\n"
  end
  local text = vim.diff(nl(old), nl(new), whole and {} or { ctxlen = 1e6 }) or ""
  local lines = {}
  for _, line in ipairs(split(text)) do
    if line ~= "" and (whole or not line:find("^@@")) and not line:find("^\\ No newline") then
      table.insert(lines, line)
    end
  end
  return #lines > 0 and lines or { " (no change)" }
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path, "b")
  return ok and table.concat(lines, "\n") or nil
end

local function add(out, lines)
  vim.list_extend(out, lines)
  table.insert(out, "")
end

local function path_of(input)
  local path = type(input.file_path) == "string" and input.file_path or "?"
  return "`" .. vim.fn.fnamemodify(path, ":~:.") .. "`"
end

---@alias prompt.Option { n: integer, label: string }

-- A rule Claude draws across its screen; a pattern's [─╌] would match bytes of other glyphs.
local function rule(line)
  return line:find("^%s*─") or line:find("^%s*╌")
end
---@alias prompt.Call { id: string, name?: string, input?: table, screen?: string[] }

-- The call as markdown: Bash's command, an edit's diff, the questions, the plan, or
-- any other tool's input pretty-printed; a call known only from the screen, its dialog
-- as shown there. The dialog's options follow, if read.
---@param call prompt.Call
---@param options? prompt.Option[]
---@return string[]
function M.render(call, options)
  local input = type(call.input) == "table" and call.input or {}
  local name = call.name
  local out = {}
  if call.screen then
    -- Plan mode's dialog names the plan's file rather than showing it.
    local plan = table.concat(call.screen, "\n"):match("/plans/([%w%-_.]+%.md)")
    local file = plan and vim.fn.glob("~/.claude/plans/" .. plan, false, true)[1]
    local text = file and read_file(file)
    if text then
      add(out, { "## Approve the plan" })
      add(out, split(vim.trim(text)))
    end
    -- A diff on screen is numbered lines marked -, + or blank: fenced as a diff, unnumbered.
    add(out, { "## Claude asks" })
    local run, kind = {}, nil
    local function flush()
      if #run > 0 then
        add(out, fenced(kind, run))
      end
      run = {}
    end
    for _, line in ipairs(call.screen) do
      local mark = line:match("^%s*%d+ ([-+ ].*)$")
      local this = mark and "diff" or "text"
      if this ~= kind then
        flush()
        kind = this
      end
      table.insert(run, mark or line)
    end
    flush()
    return out
  elseif name == "Bash" then
    add(out, { "## Run a command" .. (type(input.description) == "string" and (": " .. input.description) or "") })
    add(out, fenced("sh", split(input.command)))
  elseif name == "Edit" or name == "MultiEdit" then
    add(out, { "## Edit " .. path_of(input) })
    local edits = name == "MultiEdit" and type(input.edits) == "table" and input.edits or { input }
    for _, edit in ipairs(edits) do
      if edit.replace_all == true then
        add(out, { "_every occurrence_" })
      end
      add(out, fenced("diff", diff(edit.old_string, edit.new_string)))
    end
  elseif name == "Write" then
    local old = type(input.file_path) == "string" and read_file(input.file_path)
    add(out, { (old and "## Overwrite " or "## Create ") .. path_of(input) })
    add(out, fenced("diff", diff(old or "", input.content, true)))
  elseif name == "AskUserQuestion" then
    for _, q in ipairs(type(input.questions) == "table" and input.questions or {}) do
      local header = type(q.header) == "string" and (q.header .. ": ") or ""
      add(out, { "## " .. header .. (type(q.question) == "string" and q.question or "") })
      local items = {}
      for i, option in ipairs(type(q.options) == "table" and q.options or {}) do
        local desc = type(option.description) == "string" and (" — " .. option.description) or ""
        table.insert(items, ("%d. **%s**%s"):format(i, tostring(option.label), desc))
      end
      if q.multiSelect == true then
        table.insert(items, "_several can be picked_")
      end
      add(out, items)
    end
  elseif name == "ExitPlanMode" then
    add(out, { "## Approve the plan" })
    add(out, split(input.plan))
  else
    add(out, { "## " .. name:gsub("^mcp__(.-)__", "%1 · ") })
    add(out, fenced("lua", split(vim.inspect(input))))
  end
  if options and name ~= "AskUserQuestion" then
    add(out, { "## Claude's options" })
    add(
      out,
      vim.tbl_map(function(option)
        return ("%d. %s"):format(option.n, option.label)
      end, options)
    )
  end
  return out
end

-- The dialog's numbered options, from Claude's screen text: the run of `N. label`
-- lines at its bottom, under a footer of at most three lines, numbered 1..n without
-- a gap, with rules between and wrapped lines, joined to the option above them. nil if
-- that isn't what's there.
---@param screen string
---@return prompt.Option[]? options, integer? first the line option 1 is on
function M.options(screen)
  local lines = vim.split(screen, "\n", { plain = true })
  local found, skipped, between, wrapped = {}, 0, 0, {}
  for i = #lines, 1, -1 do
    local line = lines[i]
    -- the cursor, marking the highlighted option; a pattern's `?` would take one byte of it
    local n, label = line:gsub("❯", " ", 1):match("^%s*(%d+)%.%s+(.-)%s*$")
    if n then
      n = tonumber(n)
      if #found > 0 and n ~= found[1].n - 1 then
        return nil
      end
      -- an option's wrapped lines follow it, between it and the next
      table.insert(wrapped, 1, label)
      table.insert(found, 1, { n = n, label = table.concat(wrapped, " ") })
      between, wrapped = 0, {}
      if n == 1 then
        return found, i
      end
    elseif #found == 0 then
      if vim.trim(line) ~= "" then
        skipped = skipped + 1
        if skipped > 3 then
          return nil
        end
      end
    else
      between = between + 1
      if between > 3 then
        return nil
      elseif vim.trim(line) ~= "" and not rule(line) then
        table.insert(wrapped, 1, vim.trim(line))
      end
    end
  end
  return nil
end

-- The dialog on Claude's screen, from the rule it opens with down to its last line,
-- unindented. Rules within and under it (one can carry the session's name) are blanked
-- so they don't wrap. nil if there are no options to find it by.
---@param screen string
---@return string[]?
function M.dialog(screen)
  local options, first = M.options(screen)
  if not options then
    return nil
  end
  local lines = vim.split(screen, "\n", { plain = true })
  local top = 1
  for i = first, 1, -1 do
    if lines[i]:find("^%s*─") then
      top = i + 1
      break
    end
  end
  local body = vim.tbl_map(function(line)
    return rule(line) and "" or line
  end, vim.list_slice(lines, top))
  while #body > 0 and vim.trim(body[#body]) == "" do
    table.remove(body)
  end
  local indent = math.huge
  for _, line in ipairs(body) do
    if vim.trim(line) ~= "" then
      indent = math.min(indent, #line:match("^%s*"))
    end
  end
  return vim.tbl_map(function(line)
    return vim.trim(line) == "" and "" or line:sub(indent + 1):gsub("%s+$", "")
  end, body)
end

-- Whether the dialog on screen asks about `call`: its command, file, question or plan
-- shows in it, or for any other tool its name. A call that's running unasked, beside
-- the one asked about, doesn't.
---@param call prompt.Call
---@param dialog string[] from M.dialog
function M.asks_about(call, dialog)
  local input = type(call.input) == "table" and call.input or {}
  local text = table.concat(dialog, "\n")
  local function shows(s)
    s = type(s) == "string" and vim.trim(s:match("^[^\n]*")) or ""
    return s ~= "" and text:find(vim.fn.strcharpart(s, 0, 20), 1, true) ~= nil
  end
  if call.name == "Bash" then
    return shows(input.command)
  elseif type(input.file_path) == "string" or type(input.notebook_path) == "string" then
    return shows(vim.fs.basename(input.file_path or input.notebook_path))
  elseif call.name == "AskUserQuestion" then
    return shows(vim.tbl_get(input, "questions", 1, "question"))
  elseif call.name == "ExitPlanMode" then
    return text:find("plan", 1, true) ~= nil
  end
  return shows(call.name:match("([^_]+)$"))
end

-- Options that only open a text field or a chat: answered in Claude's own pane.
local function free_text(label)
  return label:find("^Type something") or label:find("^Chat about this") or label:find("^Tell Claude")
end

-- The keys answering `choice` in a dialog showing `options`, or why not: "yes" is
-- option 1 and "always" option 2, each only if it reads Yes; "no" is Esc; a number
-- is that option.
---@param options prompt.Option[]
---@param choice "yes"|"always"|"no"|integer
---@return string? key, string? err
function M.key(options, choice)
  if choice == "no" then
    return "esc"
  end
  local n = choice == "yes" and 1 or choice == "always" and 2 or choice
  local option = options[n]
  if not option then
    return nil, ("Claude's dialog has no option %d"):format(n)
  elseif type(choice) == "string" and not option.label:find("^Yes") then
    return nil, ("Claude's option %d is “%s”, not a yes"):format(n, option.label)
  elseif free_text(option.label) then
    return nil, ("“%s” takes text: answer it in Claude's pane (<leader>ac)"):format(option.label)
  end
  return tostring(n)
end

return M
