# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NixOS flake for two hosts (`desktop`, `laptop`), user `john`, with Home Manager as a NixOS module. The README is the user-facing manual (install, everyday use, the Arch-to-NixOS mapping). Keep it accurate when behavior changes.

## Commands

```sh
nix flake check     # evaluates both hosts, runs the niri and Noctalia config checks
nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # full build of one host, no activation
nix fmt             # nixfmt-tree over every .nix file
sudo nixos-rebuild switch --flake ~/nixos-config        # apply on this machine (fish abbr: nrs)
```

- **Flakes only see files git tracks.** A new file has to be `git add`ed before `nix flake check` or a build can see it. Otherwise you get "path does not exist" errors.
- `nixos-rebuild` needs sudo and changes the running system. Ask before you run it. `nix flake check` and `nix build` are safe ways to verify a change.
- `nix flake update [input]` changes `flake.lock`. Do it only when asked.

## Architecture

- `flake.nix` `mkHost` builds each host from `hosts/<host>/` + `modules/nixos/` + Home Manager, which loads `home/john.nix` → `modules/home/`. `modules/*/default.nix` are plain import lists. Add new modules there.
- Module args: NixOS modules get `inputs` (`specialArgs`). Home Manager modules get `inputs` and `repoDir` (`extraSpecialArgs`). `useGlobalPkgs = true`, so HM uses the system `pkgs`, overlay included.
- Shared settings go in `modules/`. A host's `default.nix` holds only what differs on that machine. Host-specific HM settings go there under `home-manager.users.john.*` (example: the desktop links `niri/host.kdl`).
- `config/` holds plain config files that modules read (`builtins.readFile`, `lib.importTOML`/`importJSON`) or link.
- `pkgs/` holds local derivations, called with `pkgs.callPackage` from the module that uses them. Their source is a pinned `flake = false` input (e.g. `librepods`).

### Store-managed vs. live configs

Most configs are copied into the Nix store. You must rebuild before an edit takes effect. A few are live symlinks into the checkout via `config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/..."`, so edits take effect at once and apps can write to them:

- `config/nvim/` (lazy.nvim rewrites `lazy-lock.json`)
- `config/claude/settings.json` (Claude Code rewrites it)
- `config/vicinae/settings.json`, `config/herdr/config.toml` (their apps rewrite them)

This requires the repo at `/home/john/nixos-config` (`repoDir` in `flake.nix`). Because apps write into these files, `git status` can show changes nobody made by hand. Check the diff before you commit them.

Noctalia is different. `modules/home/noctalia.nix` generates its shared config read-only from a Nix attrset. GUI changes go to `~/.local/state/noctalia/settings.toml`, and per-monitor settings belong there, not in the repo.

### Package sources

- Everything comes from stable nixpkgs (`nixos-26.05`) except the short `inherit (unstable)` list in `overlays/default.nix`. To get a missing or outdated package, add it there. Do not move the system to unstable. Update the README's "Unstable exceptions" table when that list changes.
- nixpkgs and Home Manager must stay on the same release (`nixos-YY.MM` / `release-YY.MM`). Bump both together.
- Never change `system.stateVersion` (`hosts/*/default.nix`) or `home.stateVersion` (`home/john.nix`) on upgrades.
- Prefer a Home Manager `programs.<name>` module over a bare `home.packages` entry when one exists.

### Things that cross files

- **Neovim**: Mason is disabled (`config/nvim/lua/plugins/nix.lua`). Every LSP, formatter, and linter LazyVim uses has to be in `programs.neovim.extraPackages` in `modules/home/neovim.nix`. A new LazyVim extra means adding its tools there. `pyright` and `rust-analyzer` are in `modules/home/dev.nix` instead, because Claude Code's LSP plugins use them too.
- **Niri**: `config/niri/config.kdl` ends with `include optional=true "host.kdl"`. The desktop fills it with `hosts/desktop/niri-outputs.kdl`. The laptop has none. The `niri-config` check validates both cases, so keep `config.kdl` valid with and without the include. Niri starts `xwayland-satellite` on demand, so do not add it to `spawn-at-startup`.
- **Noctalia plugins**: a plugin's `dependencies` (in its `plugin.toml`, under `~/.local/state/noctalia/plugins/materialized/`) are commands it runs from PATH. Noctalia doesn't install them. They go in `home.packages` in `modules/home/noctalia.nix`, except `gpu-screen-recorder`, which needs the capability wrapper from `programs.gpu-screen-recorder` in `modules/nixos/desktop.nix`. `harveywuk/airpods` depends on the librepods daemon from `modules/home/airpods.nix` + `pkgs/librepods.nix`.
- **Claude Code skills**: `config/claude/skills/` is vendored (HM links each skill file by file). `config/claude/skills-lock.json` pins each skill's source commit. To refresh a skill, re-copy it from source and update the pin.
- **Firewall**: Syncthing runs as a HM user service and can't open ports. Its ports are in `modules/nixos/networking.nix`.
- **Python**: project venvs use `uv` with managed Pythons (`UV_PYTHON_PREFERENCE=only-managed`), which run through nix-ld. Don't add pip-installed native packages to Nix's Python.

## Conventions

- The repo is public. No secrets, passwords, or tokens in Nix code. They would also become world-readable in `/nix/store`. Secrets are set by hand after install, or later through sops-nix/agenix.
- Comments explain *why* (often the Arch behavior being reproduced or a bug being worked around) and point to the related file. Follow the same style.
- Commit messages: short imperative subject, then a body that explains the reason for the change.
