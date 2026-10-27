{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "John Pierre";
      email = "johndotpierre@outlook.com";
    };
  };
  programs.gh.enable = true;
  programs.lazygit.enable = true;

  # Python project venvs: uv with its own downloaded Python builds (which run
  # through nix-ld), because pip wheels with C extensions don't load against
  # Nix's Python. See "Python projects" in the README.
  home.sessionVariables.UV_PYTHON_PREFERENCE = "only-managed";

  home.packages = with pkgs; [
    jq
    ripgrep
    fd
    unzip
    wget
    wl-clipboard

    nodejs # includes npm
    python3 # for scripts; project venvs use uv
    uv

    # Rust from nixpkgs instead of rustup: declarative, no `rustup default`
    # step. Per-project toolchains go in a flake devShell.
    cargo
    rustc
    clippy
    rustfmt
    rust-analyzer # also used by Claude Code's rust-analyzer-lsp plugin
    pyright # also used by Claude Code's pyright-lsp plugin

    # Replaces Arch's base-devel: a C toolchain for linking Rust and building
    # native extensions. Anything heavier belongs in a project devShell.
    gcc
    gnumake
    pkg-config
  ];
}
