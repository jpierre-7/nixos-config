{
  description = "NixOS configuration for john's desktop and laptop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for the few packages that are missing or too old on stable;
    # see overlays/default.nix and the README.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      # Keep this branch in step with the nixpkgs branch above.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Linked to ~/Pictures/Wallpapers; Noctalia's default wallpaper comes from here.
    wallpapers = {
      url = "github:jpierre-7/Wallpapers";
      flake = false;
    };
    # Patched AirPods daemon for the Noctalia AirPods plugin; built by pkgs/librepods.nix.
    librepods = {
      url = "github:harveywuk/librepods";
      flake = false;
    };
    # Session graph in herdr; pkgs/zoetrope.nix builds it, and modules/home/herdr.nix
    # links the herdr plugin from the same source.
    zoetrope = {
      url = "github:furkankly/zoetrope";
      flake = false;
    };
    # Clipboard sync for Lan Mouse; built by pkgs/lan-clip.nix. It reads the Lan
    # Mouse private key and every copy, and it's a new project from one author,
    # so it stays on this reviewed commit: read the diff before moving the rev.
    lan-clip = {
      url = "github:johanjongsma/lan-clip/5e5126dfdf99ce9dba92b5e9ef474a6b6831d849";
      flake = false;
    };
    # Only for the git-guardrails-claude-code skill, linked in
    # modules/home/claude.nix. Its hook isn't taken from here: that's
    # config/claude/block-dangerous-git.sh.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
    # Encrypted secrets, see SECURITY.md.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The pre-commit hook that nix develop installs.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Noctalia's community theme templates, the ones its Templates store
    # downloads. modules/home/noctalia.nix renders the Neovim and Vicinae ones.
    noctalia-templates = {
      url = "github:noctalia-dev/community-templates";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Where this repo is cloned on each machine. Configs that apps rewrite
      # themselves (and the Neovim config) are symlinked here instead of into
      # the read-only Nix store, so they stay editable without a rebuild.
      repoDir = "/home/john/nixos-config";

      mkHost =
        hostname:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${hostname}
            ./modules/nixos
            home-manager.nixosModules.home-manager
            {
              networking.hostName = hostname;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # Move pre-existing files aside instead of failing the first switch.
                backupFileExtension = "hm-backup";
                extraSpecialArgs = { inherit inputs repoDir; };
                users.john = ./home/john.nix;
              };
            }
          ];
        };

      # Package set of a real host, so checks use the same versions (and overlay) as the machines.
      pkgs = self.nixosConfigurations.desktop.pkgs;
      hm = self.nixosConfigurations.desktop.config.home-manager.users.john;

      # gitleaks reads .gitleaks.toml. nixfmt skips the generated hardware
      # configs, as they aren't meant to be reformatted.
      preCommit = inputs.git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          gitleaks.enable = true;
          nixfmt = {
            enable = true;
            excludes = [ "hardware-configuration\\.nix$" ];
          };
        };
      };
    in
    {
      nixosConfigurations = {
        desktop = mkHost "desktop";
        laptop = mkHost "laptop";
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      # Entering this shell once installs the pre-commit hook on this machine.
      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommit) shellHook;
        packages = preCommit.enabledPackages;
      };

      # `nix flake check` parses the hand-written niri config and the generated
      # Noctalia config with the exact versions that will run them.
      checks.${system} = {
        niri-config = pkgs.runCommand "niri-config-check" { nativeBuildInputs = [ pkgs.niri ]; } ''
          export HOME=$TMPDIR
          mkdir cfg
          cp ${./config/niri/config.kdl} cfg/config.kdl
          niri validate -c cfg/config.kdl
          # Again with the desktop's outputs in place of the optional include.
          cp ${./hosts/desktop/niri-outputs.kdl} cfg/host.kdl
          niri validate -c cfg/config.kdl
          # Again with Noctalia's colors: a bad one would stop niri loading its config.
          sed -E 's/\{\{[^}]*\}\}/#000000/g' \
            ${pkgs.noctalia}/share/noctalia/assets/templates/niri/niri.kdl > cfg/noctalia.kdl
          niri validate -c cfg/config.kdl
          touch $out
        '';

        # Sample commands against the hook, in all three outcomes. Exit 2 blocks;
        # exit 0 asks if the hook printed its JSON and allows if it printed nothing.
        git-guardrails =
          pkgs.runCommand "git-guardrails-check"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.jq
              ];
            }
            ''
              expect() {
                want=$1
                reply=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' \
                  | bash ${./config/claude/block-dangerous-git.sh} 2>/dev/null) && code=0 || code=$?
                got=allow
                if [ "$code" = 2 ]; then
                  got=block
                elif [ "$code" != 0 ]; then
                  got="exit $code"
                elif [ -n "$reply" ]; then
                  got=$(jq -r .hookSpecificOutput.permissionDecision <<<"$reply")
                fi
                if [ "$got" != "$want" ]; then
                  echo "want $want, got $got: $2" >&2
                  exit 1
                fi
              }

              expect ask 'git push'
              expect ask 'git push origin main'
              expect ask 'git -C /some/path push'
              expect ask 'git -C "/some path" push'
              expect ask 'git -c x=y push'
              expect ask 'git --no-pager push'
              expect ask 'git  push'
              expect ask 'git add . && git push'
              expect ask 'git push --dry-run'
              expect ask 'git push --follow-tags'
              expect ask 'git commit -m "explain git push"'
              expect ask 'bash -c "git push"'

              expect block 'git push --force'
              expect block 'git push -f origin main'
              expect block 'git push -uf origin main'
              expect block 'git push --force-with-lease'
              expect block 'git push origin +main'
              expect block 'git -C /some/path push --force'
              expect block 'git push --force --dry-run'
              expect block 'git reset --hard'
              expect block 'git reset --hard HEAD~1'
              expect block 'git -C /some/path reset --hard'
              expect block 'git clean -f'
              expect block 'git clean -fd'
              expect block 'git clean -xdf'
              expect block 'git branch -D topic'
              expect block 'git branch --delete --force topic'
              expect block 'git branch -d -f topic'
              expect block 'git checkout .'
              expect block 'git checkout -- .'
              expect block 'git restore .'
              expect block 'git restore --source=HEAD .'
              expect block 'git filter-repo --force'
              expect block 'git filter-branch'
              expect block 'git-filter-repo --force'
              expect block 'git push && git reset --hard'
              expect block 'bash -c "git push --force"'
              expect block 'bash -c "git checkout ."'

              expect allow 'git status'
              expect allow 'git log --oneline'
              expect allow 'git add .'
              expect allow 'git clean -n'
              expect allow 'git branch -d topic'
              expect allow 'git reset --soft HEAD~1'
              expect allow 'git checkout main'
              expect allow 'git restore file.txt'
              expect allow 'git pull --ff-only; git status -f'
              expect allow 'git push-foo'
              expect allow 'echo hi'

              touch $out
            '';

        noctalia-config =
          pkgs.runCommand "noctalia-config-check" { nativeBuildInputs = [ pkgs.noctalia ]; }
            ''
              export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_STATE_HOME=$TMPDIR/state
              noctalia config validate ${hm.xdg.configFile."noctalia/noctalia-config.toml".source}
              touch $out
            '';
      };
    };
}
