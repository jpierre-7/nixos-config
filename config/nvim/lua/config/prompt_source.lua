-- blink.cmp source for the prompt pane (lua/config/prompt.lua): /command, /skill and
-- @file, as Claude's own input offers them. Registered in lua/plugins/blink.lua. Ported from github.com/HefKer/dots.
local M = {}

local limit = 50

function M.new()
  return setmetatable({ candidates = {}, docs = {} }, { __index = M })
end

function M:get_trigger_characters()
  return { "/", "@", ".", ":" }
end

local function query(context)
  local before = context.line:sub(1, context.cursor[2])
  -- Only the queue's leading block of / lines runs as commands. Past that, Claude just
  -- reads the name and has to invoke the skill itself, so only the skills it can invoke
  -- are offered.
  local name = before:match("^/([%w:_-]*)$")
  if name then
    local row = context.cursor[1]
    local lines = vim.api.nvim_buf_get_lines(context.bufnr, 0, row, false)
    if require("config.prompt_queue").in_block(lines, row) then
      return "command", name
    end
  end
  local listed = name or before:match("%s/([%w:_-]*)$")
  if listed then
    return "listed_skill", listed
  end
  local file = before:match("^@(%S*)$") or before:match("%s@(%S*)$")
  if file then
    return "file", file
  end
end

-- Claude Code's own commands, which no file lists. Bundled skills come with the listing.
local builtins = {
  ["add-dir"] = "Add a working directory for this session",
  advisor = "Turn the advisor model on or off",
  agents = "Manage subagents",
  artifacts = "List artifacts and attach, open or copy one",
  autocompact = "Set how full the context gets before auto-compact",
  ["autofix-pr"] = "Cloud session that pushes fixes to this branch's PR",
  background = "Detach this session as a background agent",
  branch = "Branch the conversation at this point",
  btw = "Ask a side question without adding to the conversation",
  bug = "Report a bug or share the conversation",
  cd = "Move this session to another directory",
  chrome = "Configure Claude in Chrome",
  clear = "Start a new conversation with empty context",
  color = "Set the prompt bar color",
  compact = "Summarize the conversation to free context",
  config = "Open settings, or set key=value",
  context = "Show context usage as a grid",
  copy = "Copy the last response to the clipboard",
  cost = "Alias for /usage",
  desktop = "Continue this session in the desktop app",
  diff = "Review the working tree's changes",
  effort = "Set the effort level",
  exit = "Exit the CLI",
  export = "Export the conversation as plain text",
  fast = "Toggle fast mode",
  feedback = "Send product feedback",
  focus = "Toggle the focus view",
  fork = "Copy the conversation into a background session",
  goal = "Keep working until a condition is met",
  help = "Show help and available commands",
  hooks = "View hook configurations",
  ide = "Manage IDE integrations",
  import = "Import config from Codex, Gemini CLI or Cursor",
  init = "Initialize the project with a CLAUDE.md",
  insights = "Report on how recent sessions went",
  keybindings = "Open the keyboard shortcuts file",
  ["list-agents"] = "List the agents and sessions Claude can message",
  login = "Sign in to an Anthropic account",
  logout = "Sign out",
  mcp = "Manage MCP servers",
  memory = "Edit CLAUDE.md files and auto memory",
  model = "Switch the model",
  ["output-style"] = "List or switch output styles",
  permissions = "Manage permission rules",
  plan = "Enter plan mode",
  plugin = "Manage plugins",
  powerup = "Interactive feature lessons",
  recap = "One-line summary of this session",
  ["release-notes"] = "View the changelog",
  ["reload-plugins"] = "Reload active plugins",
  ["reload-skills"] = "Re-scan skill and command directories",
  ["remote-control"] = "Make this session available to claude.ai",
  rename = "Rename this session",
  restart = "Restart and resume this session",
  resume = "Resume a conversation",
  review = "Review the diff, a PR or a branch",
  rewind = "Rewind the conversation and/or code",
  sandbox = "Toggle sandbox mode",
  schedule = "Manage cloud scheduled tasks",
  ["security-review"] = "Security review of this branch's changes",
  ["skill-doctor"] = "What each skill costs and how often it's used",
  skills = "List available skills",
  stats = "Usage, on the Stats tab",
  status = "Version, model, account and connectivity",
  statusline = "Configure the status line",
  stop = "Stop the attached background session",
  subtask = "Spawn a forked background subagent",
  tasks = "Manage background work",
  teleport = "Pull a cloud session into this terminal",
  ["terminal-setup"] = "Install a newline keybinding for the terminal",
  theme = "Change the color theme",
  tui = "Set the terminal UI renderer",
  ultrareview = "Deep multi-agent review in the cloud",
  usage = "Session cost, plan limits and stats",
  voice = "Toggle voice dictation",
  workflows = "Watch running and finished workflows",
}

-- A command or skill file's frontmatter description, if it has one.
local function description(path)
  local lines = vim.fn.readfile(path, "", 30)
  if lines[1] ~= "---" then
    return nil
  end
  for i = 2, #lines do
    if lines[i] == "---" then
      return nil
    end
    local value = lines[i]:match("^description:%s*(.-)%s*$")
    if value and value ~= "" then
      return (value:gsub([[^(["'])(.*)%1$]], "%2"))
    end
  end
end

-- Command files under `dir`, a nested one named `sub:name` as Claude names it.
local function command_files(dir, prefix, add)
  dir = vim.fn.expand(dir)
  for _, path in ipairs(vim.fn.glob(dir .. "/**/*.md", false, true)) do
    local name = path:sub(#dir + 2, -4):gsub("/", ":")
    add(prefix .. name, path)
  end
end

-- Installed plugins' commands, named `plugin:name`.
local function plugin_commands(add)
  local ok, installed = pcall(function()
    return vim.json.decode(
      table.concat(vim.fn.readfile(vim.fn.expand("~/.claude/plugins/installed_plugins.json")), "\n")
    )
  end)
  for id, installs in pairs(ok and installed.plugins or {}) do
    local install = installs[1]
    if install and install.installPath then
      command_files(install.installPath .. "/commands", id:match("^[^@]+") .. ":", add)
    end
  end
end

-- The newest listing in the project's transcripts, since a session only writes its own
-- on its first prompt, which is when a skill is most likely to be wanted.
local function listed_skills(cwd)
  local dir = "~/.claude/projects/" .. cwd:gsub("%W", "-")
  local paths = vim.fn.glob(dir .. "/*.jsonl", false, true)
  table.sort(paths, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)
  for _, path in ipairs(vim.list_slice(paths, 1, 5)) do
    local names = {}
    for _, line in ipairs(vim.fn.readfile(path)) do
      if line:find('"skill_listing"', 1, true) then
        local ok, entry = pcall(vim.json.decode, line)
        vim.list_extend(names, ok and vim.tbl_get(entry, "attachment", "names") or {})
      end
    end
    if #names > 0 then
      return names
    end
  end
  return {}
end

-- Everything that runs as a command: the built-ins, custom and plugin commands, and the
-- skills. The listing has plugin and bundled skills but not the disable-model-invocation
-- ones, which only a scan of the skill directories finds.
local function commands(cwd)
  local names, docs = {}, {}
  local function add(name, path)
    table.insert(names, name)
    docs[name] = docs[name] or (path and description(path))
  end
  for name, doc in pairs(builtins) do
    add(name)
    docs[name] = doc
  end
  for _, dir in ipairs({ "~/.claude", cwd .. "/.claude" }) do
    command_files(dir .. "/commands", "", add)
    for _, path in ipairs(vim.fn.glob(dir .. "/skills/*/SKILL.md", false, true)) do
      add(vim.fn.fnamemodify(path, ":h:t"), path)
    end
  end
  plugin_commands(add)
  vim.list_extend(names, listed_skills(cwd))
  return names, docs
end

-- Shortest first, so the bare @ opens on the top of the tree.
local function files(cwd, done)
  local cmd = { "fd", "--hidden", "--exclude", ".git", "--strip-cwd-prefix", "--max-results", "20000" }
  vim.system(cmd, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      local list = vim.split(result.stdout, "\n", { trimempty = true })
      table.sort(list, function(a, b)
        return #a < #b or (#a == #b and a < b)
      end)
      done(list)
    end)
  end)
end

-- Looked up as each / or @ opens, so a new command, skill or file shows up on the next
-- one, in Claude's directory as config.prompt.workdir_async has it, which doesn't wait
-- on herdr while you type.
function M:refresh(kind, done)
  require("config.prompt").workdir_async(function(found)
    local cwd = found or vim.fn.getcwd()
    local function store(list)
      self.candidates[kind] = list
      done()
    end
    if kind == "file" then
      files(cwd, store)
    else
      local names, docs = listed_skills(cwd), {}
      if kind == "command" then
        names, docs = commands(cwd)
      end
      self.docs = vim.tbl_extend("force", self.docs, docs)
      table.sort(names)
      store(vim.fn.uniq(names))
    end
  end)
end

-- blink matches only the word under the cursor, which would drop everything before the
-- last / of a path. So the matching happens here, on the whole token, and filterText is
-- that word to let every result through; the source re-runs on each keystroke.
-- score_offset keeps this order, which blink's frecency would otherwise override by
-- floating anything accepted recently above a better match.
local function items(context, candidates, docs, token)
  local found = token == "" and vim.list_slice(candidates, 1, limit)
    or vim.fn.matchfuzzy(candidates, token, { limit = limit })
  local line, col = context.cursor[1] - 1, context.cursor[2]
  local keyword = context.get_keyword()
  return vim.tbl_map(function(index)
    return {
      label = found[index],
      kind = require("blink.cmp.types").CompletionItemKind.File,
      filterText = keyword,
      documentation = docs[found[index]],
      score_offset = (limit - index) * 10,
      textEdit = {
        newText = found[index],
        range = {
          start = { line = line, character = col - #token },
          ["end"] = { line = line, character = col },
        },
      },
    }
  end, vim.fn.range(1, #found))
end

function M:get_completions(context, callback)
  local kind, token = query(context)
  if not kind then
    callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = true })
    return
  end
  local function respond()
    callback({
      items = items(context, self.candidates[kind], self.docs, token),
      is_incomplete_forward = true,
      is_incomplete_backward = true,
    })
  end
  if token == "" or not self.candidates[kind] then
    self:refresh(kind, respond)
  else
    respond()
  end
end

return M
