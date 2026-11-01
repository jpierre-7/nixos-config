-- Drop markdownlint-cli2 from the lang.markdown extra: its style rules (line
-- length, table spacing) flag ordinary prose and READMEs. marksman and
-- prettier stay. Functions rather than plain tables, because lazy.nvim merges
-- list opts by index, so `markdown = {}` would keep the extra's entries.
local function without_markdownlint(list)
  return vim.tbl_filter(function(name)
    return name ~= "markdownlint-cli2"
  end, list or {})
end

return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.markdown = nil
    end,
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      for _, ft in ipairs({ "markdown", "markdown.mdx" }) do
        opts.formatters_by_ft[ft] = without_markdownlint(opts.formatters_by_ft[ft])
      end
    end,
  },
}
