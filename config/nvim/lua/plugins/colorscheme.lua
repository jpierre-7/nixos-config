-- colors/noctalia.lua is rendered by Noctalia from its palette
-- (modules/home/noctalia.nix), so it is gitignored. Noctalia sends running
-- Neovims SIGUSR1 after each palette change, and the colorscheme reloads
-- itself. Until Noctalia has written it once, LazyVim falls back to habamax.
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "noctalia",
    },
  },
}
