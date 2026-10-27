-- On NixOS, language servers, formatters and linters come from Nix
-- (modules/home/neovim.nix puts them on Neovim's PATH), because the binaries
-- Mason downloads don't run here. With Mason off, LazyVim enables each
-- configured server straight from PATH.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}
