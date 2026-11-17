-- Prompt pane: a scratch buffer for writing to the Claude agent in the same herdr tab,
-- with Claude's last reply rendered in a read-only window above it, so you can read,
-- scroll and quote the reply while composing. Opened by herdr's `prefix+i`
-- (config/herdr/config.toml) through claude-prompt (config/claude/prompt-pane.sh).
-- Ported from github.com/HefKer/dots (nvim/.config/nvim/lua/config/prompt.lua), core only.
local M = {}

local ns = vim.api.nvim_create_namespace("claude_prompt_quote")

-- One prompt pane per nvim, so its state is module-wide.
local state = {
  prompt = { buf = nil, win = nil },
  viewer = { buf = nil, win = nil },
  path = nil, -- transcript being read
  offset = 0, -- bytes of it already parsed
  partial = "", -- a line still being written when last read
  replies = {}, -- finished replies, oldest first
  index = 0, -- the one shown; 0 when there are none
  watcher = nil,
  timer = nil,
  poll = nil,
}

-- herdr prints errors as JSON on stderr; fall back to the raw text for anything else.
local function herdr_error(result)
  local ok, decoded = pcall(vim.json.decode, result.stderr)
  return ok and vim.tbl_get(decoded, "error", "message") or vim.trim(result.stderr)
end

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Claude prompt" })
end

-- The pane's session, from Claude's own record (~/.claude/sessions/<pid>.json) of the
-- process running in it: herdr's agent_session can stay stale after a fresh Claude
-- starts in the same pane. herdr's id is the fallback, for a Claude without the record.
---@param agent table a pane from `herdr pane list`
local function claude_session(agent)
  local found, started = nil, -1
  for _, file in ipairs(vim.fn.glob("~/.claude/sessions/*.json", false, true)) do
    local fh = io.open("/proc/" .. vim.fn.fnamemodify(file, ":t:r") .. "/environ", "rb")
    local env = fh and fh:read("*a")
    if fh then
      fh:close()
    end
    if env and ("\0" .. env):find("\0HERDR_PANE_ID=" .. agent.pane_id .. "\0", 1, true) then
      local ok, record = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
      end)
      if ok and type(record) == "table" and record.sessionId and (record.startedAt or 0) > started then
        found, started = record.sessionId, record.startedAt or 0
      end
    end
  end
  return found or vim.tbl_get(agent, "agent_session", "value")
end

---@param listed vim.SystemCompleted output of `herdr pane list`
local function pick_agent(listed)
  if listed.code ~= 0 then
    return nil, herdr_error(listed)
  end
  local agents = vim.tbl_filter(function(pane)
    return pane.tab_id == vim.env.HERDR_TAB_ID and pane.agent == "claude"
  end, vim.json.decode(listed.stdout).result.panes)
  if #agents ~= 1 then
    return nil, ("Expected one Claude pane in this tab, found %d"):format(#agents)
  end
  agents[1].session = claude_session(agents[1])
  return agents[1]
end

local function list_panes()
  return { "herdr", "pane", "list", "--workspace", vim.env.HERDR_WORKSPACE_ID }
end

-- Looked up on every send, not at open, so restarting Claude doesn't strand the pane.
function M.find_agent()
  return pick_agent(vim.system(list_panes(), { text = true }):wait())
end

---@return string? path of the agent's session transcript
---@return string? err
local function session_path(agent, err)
  local session = agent and agent.session
  if not session then
    return nil, err or "Claude has no session yet"
  end
  local path = vim.fn.glob("~/.claude/projects/*/" .. session .. ".jsonl", false, true)[1]
  return path, not path and "No transcript for this session yet" or nil
end

function M.transcript()
  return session_path(M.find_agent())
end

-- The same, without blocking: for the background check, so typing never stalls on herdr.
---@param cb fun(path?: string, err?: string)
function M.transcript_async(cb)
  vim.system(
    list_panes(),
    { text = true },
    vim.schedule_wrap(function(listed)
      cb(session_path(pick_agent(listed)))
    end)
  )
end

------------------------------------------------------------------------------
-- Replies, read from the transcript rather than the screen: that's the exact
-- markdown, unwrapped and complete. Only a turn's final answer counts (the text
-- Claude ends the turn with, stop_reason end_turn), so the narration it writes
-- between tool calls never replaces the reply you're reading.

-- Parses whatever was appended since the last read, so a long session isn't
-- re-read on every write. Returns whether a new reply arrived.
local function read_new()
  local fh = state.path and io.open(state.path, "rb")
  if not fh then
    return false
  end
  fh:seek("set", state.offset)
  local chunk = fh:read("*a") or ""
  fh:close()
  state.offset = state.offset + #chunk
  local text = state.partial .. chunk
  local last_nl = text:find("\n[^\n]*$")
  state.partial = last_nl and text:sub(last_nl + 1) or text
  text = last_nl and text:sub(1, last_nl) or ""

  local before, last_id = #state.replies, state.last_id
  for line in text:gmatch("[^\n]+") do
    -- Cheap filter first: Claude Code writes compact JSON, and most lines are tool output.
    if line:find('"stop_reason":"end_turn"', 1, true) then
      local ok, entry = pcall(vim.json.decode, line)
      if ok and entry.type == "assistant" and entry.isSidechain ~= true then
        local texts = {}
        for _, block in ipairs(entry.message.content or {}) do
          if block.type == "text" then
            table.insert(texts, block.text)
          end
        end
        if #texts > 0 then
          local body = table.concat(texts, "\n")
          -- A message's content blocks arrive as separate entries; join them.
          if entry.message.id and entry.message.id == last_id then
            state.replies[#state.replies] = state.replies[#state.replies] .. "\n" .. body
          else
            table.insert(state.replies, body)
          end
          last_id = entry.message.id
        end
      end
    end
  end
  state.last_id = last_id
  return #state.replies > before
end

------------------------------------------------------------------------------
-- Viewer

local function viewer_valid()
  return state.viewer.win and vim.api.nvim_win_is_valid(state.viewer.win)
end

local function set_winbars()
  if viewer_valid() then
    local title = state.index > 0 and ("Claude · reply %d/%d"):format(state.index, #state.replies)
      or "Claude · no reply yet"
    vim.wo[state.viewer.win][0].winbar = "%#WinBar# 󰚩 "
      .. title
      .. "%=%#Comment#[r ]r older/newer · <CR> quote "
  end
  if state.prompt.win and vim.api.nvim_win_is_valid(state.prompt.win) then
    vim.wo[state.prompt.win][0].winbar =
      "%#WinBar# 󰏫 Prompt%=%#Comment#M-j/k M-u/d scroll reply · <leader>aq quote all · <leader>as send "
  end
end

---@param index integer
---@param message? string shown instead of a reply
local function show(index, message)
  local buf = state.viewer.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  state.index = index
  local text = message or state.replies[index] or "_No finished reply in this session yet._"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
  vim.bo[buf].modifiable = false
  if viewer_valid() then
    vim.api.nvim_win_set_cursor(state.viewer.win, { 1, 0 })
  end
  set_winbars()
end

-- Picks up new replies. Following the newest unless you've stepped back to an older one.
local function refresh()
  local following = state.index == #state.replies
  if read_new() and following then
    show(#state.replies)
  else
    set_winbars()
  end
end

-- Claude restarted or /clear'd: start over on the new transcript.
local function attach_to(path, err)
  if path == state.path then
    return refresh()
  end
  if state.watcher then
    state.watcher:stop()
  end
  state.path, state.offset, state.partial, state.replies, state.last_id = path, 0, "", {}, nil
  if not path then
    return show(0, "_" .. err .. "._")
  end
  read_new()
  show(#state.replies)

  -- libuv often reports only the first of several edits, so re-arm after each one.
  state.timer = state.timer or vim.uv.new_timer()
  state.watcher = state.watcher or vim.uv.new_fs_event()
  local function arm()
    state.watcher:start(state.path, {}, function()
      state.watcher:stop()
      state.timer:start(
        150,
        0,
        vim.schedule_wrap(function()
          refresh()
          arm()
        end)
      )
    end)
  end
  arm()
end

local function attach()
  attach_to(M.transcript())
end

-- The transcript only exists once a session's first message is written, and
-- /clear or a restarted Claude moves to a new one, neither of which the file
-- watcher can see. So check the agent's session every few seconds, and re-read
-- too, in case libuv dropped an event. A failed lookup keeps the reply shown.
local function start_polling()
  state.poll = state.poll or vim.uv.new_timer()
  state.poll:start(
    2000,
    2000,
    vim.schedule_wrap(function()
      M.transcript_async(function(path)
        if path then
          attach_to(path)
        end
      end)
    end)
  )
end

local function step(delta)
  local target = state.index + delta
  if target >= 1 and target <= #state.replies then
    show(target)
  end
end

-- Scrolls the viewer from the prompt window, in normal or insert mode alike.
local function scroll(keys)
  return function()
    if viewer_valid() then
      vim.api.nvim_win_call(state.viewer.win, function()
        vim.cmd.normal({ vim.keycode(keys), bang = true })
      end)
    end
  end
end

------------------------------------------------------------------------------
-- Quoting

local function quote_lines(lines)
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end
  return vim.tbl_map(function(line)
    return vim.trim("> " .. line)
  end, lines)
end

-- Puts quoted lines at the end of the prompt, a blank line after any text above,
-- leaves an empty line under them to answer on, and goes there in insert mode.
local function insert_quote(lines)
  local buf, win = state.prompt.buf, state.prompt.win
  if #lines == 0 or not (buf and win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local last = #all
  while last > 0 and vim.trim(all[last]) == "" do
    last = last - 1
  end
  local block = vim.list_extend(last > 0 and { "" } or {}, lines)
  table.insert(block, "")
  vim.api.nvim_buf_set_lines(buf, last, -1, false, block)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { last + #block, 0 })
  vim.cmd.startinsert()
end

-- The markdown block under the viewer's cursor: a list item, code block, table or
-- quote as a whole, otherwise the paragraph or heading.
local function block_at_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  pcall(function()
    vim.treesitter.get_parser(0):parse()
  end)
  local ok, node = pcall(vim.treesitter.get_node, { pos = { row, 0 }, ignore_injections = true })
  local whole =
    { list_item = true, fenced_code_block = true, indented_code_block = true, pipe_table = true, block_quote = true }
  local fallback
  while ok and node do
    local kind = node:type()
    if whole[kind] then
      fallback = node
      break
    elseif not fallback and (kind == "paragraph" or kind:match("heading$")) then
      fallback = node
    elseif kind == "section" or kind == "document" then
      break
    end
    node = node:parent()
  end
  if not fallback then
    return vim.api.nvim_buf_get_lines(0, row, row + 1, false)
  end
  local srow, _, erow, ecol = fallback:range()
  return vim.api.nvim_buf_get_lines(0, srow, ecol == 0 and erow or erow + 1, false)
end

local function quote_block()
  insert_quote(quote_lines(block_at_cursor()))
end

local function quote_selection()
  local from, to = vim.fn.line("v"), vim.fn.line(".")
  vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
  insert_quote(quote_lines(vim.api.nvim_buf_get_lines(0, math.min(from, to) - 1, math.max(from, to), false)))
end

-- The whole reply shown, for replying between its lines and deleting what doesn't
-- need an answer.
local function quote_all()
  local reply = state.replies[state.index]
  if not reply then
    return notify_error("No reply to quote yet")
  end
  insert_quote(quote_lines(vim.split(reply, "\n")))
end

-- Undoes the quotes once the replies are written: drops every quoted line, keeping
-- only the text typed between them. The blank lines the quotes left between replies
-- are squeezed to one, so the comments don't arrive spread over gaps.
local function unquote()
  local kept = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local blank = vim.trim(line) == ""
    if not line:match("^%s*>") and not (blank and (#kept == 0 or kept[#kept] == "")) then
      table.insert(kept, blank and "" or line)
    end
  end
  if kept[#kept] == "" then
    table.remove(kept)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, kept)
end

-- Quoted lines in the prompt are dimmed, so they read as context, not as what you
-- wrote. Claude still receives plain `> ` markdown.
local function dim_quotes(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^%s*>") then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #line, hl_group = "ClaudePromptQuote", priority = 110 })
    end
  end
end

local function set_quote_hl()
  local fg = vim.api.nvim_get_hl(0, { name = "NonText", link = false }).fg
  vim.api.nvim_set_hl(0, "ClaudePromptQuote", { fg = fg })
end

------------------------------------------------------------------------------
-- Sending

local function send()
  local buf = state.prompt.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
  if text == "" then
    return
  end
  local agent, err = M.find_agent()
  if agent then
    -- Claude only runs a leading /skill outside a long paste, which it reads as plain
    -- text, so that word goes in as its own paste. Bracketed by hand, since `agent prompt`
    -- is the only paste herdr offers and it submits. A blocked agent would be left with
    -- the word in its input, so that case falls through for `agent prompt` to refuse.
    local skill, rest = text:match("^(/[%w:_-]+)%s+(.+)$")
    if skill and agent.agent_status ~= "blocked" then
      vim.system({ "herdr", "pane", "send-text", agent.pane_id, "\27[200~" .. skill .. " \27[201~" }):wait()
      text = rest
    end
    -- `agent prompt` rather than `pane send-text`: it pastes, so newlines don't submit
    -- early and Claude's vim mode can't run the text, and it refuses a blocked agent.
    local sent = vim.system({ "herdr", "agent", "prompt", agent.pane_id, text }, { text = true }):wait()
    err = sent.code ~= 0 and herdr_error(sent) or nil
  end
  if err then
    return notify_error(err)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  -- The session may have changed since open (a restarted Claude); follow it.
  attach()
end

------------------------------------------------------------------------------
-- Opening

local function open_viewer(prompt_win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  -- snacks' smooth scroll animates the cursor too, so a quote taken mid-scroll
  -- would grab whatever line it was passing, and quick Alt+j presses get lost.
  vim.b[buf].snacks_scroll = false
  local height = math.floor(vim.o.lines * 0.62)
  local win = vim.api.nvim_open_win(buf, false, { split = "above", win = prompt_win, height = height })
  -- Window-local ([0]), so they don't leak into windows split from this one.
  for opt, val in pairs({ signcolumn = "no", spell = false, wrap = true, linebreak = true }) do
    vim.wo[win][0][opt] = val
  end
  state.viewer = { buf = buf, win = win }

  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("n", "<CR>", quote_block, "Quote Block into Prompt")
  map("x", "<CR>", quote_selection, "Quote Selection into Prompt")
  map("n", "[r", function()
    step(-1)
  end, "Older Reply")
  map("n", "]r", function()
    step(1)
  end, "Newer Reply")
  map("n", "R", attach, "Reload Reply")
  map("n", "<leader>as", send, "Send Prompt to Claude")
  -- The reply can't be edited, so insert keys move to the prompt and run there.
  for _, key in ipairs({ "i", "a", "I", "A", "o", "O" }) do
    map("n", key, function()
      local win = state.prompt.win
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_feedkeys(key, "n", false)
      end
    end, "Write in Prompt")
  end
end

-- Runs in the .md file claude-prompt opens, not an empty buffer: a file argument is
-- what skips the dashboard and makes LazyVim load its markdown autocmds in time.
function M.open()
  vim.fn.delete(vim.api.nvim_buf_get_name(0))
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  state.prompt = { buf = buf, win = win }
  vim.wo[win][0].winfixheight = true

  -- Buffer-local, so the claudecode extra's global <leader>a binds stay as they are.
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("n", "<leader>as", send, "Send Prompt to Claude")
  map("n", "<leader>aq", quote_all, "Quote Claude's Whole Reply")
  map("n", "<leader>aQ", unquote, "Strip Quoted Lines")
  map("n", "[r", function()
    step(-1)
  end, "Older Reply")
  map("n", "]r", function()
    step(1)
  end, "Newer Reply")
  -- Alt+j/k/u/d scroll the reply from the prompt, even in insert mode.
  for lhs, keys in pairs({
    ["<M-j>"] = "<C-e>",
    ["<M-k>"] = "<C-y>",
    ["<M-d>"] = "<C-d>",
    ["<M-u>"] = "<C-u>",
    ["<M-g>"] = "gg",
    ["<M-G>"] = "G",
  }) do
    map({ "n", "i" }, lhs, scroll(keys), "Scroll Claude's Reply")
  end

  set_quote_hl()
  local group = vim.api.nvim_create_augroup("claude_prompt", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_quote_hl })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      dim_quotes(buf)
    end,
  })
  -- :q in the prompt closes the pane, not just the prompt window.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = buf,
    callback = function()
      if viewer_valid() then
        vim.api.nvim_win_close(state.viewer.win, true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = attach })

  open_viewer(win)
  attach()
  start_polling()
  dim_quotes(buf)
  vim.cmd.normal({ "G", bang = true })
  vim.cmd.startinsert({ bang = true })
end

return M
