return {
  "folke/snacks.nvim",
  opts = {
    -- Inline previews of markdown images, such as the prompt pane's pasted ones
    -- (config/prompt.lua), through herdr's kitty graphics (config/herdr/config.toml).
    image = {},
    picker = {
      sources = {
        explorer = {
          hidden = true,  -- show dotfiles like .config
          ignored = true, -- show git-ignored files too
        },
        files = {
          hidden = true, -- also include dotfiles in the <leader><space> file finder
        },
      },
    },
  },
}
