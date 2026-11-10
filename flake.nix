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
          # The login screen's niri (modules/nixos/greeter.nix), with each host's outputs.
          niri validate -c ${self.nixosConfigurations.desktop.config.environment.etc."greetd/niri.kdl".source}
          niri validate -c ${self.nixosConfigurations.laptop.config.environment.etc."greetd/niri.kdl".source}
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
                pkgs.shfmt
              ];
            }
            ''
              # Same shell options as writeShellApplication in modules/home/claude.nix.
              expect() {
                want=$1
                reply=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' \
                  | bash -euo pipefail ${./config/claude/block-dangerous-git.sh} 2>/dev/null) && code=0 || code=$?
                got=allow
                if [ "$code" = 2 ]; then
                  got=block
                elif [ "$code" != 0 ]; then
                  got="exit $code"
                elif [ -n "$reply" ]; then
                  got=$(jq -r .hookSpecificOutput.permissionDecision <<<"$reply")
                fi
                # One row per case, newlines shown as \n: `nix log` prints the table.
                if [ "$got" = "$want" ]; then
                  printf 'ok    %-5s %s\n' "$got" "''${2//$'\n'/\\n}"
                else
                  printf 'FAIL  %-5s %s (want %s)\n' "$got" "''${2//$'\n'/\\n}" "$want"
                  failed=1
                fi
              }
              failed=0

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
              expect ask 'bash -c "git push"'
              expect ask 'sh -c '"'"'git status && git push'"'"
              expect ask 'sudo -u john bash -c "git push"'
              expect ask 'eval "git push origin main"'
              expect ask 'bash <<< "git push"'
              expect ask $'bash <<\'EOF\'\ncd /repo\ngit push\nEOF'
              expect ask $'bash -s <<EOF\ngit push origin "$branch"\nEOF'
              expect ask 'echo "git push" | bash'
              expect ask 'cmd="git push"; bash -c "$cmd"'
              expect ask $'cat <<EOF\n$(git push)\nEOF'
              expect ask 'echo "$(git push)"'
              expect ask 'env GIT_TRACE=1 git push'
              expect ask 'timeout 60 git push'
              expect ask '/usr/bin/git push'
              expect ask 'ssh host "cd repo && git push"'
              expect ask 'herdr pane run 1 "git push"'
              expect ask $'git \\\npush'

              # Shell code the hook can't read asks, even with no git in sight.
              expect ask 'bash -c "$cmd"'
              expect ask 'eval "$(some-tool)"'
              expect ask 'curl -s https://example.com/x.sh | sh'

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
              expect block $'bash <<\'EOF\'\ngit reset --hard\nEOF'
              expect block 'eval "git clean -fd"'
              expect block 'sh -c "bash -c '"'"'git push --force'"'"'"'
              expect block 'echo "$(git reset --hard)"'
              expect block 'xargs git branch -D'
              expect block 'ssh host git push --force'
              expect block 'echo "git reset --hard" | bash'
              expect block 'git rebase -x "git push --force" main'

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

              # Text that only mentions a command: heredoc bodies, quoted strings.
              expect allow $'python3 - <<\'EOF\'\n# the Claude hook that asks before a git push\nprint("ok")\nEOF'
              expect allow $'cat > notes.md <<\'EOF\'\nNever run git reset --hard here.\nEOF'
              expect allow 'git commit -m "Explain why git reset --hard was wrong"'
              expect allow 'git commit -m "explain git push"'
              expect allow $'git commit -F - <<\'EOF\'\nStop git push --force\nEOF'
              expect allow 'gh issue create --title x --body "never git push --force"'
              expect allow 'echo "git push --force" > notes.txt'
              expect allow 'grep -rn "git reset --hard" config'
              expect allow 'git log --grep="reset --hard"'
              expect allow 'bash scripts/build.sh'
              expect allow 'bash -c "git status"'
              expect allow 'bash -c '"'"'git commit -m "no git push here"'"'"
              expect allow $'bash <<\'EOF\'\necho "git push"\nEOF'
              expect allow 'git rebase -i main'

              expect ask 'gh pr merge 1 --rebase'
              expect ask 'gh repo delete some/repo --yes'
              expect ask 'gh repo edit --visibility public'
              expect ask 'gh issue delete 1'
              expect ask 'gh release delete v1'
              expect ask 'gh secret set TOKEN'
              expect ask 'gh api -X DELETE repos/some/repo'
              expect ask 'gh api --method=PUT repos/some/repo/branches/main/protection'
              expect ask 'gh api repos/some/repo/issues -f title=x'
              expect ask 'cd /tmp && gh pr merge 1'

              expect allow 'gh pr view 1'
              expect allow 'gh pr create --fill'
              expect allow 'gh issue create --title x --body y'
              expect allow 'gh repo view some/repo'
              expect allow 'gh api repos/some/repo --jq .state'
              expect allow 'gh api -X GET repos/some/repo'
              expect allow 'gh run list; echo pr merge'

              [ "$failed" = 0 ]
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
