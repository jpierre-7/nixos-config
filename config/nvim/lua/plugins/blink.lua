-- /command, /skill and @file completion in the Claude prompt pane
-- (config/prompt_source.lua), only in its buffer. LazyVim extends sources.default,
-- so the usual sources stay.
return {
  "saghen/blink.cmp",
  opts = {
    sources = {
      default = { "claude_prompt" },
      providers = {
        claude_prompt = {
          name = "Claude",
          module = "config.prompt_source",
          enabled = function()
            return vim.b.claude_prompt == true
          end,
          fallbacks = { "snippets", "buffer", "path" },
        },
      },
    },
  },
}
