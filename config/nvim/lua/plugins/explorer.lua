return {
  "folke/snacks.nvim",
  opts = {
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
