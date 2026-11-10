{ lib, pkgs, ... }:
{
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin" # `cargo install` targets
  ];

  programs.fish = {
    enable = true;

    shellAliases = {
      ls = "lsd";
      l = "lsd -l";
      la = "lsd -a";
      lla = "lsd -la";
      lt = "lsd --tree";
    };

    shellAbbrs = {
      l = "lsd";
      lt = "lsd --tree";
      lta = "lsd --tree -a";
      nv = "nvim";
      lg = "lazygit";
      nrs = "sudo nixos-rebuild switch --flake ~/nixos-config";
      # Pull changes made on the other machine, then rebuild.
      nup = "git -C ~/nixos-config pull && sudo nixos-rebuild switch --flake ~/nixos-config";
      # `qqq` + space -> `cd ../../../`
      qcd = {
        position = "command";
        regex = "q+";
        function = "qcd";
      };
    };

    functions = {
      qcd = {
        description = "Expand a run of q characters into cd ../.. one level per q";
        body = "echo cd (string repeat -n (string length -- $argv[1]) ../)";
      };
      fish_greeting = "fastfetch";
    };

    # Claude Code draws images (terminal-browser pages, pasted-image previews)
    # only on kitty and Ghostty, and herdr reports itself as libghostty, so
    # herdr's panes force them on. Only there: plain WezTerm can't draw kitty's
    # Unicode placeholders and shows them as boxes, with the picture at the
    # cursor.
    shellInit = ''
      if set -q HERDR_ENV
          set -gx CLAUDE_CODE_FORCE_TERMINAL_IMAGES 1
      end
    '';

    # Interactive only, as on Arch: an on-variable handler declared through
    # `functions` would also fire in scripts.
    interactiveShellInit = ''
      set -g fish_key_bindings fish_vi_key_bindings

      # On cd: onefetch when entering a different git repo, then a long listing.
      function run-ls-on-cd -v PWD
          set current_repository (git rev-parse --show-toplevel 2> /dev/null)
          if [ "$current_repository" ] && [ "$current_repository" != "$last_repository" ]
              onefetch
          end
          set -gx last_repository $current_repository
          command lsd -l
      end
    '';
  };

  # No settings here: config/starship.toml is a Noctalia template, and
  # Noctalia writes ~/.config/starship.toml from it in its current colors
  # (modules/home/noctalia.nix). Until it has run once, starship uses its
  # default prompt.
  programs.starship.enable = true;

  programs.lsd = {
    enable = true;
    # The aliases above are the ones you use; Home Manager's own set
    # (ll, la = "lsd -A", ...) would clash with them.
    enableFishIntegration = false;
    settings = {
      classic = false;
      blocks = [
        "permission"
        "user"
        "group"
        "size"
        "date"
        "name"
      ];
      color = {
        when = "auto";
        theme = "default";
      };
      date = "date";
      dereference = false;
      icons = {
        when = "auto";
        theme = "fancy";
        separator = " ";
      };
      indicators = false;
      layout = "grid";
      recursion.enabled = false;
      size = "default";
      sorting = {
        column = "name";
        reverse = false;
        dir-grouping = "none";
      };
      no-symlink = false;
      total-size = false;
      hyperlink = "never";
      symlink-arrow = "⇒";
      header = false;
      literal = false;
      truncate-owner.marker = "";
    };
    icons = ../../config/lsd/icons.yaml;
  };

  programs.fastfetch = {
    enable = true;
    settings = lib.importJSON ../../config/fastfetch.jsonc;
  };

  programs.htop.enable = true;

  home.packages = [ pkgs.onefetch ];
}
