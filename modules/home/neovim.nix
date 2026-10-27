{
  config,
  pkgs,
  repoDir,
  ...
}:
let
  # LazyVim's Astro extra looks for the Astro TypeScript plugin inside Mason's
  # install dir and warns on every start when it isn't there. Point $MASON at
  # a tiny tree holding just that path, taken from the Nix package.
  masonShim = pkgs.linkFarm "lazyvim-mason-shim" [
    {
      name = "packages/astro-language-server/node_modules/@astrojs/ts-plugin";
      path = "${pkgs.astro-language-server}/lib/node_modules/astro-language-server/packages/language-tools/ts-plugin";
    }
  ];
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;

    # The wrapper's provider settings would otherwise be written to
    # ~/.config/nvim/init.lua, which is your LazyVim config below.
    sideloadInitLua = true;

    # On Neovim's PATH only. Mason is disabled (config/nvim/lua/plugins/nix.lua),
    # so everything LazyVim and your extras call has to be here. pyright and
    # rust-analyzer come from modules/home/dev.nix because Claude Code uses them too.
    extraPackages = with pkgs; [
      # LazyVim core
      lua-language-server
      stylua
      shfmt
      # lang.json, lang.markdown, lang.toml
      vscode-langservers-extracted
      marksman
      markdownlint-cli2
      markdown-toc
      prettier
      taplo
      # lang.nix
      nil
      nixfmt
      statix
      # lang.python (pyright from dev.nix)
      ruff
      # lang.sql
      sqlfluff
      # lang.tailwind, lang.astro (+ the TypeScript extra it pulls in)
      tailwindcss-language-server
      astro-language-server
      vtsls

      # nvim-treesitter (main branch) compiles parsers with these
      tree-sitter
      gcc
      # lazy.nvim, markdown-preview.nvim's build, snacks pickers
      git
      curl
      unzip
      nodejs
      ripgrep
      fd
    ];

    extraWrapperArgs = [
      "--set"
      "MASON"
      "${masonShim}"
    ];
  };

  # A live symlink into this repo rather than a store copy: edit the Lua
  # config without rebuilding, and lazy.nvim can update lazy-lock.json.
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/nvim";
}
