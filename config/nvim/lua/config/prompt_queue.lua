-- The command queue of the prompt pane (config/prompt.lua): splits a draft into what the prompt
-- pane sends one at a time. Its leading block of `/` lines, blank lines between them
-- ignored, is the queue; the first prose line ends it, and everything from there on is
-- one prose item. A command followed directly by text, on its own line or the next ones
-- with no blank line between, takes that text as its arguments.
local M = {}

---@class prompt.Item
---@field name? string the command, `/model`; nil for prose
---@field args? string a command's arguments, or the prose
---@field source string the draft lines it came from, to put back if it isn't sent

-- `/name args` → "/name", "args"; nil for a line that isn't a command, such as a path.
---@param line string
function M.command(line)
  local name, rest = line:match("^(/[%w:_-]+)(.*)$")
  if name and (rest == "" or rest:match("^%s")) then
    return name, vim.trim(rest)
  end
end

---@param text string
---@return prompt.Item[]
function M.parse(text)
  local lines = vim.split(text, "\n", { plain = true })
  local items, i = {}, 1
  while i <= #lines do
    local line = lines[i]
    if vim.trim(line) == "" then
      i = i + 1
    elseif not M.command(line) then
      local prose = vim.trim(table.concat(lines, "\n", i))
      table.insert(items, { args = prose, source = prose })
      break
    else
      local name, rest = M.command(line)
      local args, j = { rest ~= "" and rest or nil }, i + 1
      while j <= #lines and vim.trim(lines[j]) ~= "" do
        table.insert(args, lines[j])
        j = j + 1
      end
      local joined = #args > 0 and table.concat(args, "\n") or nil
      table.insert(items, { name = name, args = joined, source = table.concat(lines, "\n", i, j - 1) })
      i = j
    end
  end
  return items
end

-- Whether a command typed at the start of line `row` would be queued: the parser is asked
-- with that line standing in as one, so only the lines above it decide.
---@param lines string[] the draft, at least up to `row`
---@param row integer
function M.in_block(lines, row)
  local above = vim.list_slice(lines, 1, row - 1)
  table.insert(above, "/x")
  local items = M.parse(table.concat(above, "\n"))
  return items[#items].name ~= nil
end

-- How the item reads in the winbar: its first line, cut short.
---@param item prompt.Item
function M.label(item)
  local first = item.source:match("[^\n]*")
  if vim.fn.strchars(first) > 30 then
    first = vim.fn.strcharpart(first, 0, 29) .. "…"
  end
  return first
end

return M
