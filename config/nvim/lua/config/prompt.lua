-- Prompt pane: a scratch buffer for writing to the Claude agent in the same herdr tab,
-- with Claude's last reply rendered in a read-only window above it, so you can read,
-- scroll and quote the reply while composing. Opened by herdr's `prefix+i`
-- (config/herdr/config.toml) through claude-prompt (config/claude/prompt-pane.sh).
-- Ported from github.com/HefKer/dots (nvim/.config/nvim/lua/config/prompt.lua), without
-- its table drawing, task list, statusline bar, history, templates, interrupt and
-- permission-mode cycling. The helpers are in config/prompt_*.lua.
local M = {}

local queue = require("config.prompt_queue")
local handoff = require("config.prompt_handoff")
local pending = require("config.prompt_pending")

local ns = vim.api.nvim_create_namespace("claude_prompt_quote")

-- One prompt pane per nvim, so its state is module-wide.
local state = {
  prompt = { buf = nil, win = nil },
  viewer = { buf = nil, win = nil },
  path = nil, -- transcript being read
  offset = 0, -- bytes of it already parsed
  partial = "", -- a line still being written when last read
  replies = {}, -- finished replies, oldest first; those with no prompt of yours between are one
  prompted = true, -- whether you've written to Claude since its last reply
  session = nil, -- Claude's session id, last seen
  status = nil, -- herdr's agent_status for Claude, last seen
  cwd = nil, -- Claude's working directory, last seen
  draft = nil, -- file the prompt is saved to
  index = 0, -- the one shown; 0 when there are none
  view = "reply", -- or "pending", the call Claude is blocked on
  calls = {}, -- tool calls made this turn with no result yet, oldest first (config.prompt_pending)
  answered = {}, -- ids of calls answered from here, before their result is written
  shown_call = nil, -- the call the viewer shows, keyed by call_key
  screen = nil, -- Claude's screen text, read while it's blocked
  answered_screen = nil, -- a dialog known only from the screen, answered from here
  watcher = nil,
  timer = nil,
  poll = nil,
  save_timer = nil,
  queue = nil, -- the command queue being sent: { n, total, label }
  stop_queue = nil, -- stops it, putting back what isn't sent yet: fun(why: string)
}

-- The viewer window's look. Set with vim.wo[win][0], like :setlocal, so windows split
-- from it don't inherit it.
local viewer_opts =
  { number = true, relativenumber = true, signcolumn = "no", spell = false, wrap = true, linebreak = true }

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

-- The directory Claude's @ paths are relative to: its foreground process's, else its pane's.
---@param agent? table a pane from `herdr pane list`
---@return string?
function M.workdir(agent)
  local cwd = agent and agent.foreground_cwd
  if type(cwd) ~= "string" then
    cwd = agent and agent.cwd
  end
  return type(cwd) == "string" and cwd or nil
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
---@param cb fun(path?: string, err?: string, agent?: table)
function M.transcript_async(cb)
  vim.system(
    list_panes(),
    { text = true },
    vim.schedule_wrap(function(listed)
      local agent, err = pick_agent(listed)
      local path, path_err = session_path(agent, err)
      cb(path, path_err, agent)
    end)
  )
end

------------------------------------------------------------------------------
-- Replies, read from the transcript rather than the screen: that's the exact
-- markdown, unwrapped and complete. Only a turn's final answer counts (the text
-- Claude ends the turn with, stop_reason end_turn), so the narration it writes
-- between tool calls never replaces the reply you're reading.

-- Whether a user entry is something you wrote: a prompt or a /command, not a tool
-- result, an injected reminder, a background task's notification or `!` output.
function M.from_you(entry)
  if entry.type ~= "user" or entry.isMeta or entry.isSidechain or entry.toolUseResult ~= nil then
    return false
  end
  local content = entry.message and entry.message.content
  if type(content) == "table" then
    for _, block in ipairs(content) do
      if block.type == "tool_result" then
        return false
      end
    end
    return true
  end
  return type(content) == "string"
    and not content:find("^<task%-notification>")
    and not content:find("^<bash%-std")
    and not content:find("^<local%-command")
end

-- Parses whatever was appended since the last read, so a long session isn't
-- re-read on every write. Replies Claude ends several turns with, with no prompt of
-- yours between (a background task finishing, say), join the one before them, so
-- none is hidden behind the newest. Returns whether a reply arrived, and whether
-- it was joined to the last one rather than starting a new one.
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

  local before, last_id, joined = #state.replies, state.last_id, false
  -- A message's content blocks arrive as separate entries; join them.
  local function add(body, id)
    local last = state.replies[#state.replies]
    if id and id == last_id then
      state.replies[#state.replies] = last .. "\n" .. body
      joined = joined or #state.replies == before
    elseif last and not state.prompted then
      state.replies[#state.replies] = last .. "\n\n---\n\n" .. body
      joined = joined or #state.replies == before
    else
      table.insert(state.replies, body)
    end
    last_id = id
    state.prompted = false
  end
  for line in text:gmatch("[^\n]+") do
    if line:find('"type":"user"', 1, true) and not line:find('"tool_use_id"', 1, true) then
      local ok, entry = pcall(vim.json.decode, line)
      if ok and type(entry) == "table" and M.from_you(entry) then
        state.prompted = true
        state.calls = {} -- a prompt, or an interrupt: whatever was asked is over
      end
    end
    -- A tool result answers its call. Found without decoding: these lines hold tool output.
    if line:find('"type":"tool_result"', 1, true) then
      for id in line:gmatch('"tool_use_id":"([^"]+)"') do
        state.calls = vim.tbl_filter(function(call)
          return call.id ~= id
        end, state.calls)
      end
    end
    -- A tool call Claude may block on, for the pending view.
    if line:find('"type":"tool_use"', 1, true) then
      local ok, entry = pcall(vim.json.decode, line)
      if ok and type(entry) == "table" and entry.type == "assistant" and entry.isSidechain ~= true then
        for _, block in ipairs(vim.tbl_get(entry, "message", "content") or {}) do
          if block.type == "tool_use" then
            table.insert(state.calls, { id = block.id, name = block.name, input = block.input })
          end
        end
      end
    end
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
          add(table.concat(texts, "\n"), entry.message.id)
          state.calls = {}
        end
      end
    end
  end
  state.last_id = last_id
  return #state.replies > before, joined
end

------------------------------------------------------------------------------
-- Viewer

local function viewer_valid()
  return state.viewer.win and vim.api.nvim_win_is_valid(state.viewer.win)
end

local function set_winbars()
  if viewer_valid() then
    local title = state.view == "pending" and "Claude · %#DiagnosticError#waiting on you%#WinBar#"
      or state.index > 0 and ("Claude · reply %d/%d"):format(state.index, #state.replies)
      or "Claude · no reply yet"
    if state.queue then
      title = title
        .. ("%%#DiagnosticWarn# · %s %d/%d%%#WinBar#"):format(
          (state.queue.label:gsub("%%", "%%%%")),
          state.queue.n,
          state.queue.total
        )
    end
    local hints = state.view == "pending" and "<leader>a y yes · Y always · n no · 1-9 option · c pane"
      or "<CR> quote · [r ]r replies · <leader>a s send · c pane"
    vim.wo[state.viewer.win][0].winbar = "%#WinBar# 󰚩 " .. title .. "%=%#Comment#" .. hints .. " "
  end
  if state.prompt.win and vim.api.nvim_win_is_valid(state.prompt.win) then
    vim.wo[state.prompt.win][0].winbar =
      "%#WinBar# 󰏫 Prompt%=%#Comment#M-j/k scroll · <leader>a s send · q quote · d drafts · l stash · H sessions "
  end
end

local function draw(lines)
  local buf = state.viewer.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

---@param index integer
---@param message? string shown instead of a reply
local function show(index, message)
  local buf = state.viewer.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  state.index, state.view = index, "reply"
  local text = message or state.replies[index] or "_No finished reply in this session yet._"
  draw(vim.split(text, "\n"))
  if viewer_valid() then
    vim.api.nvim_win_set_cursor(state.viewer.win, { 1, 0 })
  end
  set_winbars()
end

------------------------------------------------------------------------------
-- Claude's screen

local function lookup_agent(cb)
  vim.system(
    list_panes(),
    { text = true },
    vim.schedule_wrap(function(listed)
      cb(pick_agent(listed))
    end)
  )
end

-- M.workdir without blocking, for completion as you type: the one the poll last saw,
-- else looked up.
---@param cb fun(cwd?: string)
function M.workdir_async(cb)
  if state.cwd then
    return cb(state.cwd)
  end
  lookup_agent(function(agent)
    cb(M.workdir(agent))
  end)
end

-- Whether Claude's input box is on screen: a `❯` line under a `─` rule. A dialog such
-- as /model's picker, or a permission prompt, takes its place.
local function input_box(screen)
  local above
  for _, line in ipairs(vim.split(screen, "\n", { plain = true })) do
    if vim.trim(line) ~= "" then
      if line:find("^❯") and above and above:find("^─") then
        return true
      end
      above = line
    end
  end
  return false
end

-- What Claude's pane shows now. herdr's agent_status alone misses a dialog: it keeps
-- the last state behind /model's picker, so the screen is read for the input box too.
---@param cb fun(screen?: "idle"|"working"|"blocked"|"dialog", agent?: table, err?: string, text?: string)
local function read_screen(cb)
  lookup_agent(function(agent, err)
    if not agent then
      return cb(nil, nil, err)
    end
    vim.system(
      { "herdr", "pane", "read", agent.pane_id, "--source", "visible" },
      { text = true },
      vim.schedule_wrap(function(read)
        if read.code ~= 0 then
          return cb(nil, agent, herdr_error(read))
        end
        local screen = agent.agent_status == "blocked" and "blocked"
          or not input_box(read.stdout) and "dialog"
          or agent.agent_status == "working" and "working"
          or "idle"
        cb(screen, agent, nil, read.stdout)
      end)
    )
  end)
end

------------------------------------------------------------------------------
-- The pending call: while Claude is blocked on a tool call, the viewer shows it in
-- place of the reply (config.prompt_pending), and <leader>ay/aY/an/a1-9 answer the
-- dialog asking about it, back to the reply once answered.

-- The call Claude's dialog asks about, with the dialog's options once its screen has
-- been read: the oldest call made this turn with no result yet that the dialog shows,
-- or, while Claude holds that back from the transcript, the dialog as the screen shows
-- it. Not one answered from here.
---@return prompt.Call? call, prompt.Option[]? options
local function pending_call()
  if state.status ~= "blocked" then
    return nil
  end
  local options = state.screen and pending.options(state.screen)
  local lines = options and pending.dialog(state.screen)
  for _, call in ipairs(state.calls) do
    if not state.answered[call.id] and (not lines or pending.asks_about(call, lines)) then
      return call, options
    end
  end
  local id = lines and "screen:" .. table.concat(lines, "\n")
  if id and id ~= state.answered_screen then
    return { id = id, screen = lines }, options
  end
end

-- Which call the viewer shows, and whether with its options: once they're read, it's redrawn.
local function call_key(call, options)
  return call.id .. (options and "#" .. #options or "")
end

local function show_pending(call, options)
  local buf = state.viewer.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  state.view, state.shown_call = "pending", call_key(call, options)
  draw(pending.render(call, options))
  if viewer_valid() then
    vim.api.nvim_win_set_cursor(state.viewer.win, { 1, 0 })
  end
  set_winbars()
end

-- Shows the pending call once Claude is blocked on it, and the reply again once not.
-- Shown once per call, so [r can step away from it while it waits.
local function update_pending()
  local call, options = pending_call()
  if call and state.shown_call ~= call_key(call, options) then
    show_pending(call, options)
  elseif not call and state.shown_call then
    state.shown_call = nil
    if state.view == "pending" then
      show(#state.replies)
    end
  end
end

-- Claude's screen while it's blocked, read for the dialog; then the pending call shown.
---@param cb fun(screen?: "idle"|"working"|"blocked"|"dialog", agent?: table, text?: string) only once read
local function read_dialog(cb)
  if state.status ~= "blocked" then
    state.screen, state.answered_screen = nil, nil
    return update_pending()
  end
  read_screen(function(screen, agent, _, text)
    state.screen = screen == "blocked" and text or nil
    update_pending()
    cb(screen, agent, text)
  end)
end

-- Whether the prompt pane answers the dialog on Claude's screen itself: one whose
-- numbered options it can read. The hand-off takes the rest.
---@param text string Claude's screen
local function answerable(text)
  return pending.options(text) ~= nil
end

-- Picks up new replies. Following the newest reply unless you've stepped back to an
-- older one, or the pending call is shown.
local function refresh()
  local following = state.index == #state.replies
  local new_reply, joined = read_new()
  if state.view == "pending" then
    if following then
      state.index = #state.replies
    end
    set_winbars()
  elseif new_reply and following then
    show(#state.replies)
  elseif joined and following and viewer_valid() then
    -- More of the reply you're reading: keep your place in it.
    vim.api.nvim_win_call(state.viewer.win, function()
      local view = vim.fn.winsaveview()
      draw(vim.split(state.replies[state.index], "\n"))
      vim.fn.winrestview(view)
    end)
    set_winbars()
    vim.notify("Claude added to its reply", vim.log.levels.INFO, { title = "Claude prompt" })
  else
    set_winbars()
  end
  update_pending()
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
  state.prompted = true
  state.calls, state.answered = {}, {}
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

-- Past the newest reply is the pending call, while one waits.
local function step(delta)
  local call = state.shown_call and pending_call()
  local target = state.view == "pending" and delta < 0 and state.index or state.index + delta
  if state.view ~= "pending" and target == #state.replies + 1 and call then
    show_pending(call)
  elseif target >= 1 and target <= #state.replies then
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
      vim.api.nvim_buf_set_extmark(
        buf,
        ns,
        i - 1,
        0,
        { end_col = #line, hl_group = "ClaudePromptQuote", priority = 110 }
      )
    end
  end
end

local function set_quote_hl()
  local fg = vim.api.nvim_get_hl(0, { name = "NonText", link = false }).fg
  vim.api.nvim_set_hl(0, "ClaudePromptQuote", { fg = fg })
end

------------------------------------------------------------------------------
-- Drafts

-- The prompt, saved as you type so a crash, reboot or power cut doesn't take it:
-- one file per Claude session, which herdr resumes under the same id after a
-- restart, so the next prefix+i in that tab brings it back; per pane until the
-- session exists. Deleted once sent or emptied.
local drafts_dir = vim.fn.stdpath("state") .. "/claude-drafts"

local function draft_path()
  local key = state.session or (vim.env.HERDR_PANE_ID and "pane-" .. vim.env.HERDR_PANE_ID:gsub(":", "-"))
  return key and ("%s/%s.md"):format(drafts_dir, key)
end

local function save_draft()
  local buf = state.prompt.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local path = draft_path()
  -- The session changed under the pane (/clear, a restarted Claude): follow it.
  if state.draft and state.draft ~= path then
    vim.fn.delete(state.draft)
  end
  state.draft = path
  if not path then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) == "" then
    vim.fn.delete(path)
    return
  end
  vim.fn.mkdir(drafts_dir, "p")
  -- Synced and renamed into place, so a power cut leaves the old draft or the new
  -- one, never half of one.
  local tmp = path .. ".tmp"
  if vim.fn.writefile(lines, tmp, "s") == 0 then
    vim.uv.fs_rename(tmp, path)
  end
end

local function schedule_save()
  state.save_timer = state.save_timer or vim.uv.new_timer()
  state.save_timer:start(500, 0, vim.schedule_wrap(save_draft))
end

-- Puts this session's saved draft in the prompt, above any unsent input
-- claude-prompt moved in from Claude.
local function restore_draft(buf)
  local path = draft_path()
  state.draft = path
  if not (path and vim.fn.filereadable(path) == 1) then
    return
  end
  local lines = vim.fn.readfile(path)
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(current, "\n")) ~= "" then
    table.insert(lines, "")
    vim.list_extend(lines, current)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Puts text in the prompt under its cursor, replacing the prompt if it's empty, and
-- leaves the cursor at its end in insert mode.
local function insert_text(text)
  local buf, win = state.prompt.buf, state.prompt.win
  if not (buf and win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local lines = vim.split(vim.trim(text), "\n")
  local start = 0
  if vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")) == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    start = vim.api.nvim_win_get_cursor(win)[1]
    table.insert(lines, 1, "")
    vim.api.nvim_buf_set_lines(buf, start, start, false, lines)
  end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { start + #lines, #lines[#lines] })
  vim.cmd.startinsert({ bang = true })
end

-- Every other saved draft, newest first: one whose pane is gone, or whose session
-- came back under a new id. Picking one moves it into this prompt.
local function pick_draft()
  local items, drafts, transcripts = {}, {}, {}
  for _, path in ipairs(vim.fn.glob(drafts_dir .. "/*.md", false, true)) do
    if path ~= state.draft then
      local key = vim.fn.fnamemodify(path, ":t:r")
      local transcript = vim.fn.glob("~/.claude/projects/*/" .. key .. ".jsonl", false, true)[1]
      table.insert(drafts, { path = path, transcript = transcript })
      if transcript then
        table.insert(transcripts, transcript)
      end
    end
  end
  -- From the cwd each transcript records, since its project dir's name can't be read
  -- back: ~/dev/my-app is -home-me-dev-my-app.
  local cwds = require("config.prompt_stash").cwds_of(transcripts)
  for _, draft in ipairs(drafts) do
    local text = table.concat(vim.fn.readfile(draft.path), "\n")
    local time = vim.fn.getftime(draft.path)
    table.insert(items, {
      text = text,
      file = draft.path,
      time = time,
      when = os.date("%m-%d %H:%M", time),
      where = vim.fn.fnamemodify(draft.transcript and cwds[draft.transcript] or "", ":t"),
      title = text:match("[^\n]*"),
      preview = { text = text, ft = "markdown" },
    })
  end
  if #items == 0 then
    return notify_error("No other saved drafts")
  end
  table.sort(items, function(a, b)
    return a.time > b.time
  end)
  Snacks.picker.pick({
    title = "Saved Drafts",
    items = items,
    preview = "preview",
    format = function(item)
      return {
        { item.when, "Comment" },
        { " " },
        { ("%-16s"):format(item.where:sub(1, 16)), "Directory" },
        { " " },
        { item.title },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        insert_text(item.text)
        vim.fn.delete(item.file)
        save_draft()
      end
    end,
  })
end

------------------------------------------------------------------------------
-- Stash (config/prompt_stash.lua)

-- Closes the agent and this pane, or their tab when nothing else is in it. This pane
-- goes last: closing it ends this nvim.
local function close_agent(agent)
  local listed = vim.system(list_panes(), { text = true }):wait()
  local ok, decoded = pcall(vim.json.decode, listed.stdout or "")
  local others = ok
      and #vim.tbl_filter(function(pane)
        return pane.tab_id == vim.env.HERDR_TAB_ID
          and pane.pane_id ~= agent.pane_id
          and pane.pane_id ~= vim.env.HERDR_PANE_ID
      end, vim.tbl_get(decoded, "result", "panes") or {})
    or 1
  if others == 0 then
    vim.system({ "herdr", "tab", "close", vim.env.HERDR_TAB_ID })
  else
    vim.system({ "herdr", "pane", "close", agent.pane_id }):wait()
    vim.system({ "herdr", "pane", "close", vim.env.HERDR_PANE_ID })
  end
end

-- Stashes this pane's session with the draft; with close, then closes the agent too,
-- the draft going with the stash rather than staying in claude-drafts.
local function stash(close)
  local agent, err = M.find_agent()
  local path, path_err = session_path(agent, err)
  if not path then
    return notify_error(path_err)
  end
  local buf = state.prompt.buf
  local draft = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  require("config.prompt_stash").add(agent.session, path, draft, function()
    if close then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      save_draft()
      close_agent(agent)
    end
  end)
end

local function pick_sessions()
  require("config.prompt_stash").pick(state.cwd)
end

------------------------------------------------------------------------------
-- Sending

-- Image embeds from paste() go to Claude as bare paths, which it attaches; a leading
-- `![` would also put Claude in bash mode.
local function unembed(text)
  return (text:gsub("!%[[^%]\n]*%]%(([^)\n]+)%)", "%1"))
end

-- `agent prompt` rather than `pane send-text`: it pastes, so newlines don't submit
-- early and Claude's vim mode can't run the text, and it refuses a blocked agent.
-- Claude only runs a command outside a long paste, which it reads as plain text, so a
-- command with arguments goes in as its own paste first. Bracketed by hand, since
-- `agent prompt` is the only paste herdr offers and it submits.
---@param item prompt.Item
---@param cb fun(err?: string)
local function send_item(agent, item, cb)
  local function prompt(text)
    vim.system(
      { "herdr", "agent", "prompt", agent.pane_id, unembed(text) },
      { text = true },
      vim.schedule_wrap(function(sent)
        cb(sent.code ~= 0 and herdr_error(sent) or nil)
      end)
    )
  end
  if not (item.name and item.args) then
    return prompt(item.name or item.args)
  end
  vim.system(
    { "herdr", "pane", "send-text", agent.pane_id, "\27[200~" .. item.name .. " \27[201~" },
    { text = true },
    vim.schedule_wrap(function(pasted)
      if pasted.code ~= 0 then
        return cb(herdr_error(pasted))
      end
      prompt(item.args)
    end)
  )
end

local waiting_msg = "Claude is waiting on you (a dialog or permission prompt)"

-- Waits for a command to finish: /clear until Claude's session record names a new
-- session, anything else until Claude's input box is back. A command too quick to be
-- seen working counts as done once it has been idle for a second. Gives up after 10s,
-- so the next item goes anyway; calls back with the screen, "blocked" or "dialog", when
-- a prompt or dialog opens, or the input box stays gone for over a second.
---@param item prompt.Item
---@param before? string the session the command was sent in
---@param cb fun(screen?: "blocked"|"dialog", text?: string)
---@param alive fun(): boolean false once the queue is stopped, which ends the wait unanswered
local function await_item(item, before, cb, alive)
  local start, busy, stuck = vim.uv.now(), false, nil
  local function poll()
    if not alive() then
      return
    end
    read_screen(function(screen, agent, _, text)
      if not alive() then
        return
      end
      local now = vim.uv.now()
      local elapsed = now - start
      if screen == "blocked" then
        return cb(screen, text)
      end
      busy = busy or screen == "working"
      if screen == "dialog" then
        stuck = stuck or now
        if now - stuck >= 1000 then
          return cb(screen, text)
        end
      else
        stuck = nil
      end
      local done = screen == "idle"
        and (item.name == "/clear" and agent.session ~= before or item.name ~= "/clear" and (busy or elapsed >= 1000))
      if done or elapsed >= 10000 then
        return cb()
      end
      vim.defer_fn(poll, 250)
    end)
  end
  vim.defer_fn(poll, 250)
end

local answer_hint = "answer with <leader>ay yes, <leader>aY always, <leader>an no or <leader>a1-9"

-- Answers Claude's dialog from here: `choice` is checked against the options on its
-- screen first, so a dialog laid out differently, or none, only notifies.
---@param choice "yes"|"always"|"no"|integer
local function answer(choice)
  read_screen(function(screen, agent, err, text)
    if not screen then
      return notify_error(err)
    elseif screen == "dialog" then
      return notify_error("Claude's dialog isn't a question to answer from here; <leader>ac goes to its pane")
    elseif screen ~= "blocked" then
      return vim.notify("No dialog from Claude to answer", vim.log.levels.INFO, { title = "Claude prompt" })
    end
    state.status, state.screen = "blocked", text
    refresh() -- the call may have been written since the watcher last fired
    local call, options = pending_call()
    if not (call and options) then
      return notify_error("Couldn't read the options of Claude's dialog; answer it in Claude's pane (<leader>ac)")
    end
    local key, why = pending.key(options, choice)
    if not key then
      return notify_error(why)
    end
    local sent = vim.system({ "herdr", "pane", "send-keys", agent.pane_id, key }, { text = true }):wait()
    if sent.code ~= 0 then
      return notify_error(herdr_error(sent))
    end
    if call.screen then
      state.answered_screen = call.id
    else
      state.answered[call.id] = true
    end
    state.screen = nil
    update_pending()
  end)
end

-- Waits for an answerable dialog to close, answered from here or in Claude's pane.
---@param cb fun()
---@param alive fun(): boolean false once the queue is stopped, which ends the wait
local function wait_answered(cb, alive)
  if not alive() then
    return
  end
  read_screen(function(screen)
    if not alive() then
      return
    elseif screen == "blocked" or screen == "dialog" then
      return vim.defer_fn(function()
        wait_answered(cb, alive)
      end, 500)
    end
    cb()
  end)
end

-- Puts items the queue didn't send back in the draft, above anything typed since.
---@param items prompt.Item[]
local function put_back(items)
  local buf = state.prompt.buf
  if #items == 0 or not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local lines = vim.split(
    table.concat(
      vim.tbl_map(function(item)
        return item.source
      end, items),
      "\n\n"
    ),
    "\n"
  )
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(current, "\n")) ~= "" then
    table.insert(lines, "")
    vim.list_extend(lines, current)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  save_draft()
end

-- Steps through the command queue in the background, each item once the one before
-- has finished, with its progress in the viewer's winbar. A dialog asking about a tool
-- call is answered from here, and one the prompt pane can't answer hands off to Claude's
-- pane (config.prompt_handoff); either holds the rest until it closes. A trip not taken
-- or abandoned, or a refused send, stops it, and what isn't sent yet goes back in the
-- draft. Every wait checks it's still running first.
---@param items prompt.Item[]
local function run_queue(items)
  local step_to
  local running, unsent = true, 1
  local function alive()
    return running
  end
  local function stop(from, why)
    if not running then
      return
    end
    running, state.queue, state.stop_queue = false, nil, nil
    set_winbars()
    put_back(vim.list_slice(items, from))
    notify_error(why .. (from <= #items and "; the rest is back in the draft" or ""))
  end
  state.stop_queue = function(why)
    stop(unsent, why)
  end
  -- Pauses at item `from` for a dialog, or stops there if no trip is taken.
  local function pause(agent, from, screen, text)
    if not handoff.wants(screen, text) then
      state.queue.label = state.queue.label .. " · waiting on you"
      state.status, state.screen = "blocked", text
      update_pending()
      vim.notify("Claude is waiting on you: " .. answer_hint, vim.log.levels.WARN, { title = "Claude prompt" })
      return wait_answered(function()
        step_to(from)
      end, alive)
    end
    handoff.go(agent, {
      armed = true,
      resume = function()
        step_to(from)
      end,
      abandon = function()
        stop(from, waiting_msg)
      end,
    }, function(went)
      if not running then
        return
      elseif went then
        state.queue.label = state.queue.label .. " · in Claude's pane"
        set_winbars()
      else
        stop(from, waiting_msg)
      end
    end)
  end
  step_to = function(i)
    if not running then
      return
    end
    unsent = i
    if i > #items then
      running, state.queue, state.stop_queue = false, nil, nil
      set_winbars()
      -- The session may have changed (/clear, a restarted Claude); follow it.
      return M.transcript_async(attach_to)
    end
    state.queue = { n = i, total = #items, label = queue.label(items[i]) }
    set_winbars()
    read_screen(function(screen, agent, err, text)
      if not running then
        return
      elseif not screen then
        return stop(i, err)
      elseif screen == "blocked" or screen == "dialog" then
        return pause(agent, i, screen, text)
      end
      send_item(agent, items[i], function(send_err)
        if not running then
          return
        elseif send_err then
          return stop(i, send_err)
        end
        unsent = i + 1
        if i == #items and not items[i].name then
          return step_to(i + 1)
        end
        -- A last command is awaited too, for the dialog it may open (/model).
        await_item(items[i], agent.session, function(opened, opened_text)
          if opened then
            return pause(agent, i + 1, opened, opened_text)
          end
          step_to(i + 1)
        end, alive)
      end)
    end)
  end
  step_to(1)
end

local function send()
  local buf = state.prompt.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
  if text == "" then
    return
  end
  if state.queue then
    return notify_error("Still sending the last command queue")
  end
  local items = queue.parse(text)
  local agent, err = M.find_agent()
  -- Refused while Claude waits on you: a dialog answerable here is shown, the rest hand
  -- off to its pane, sending once back.
  if agent and agent.agent_status == "blocked" then
    return read_screen(function(screen, now, _, screen_text)
      if screen and not handoff.wants(screen, screen_text) then
        state.status, state.screen = "blocked", screen_text
        update_pending()
        return notify_error("Claude is waiting on you: " .. answer_hint)
      end
      handoff.go(now or agent, { armed = true, resume = send }, function(went)
        if not went then
          notify_error(waiting_msg)
        end
      end)
    end)
  end
  if not agent then
    return notify_error(err)
  end
  -- Cleared now, not once herdr answers, so what you type meanwhile isn't lost; a
  -- refused send goes back in the draft above it.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  save_draft()
  if items[1].name then
    return run_queue(items)
  end
  vim.system(
    { "herdr", "agent", "prompt", agent.pane_id, unembed(text) },
    { text = true },
    vim.schedule_wrap(function(sent)
      if sent.code ~= 0 then
        put_back({ { source = text } })
        return notify_error(herdr_error(sent) .. "; the prompt is back in the draft")
      end
      -- The session may have changed since open (a restarted Claude); follow it.
      M.transcript_async(attach_to)
    end)
  )
end

-- The hand-off on purpose: back on its own once Claude has opened a dialog and closed it.
-- Not while a queue runs, which hands off for its own dialogs.
local function to_claude()
  if state.queue then
    return notify_error("Still sending the command queue; it hands off at a dialog")
  end
  local agent, err = M.find_agent()
  if not agent then
    return notify_error(err)
  end
  handoff.go(agent, {}, function(went)
    if not went then
      notify_error("Already handed off, or this pane isn't focused in herdr")
    end
  end)
end

-- The transcript only exists once a session's first message is written, and
-- /clear or a restarted Claude moves to a new one, neither of which the file
-- watcher can see. So check the agent's session every few seconds, and re-read
-- too, in case libuv dropped an event. A failed lookup keeps the reply shown.
-- Claude going blocked mid-turn shows the pending call, or hands off to its pane for a
-- dialog the prompt pane can't answer; a running queue does its own.
local function start_polling()
  state.poll = state.poll or vim.uv.new_timer()
  state.poll:start(
    2000,
    2000,
    vim.schedule_wrap(function()
      M.transcript_async(function(path, _, agent)
        local was = state.status
        state.status = agent and agent.agent_status
        -- Kept through a failed lookup, so a herdr hiccup doesn't move the draft.
        state.session = agent and agent.session or state.session
        state.cwd = M.workdir(agent) or state.cwd
        -- Read first, so the call Claude is blocked on is known.
        if path then
          attach_to(path)
        else
          set_winbars()
        end
        read_dialog(function(screen, now, text)
          if
            was ~= "blocked"
            and screen
            and not state.queue
            and not handoff.active()
            and handoff.wants(screen, text)
          then
            handoff.go(now, { armed = true })
          end
        end)
      end)
    end)
  )
end

-- Ctrl+V pastes like Claude's input box: a clipboard image is saved where Claude can
-- Read it from any cwd and goes in by absolute path, as an embed snacks.image
-- previews; anything else pastes as text.
local function paste()
  local types = vim.fn.systemlist({ "wl-paste", "--list-types" })
  local mime = vim.iter(types):find(function(t)
    return t:match("^image/%w+$")
  end)
  if not mime then
    return vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
  end
  local out = vim.system({ "wl-paste", "--type", mime }):wait()
  local dir = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/claude-prompt-images"
  local path = ("%s/%s.%s"):format(dir, os.date("%Y%m%d-%H%M%S"), mime:match("/(%w+)"))
  vim.fn.mkdir(dir, "p")
  local file = out.code == 0 and io.open(path, "wb")
  if not file then
    return vim.notify("Couldn't save the clipboard image", vim.log.levels.ERROR)
  end
  file:write(out.stdout)
  file:close()
  vim.api.nvim_paste("![](" .. path .. ")", true, -1)
end

------------------------------------------------------------------------------
-- Opening

-- The answers to Claude's dialog, in the draft and the viewer alike.
local function map_answers(buf)
  local function map(lhs, choice, desc)
    vim.keymap.set("n", lhs, function()
      answer(choice)
    end, { buffer = buf, desc = desc })
  end
  map("<leader>ay", "yes", "Yes to Claude's Dialog")
  map("<leader>aY", "always", "Yes, Don't Ask Again")
  map("<leader>an", "no", "No to Claude's Dialog")
  for n = 1, 9 do
    map("<leader>a" .. n, n, "Option " .. n .. " in Claude's Dialog")
  end
end

local function open_viewer(prompt_win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  -- snacks' smooth scroll animates the cursor too, so a quote taken mid-scroll
  -- would grab whatever line it was passing, and quick Alt+j presses get lost.
  vim.b[buf].snacks_scroll = false
  local height = math.floor(vim.o.lines * 0.62)
  local win = vim.api.nvim_open_win(buf, false, { split = "above", win = prompt_win, height = height })
  for opt, val in pairs(viewer_opts) do
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
  map("n", "<leader>ac", to_claude, "Claude's Pane")
  map_answers(buf)
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
  vim.b[buf].claude_prompt = true -- turns on config.prompt_source (plugins/blink.lua)
  state.prompt = { buf = buf, win = win }
  vim.wo[win][0].winfixheight = true
  local agent = M.find_agent()
  state.session = agent and agent.session
  state.cwd = M.workdir(agent)
  restore_draft(buf)

  -- Buffer-local, so the claudecode extra's global <leader>a binds stay as they are.
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("n", "<leader>as", send, "Send Prompt to Claude")
  map("n", "<leader>aq", quote_all, "Quote Claude's Whole Reply")
  map("n", "<leader>aQ", unquote, "Strip Quoted Lines")
  map("n", "<leader>ad", pick_draft, "Saved Drafts")
  map("n", "<leader>al", stash, "Stash Session")
  map("n", "<leader>aL", function()
    stash(true)
  end, "Stash Session and Close")
  map("n", "<leader>aH", pick_sessions, "Claude Sessions")
  map("n", "<leader>ac", to_claude, "Claude's Pane")
  map("i", "<C-v>", paste, "Paste Image or Text")
  -- Ctrl+C copies like Claude's input box; a mouse drag lands here as a selection.
  map("x", "<C-c>", '"+y', "Copy Selection")
  map_answers(buf)
  vim.api.nvim_create_user_command(
    "ClaudePane",
    to_claude,
    { desc = "Hand off to Claude's pane until its next dialog closes" }
  )
  vim.api.nvim_create_user_command("ClaudeStash", function(cmd)
    stash(cmd.bang)
  end, { bang = true, desc = "Stash this Claude session (! closes it)" })
  vim.api.nvim_create_user_command("ClaudeSessions", pick_sessions, { desc = "Pick a Claude session to resume" })
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
  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI" },
    { group = group, buffer = buf, callback = schedule_save }
  )
  vim.api.nvim_create_autocmd({ "InsertLeave", "FocusLost", "VimLeavePre" }, { group = group, callback = save_draft })
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

  handoff.setup(read_screen, answerable)
  open_viewer(win)
  attach()
  start_polling()
  dim_quotes(buf)
  vim.cmd.normal({ "G", bang = true })
  vim.cmd.startinsert({ bang = true })
end

return M
