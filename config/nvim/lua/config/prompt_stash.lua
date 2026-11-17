-- The stash: Claude sessions set aside from the prompt pane
-- (config/prompt.lua) to come back to, each with a note and its draft, and the sessions
-- picker that resumes one, stashed or not, in a new herdr tab through
-- claude-prompt-tab (config/claude/prompt-tab.sh). Ported from github.com/HefKer/dots,
-- without its second Claude account.
local M = {}

-- One JSON object keyed by session id: { session, cwd, note, draft, time }.
local stash_path = vim.fn.stdpath("state") .. "/claude-stash.json"

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Claude stash" })
end

local function read()
  local ok, all = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(stash_path), "\n"))
  end)
  return ok and type(all) == "table" and all or {}
end

-- Renamed into place, so a crash leaves the old stash or the new one.
local function write(all)
  vim.fn.mkdir(vim.fs.dirname(stash_path), "p")
  local tmp = stash_path .. ".tmp"
  local text = vim.tbl_isempty(all) and "{}" or vim.json.encode(all)
  if vim.fn.writefile({ text }, tmp, "s") == 0 then
    vim.uv.fs_rename(tmp, stash_path)
  end
end

-- The cwd each session was started in: the first one its transcript records. One rg
-- for them all.
---@param transcripts string[]
---@return table<string, string> cwd by transcript path
function M.cwds_of(transcripts)
  local found = {}
  if #transcripts == 0 then
    return found
  end
  local out = vim
    .system(
      vim.list_extend(
        { "rg", "--no-config", "--null", "--with-filename", "-m1", "-o", [["cwd":"(?:[^"\\]|\\.)*"]] },
        transcripts
      ),
      { text = true }
    )
    :wait()
  for line in (out.stdout or ""):gmatch("[^\n]+") do
    local path, match = line:match("^(.-)%z(.*)$")
    local ok, decoded = pcall(vim.json.decode, "{" .. (match or "") .. "}")
    if path and ok and type(decoded.cwd) == "string" then
      found[path] = decoded.cwd
    end
  end
  return found
end

---Adds a session to the stash, or updates its note and draft, asking for the note.
---@param session string
---@param transcript string its transcript's path
---@param draft string
---@param cb fun() called once it's stashed, not when the note is cancelled
function M.add(session, transcript, draft, cb)
  local old = read()[session]
  vim.ui.input({ prompt = "Stash note (optional): ", default = old and old.note or "" }, function(note)
    if note == nil then
      return
    end
    local all = read()
    all[session] = {
      session = session,
      cwd = M.cwds_of({ transcript })[transcript],
      note = vim.trim(note),
      draft = vim.trim(draft) ~= "" and draft or nil,
      time = os.time(),
    }
    write(all)
    notify(old and "Stash updated" or "Session stashed")
    cb()
  end)
end

local function remove(session)
  local all = read()
  all[session] = nil
  write(all)
end

------------------------------------------------------------------------------
-- Sessions: every transcript under ~/.claude/projects/, read with
-- two rg passes over the whole store, rather than parsing 1 GB of JSON in Lua.

---@return table<string, {path: string, session: string, cwd?: string, title?: string, mtime: integer}>
local function discover()
  local roots = vim.fn.glob("~/.claude/projects", false, true)
  if #roots == 0 then
    return {}
  end
  -- Depth 2 is <project>/<id>.jsonl; subagents sit deeper.
  local base =
    { "rg", "--no-config", "--null", "--no-line-number", "--with-filename", "--max-depth", "2", "-g", "*.jsonl" }
  local meta = vim.system(
    vim.list_extend(
      vim.list_extend({}, base),
      vim.list_extend({ "-e", [[^\{"type":"(ai-title|custom-title|last-prompt|summary)"]] }, roots)
    ),
    { text = true }
  )
  local cwds = vim.system(
    vim.list_extend(
      vim.list_extend({}, base),
      vim.list_extend({ "-m1", "-o", "-e", [["cwd":"(?:[^"\\]|\\.)*"]] }, roots)
    ),
    { text = true }
  )
  local sessions = {}
  local function get(path)
    local s = sessions[path]
    if not s then
      local stat = vim.uv.fs_stat(path)
      s = {
        path = path,
        session = vim.fn.fnamemodify(path, ":t:r"),
        mtime = stat and stat.mtime.sec or 0,
        titles = {},
      }
      sessions[path] = s
    end
    return s
  end
  for line in (cwds:wait().stdout or ""):gmatch("[^\n]+") do
    local path, match = line:match("^(.-)%z(.*)$")
    local ok, decoded = pcall(vim.json.decode, "{" .. (match or "") .. "}")
    if path and ok then
      get(path).cwd = decoded.cwd
    end
  end
  for line in (meta:wait().stdout or ""):gmatch("[^\n]+") do
    local path, json = line:match("^(.-)%z(.*)$")
    local ok, entry = pcall(vim.json.decode, json or "")
    if path and ok and type(entry) == "table" then
      local titles = get(path).titles
      -- A name you gave it beats Claude's, which beats the summary and the first prompt.
      if entry.type == "custom-title" then
        titles.custom = entry.customTitle
      elseif entry.type == "ai-title" then
        titles.ai = entry.aiTitle
      elseif entry.type == "summary" then
        titles.summary = titles.summary or entry.summary
      elseif entry.type == "last-prompt" then
        titles.first = titles.first or entry.lastPrompt
      end
    end
  end
  local by_id = {}
  for _, s in pairs(sessions) do
    local t = s.titles
    local title = t.custom or t.ai or t.summary or t.first
    s.title = type(title) == "string" and vim.trim(title:match("[^\n]*")) or nil
    s.titles = nil
    -- One transcript per id; a sync-conflict copy or a moved project keeps the newest.
    if not by_id[s.session] or by_id[s.session].mtime < s.mtime then
      by_id[s.session] = s
    end
  end
  return by_id
end

------------------------------------------------------------------------------
-- Preview: what you and Claude wrote, as markdown, the way the reply viewer reads it.

local preview_bytes = 4 * 1024 * 1024 -- the tail read of a long transcript

local function text_of(content)
  if type(content) == "string" then
    return content
  end
  local texts = {}
  for _, block in ipairs(type(content) == "table" and content or {}) do
    if block.type == "text" and type(block.text) == "string" then
      table.insert(texts, block.text)
    end
  end
  return table.concat(texts, "\n")
end

-- `/triage capture items` rather than the tags Claude Code stores it in.
local function tidy(text)
  local name = text:match("<command%-name>(.-)</command%-name>")
  if name then
    local args = text:match("<command%-args>(.-)</command%-args>") or ""
    return vim.trim(name .. " " .. args)
  end
  return text
end

local function render(path)
  local fh = io.open(path, "rb")
  if not fh then
    return "_Transcript missing._"
  end
  local size = fh:seek("end")
  local cut = size > preview_bytes
  fh:seek("set", cut and size - preview_bytes or 0)
  local data = fh:read("*a") or ""
  fh:close()
  if cut then
    data = data:gsub("^[^\n]*\n", "") -- the line the cut started in
  end
  local from_you = require("config.prompt").from_you
  local out, last = cut and { "_… earlier turns cut_", "" } or {}, nil
  for line in data:gmatch("[^\n]+") do
    if line:find('"type":"user"', 1, true) or line:find('"type":"assistant"', 1, true) then
      local ok, entry = pcall(vim.json.decode, line)
      if ok and type(entry) == "table" and entry.message and entry.isSidechain ~= true then
        local who = entry.type == "user" and from_you(entry) and "You" or entry.type == "assistant" and "Claude"
        local text = who and vim.trim(tidy(text_of(entry.message.content))) or ""
        if text ~= "" then
          if who ~= last then
            vim.list_extend(out, { "## " .. who, "" })
          end
          vim.list_extend(out, vim.split(text, "\n"))
          table.insert(out, "")
          last = who
        end
      end
    end
  end
  return #out > 0 and table.concat(out, "\n") or "_Nothing written in this session yet._"
end

------------------------------------------------------------------------------
-- Picker

local function age(time)
  local s = os.time() - time
  return s < 3600 and ("%dm"):format(s / 60)
    or s < 86400 and ("%dh"):format(s / 3600)
    or s < 86400 * 60 and ("%dd"):format(s / 86400)
    or ("%dmo"):format(s / (86400 * 30))
end

-- Opens a new tab in the session's cwd, with Claude resuming it and the prompt pane
-- over it, the stashed draft in the prompt.
local function resume(item)
  if item.missing then
    return notify("Transcript is gone; nothing to resume", vim.log.levels.ERROR)
  end
  if not (item.cwd and vim.fn.isdirectory(item.cwd) == 1) then
    return notify("Session's directory is gone: " .. tostring(item.cwd), vim.log.levels.ERROR)
  end
  local args = { "claude-prompt-tab", "--resume", item.session, item.cwd }
  -- A draft the prompt pane saved since (config/prompt.lua) is newer, and comes back anyway.
  local saved = ("%s/claude-drafts/%s.md"):format(vim.fn.stdpath("state"), item.session)
  if item.draft and vim.fn.filereadable(saved) == 0 then
    local tmp = vim.fn.tempname() .. ".md"
    vim.fn.writefile(vim.split(item.draft, "\n"), tmp)
    table.insert(args, tmp)
  end
  -- The script reads the focused pane from herdr's key-bind environment.
  vim.system(args, { env = { HERDR_ACTIVE_PANE_ID = vim.env.HERDR_PANE_ID } }, function(out)
    if out.code == 0 and item.stashed then
      vim.schedule(function()
        remove(item.session)
      end)
    end
  end)
end

---@param here? string the current project's directory, listed after the stash
function M.pick(here)
  local sessions = discover()
  local items = {}
  for id, entry in pairs(read()) do
    local s = sessions[id]
    sessions[id] = nil
    table.insert(items, {
      rank = 0,
      sort = -(entry.time or 0),
      stashed = true,
      missing = s == nil,
      session = id,
      path = s and s.path,
      cwd = (s and s.cwd) or entry.cwd,
      title = s and s.title,
      mtime = s and s.mtime or entry.time or 0,
      note = entry.note ~= "" and entry.note or nil,
      draft = entry.draft,
    })
  end
  for _, s in pairs(sessions) do
    table.insert(items, {
      rank = here and s.cwd == here and 1 or 2,
      sort = -s.mtime,
      session = s.session,
      path = s.path,
      cwd = s.cwd,
      title = s.title,
      mtime = s.mtime,
    })
  end
  table.sort(items, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.sort < b.sort
  end)
  for i, item in ipairs(items) do
    item.idx = i
    item.where = item.cwd and vim.fn.fnamemodify(item.cwd, ":~") or "?"
    item.title = item.title or "(untitled)"
    if vim.fn.strchars(item.title) > 60 then
      item.title = vim.fn.strcharpart(item.title, 0, 59) .. "…"
    end
    -- What the filter matches: note, title, project dir, and id.
    item.text =
      table.concat({ item.stashed and "stashed" or "", item.note or "", item.title, item.where, item.session }, " ")
  end
  if #items == 0 then
    return notify("No Claude sessions found", vim.log.levels.ERROR)
  end

  Snacks.picker.pick({
    title = "Claude Sessions",
    items = items,
    -- Kept in the order above (stash, this project, the rest), not by match score.
    sort = { fields = { "score:desc", "idx" } },
    matcher = { sort_empty = false },
    format = function(item)
      local row = {}
      if item.stashed then
        table.insert(
          row,
          { item.missing and "missing " or "stashed ", item.missing and "DiagnosticError" or "DiagnosticWarn" }
        )
      end
      if item.note then
        table.insert(row, { item.note .. " · ", "DiagnosticHint" })
      end
      vim.list_extend(row, {
        { item.title },
        { "  " },
        { item.where, "Directory" },
        { " " .. age(item.mtime), "Comment" },
      })
      return row
    end,
    preview = function(ctx)
      local item = ctx.item
      if not item.preview then
        local head = {}
        if item.note then
          vim.list_extend(head, { "> **Stashed:** " .. item.note, "" })
        end
        if item.draft then
          vim.list_extend(head, { "> **Draft:**", "> " .. item.draft:gsub("\n", "\n> "), "" })
        end
        local body = item.missing and "_Transcript missing._" or render(item.path)
        table.insert(head, body)
        item.preview = { text = table.concat(head, "\n"), ft = "markdown" }
        item.pos = { #vim.split(item.preview.text, "\n"), 0 }
      end
      Snacks.picker.preview.preview(ctx)
      ctx.preview:wo({ wrap = true, linebreak = true })
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        resume(item)
      end
    end,
    actions = {
      stash_delete = function(picker, item)
        if not (item and item.stashed) then
          return notify("Not stashed", vim.log.levels.WARN)
        end
        remove(item.session)
        notify("Removed from the stash")
        picker:close()
        M.pick(here)
      end,
    },
    win = {
      input = { keys = { ["<c-x>"] = { "stash_delete", mode = { "n", "i" }, desc = "Unstash" } } },
      list = { keys = { ["dd"] = { "stash_delete", desc = "Unstash" } } },
    },
  })
end

return M
