# nixos-config

NixOS configuration for my desktop and laptop: a flake with Home Manager as a
NixOS module. It replaces my Arch + GNU Stow
[dotfiles](https://github.com/jpierre-7/dotfiles). A fresh install becomes the
full system with one `nixos-install` (or `nixos-rebuild switch`).

- nixpkgs **nixos-26.05**, Home Manager **release-26.05** (keep them on the same release)
- Hosts: `desktop` and `laptop`; user `john` on both

| Piece | Choice |
|---|---|
| Compositor / shell | [Niri](https://github.com/YaLTeR/niri) + [Noctalia](https://noctalia.dev) |
| Login | cosmic-greeter (greetd), GNOME Keyring unlocked through PAM |
| Terminal, shell, prompt | WezTerm, Fish, Starship |
| Editor | Neovim with LazyVim; LSPs and formatters from Nix |
| Launcher | Vicinae |
| Boot | Limine (UEFI) |
| Network | NetworkManager, Tailscale, NixOS firewall |
| Sync | Syncthing (user service) |
| Keys | keyd: Caps Lock → Escape |
| Font | Maple Mono (+ Nerd Font builds), Noto, Noto Color Emoji |

## Layout

```
flake.nix               inputs, the two hosts, checks, formatter
overlays/default.nix    the only packages taken from nixpkgs-unstable
hosts/<host>/           default.nix (hostname-specific bits, stateVersion)
                        hardware-configuration.nix (generated on the machine)
                        niri-outputs.kdl (desktop only: monitor layout)
modules/nixos/          system modules (boot, networking, audio, desktop, ...)
modules/home/           Home Manager modules (shell, terminal, editor, apps, ...)
home/john.nix           my user's entry point
config/                 plain config files that the modules read or link
```

Shared settings live in `modules/`. A host's `default.nix` only holds what
differs on that machine.

### Store-managed vs. live configs

Most configs are built into the Nix store and linked read-only: edit the file
in this repo, then rebuild. A few are **live** symlinks into the checkout
(`config.lib.file.mkOutOfStoreSymlink`). Edits to those take effect at once,
and apps can write to them. This requires the repo to be cloned at
**`~/nixos-config`** (set as `repoDir` in `flake.nix`).

| Live (edit without rebuilding) | Why |
|---|---|
| `config/nvim/` → `~/.config/nvim` | Edit Lua without a rebuild; lazy.nvim writes `lazy-lock.json` |
| `config/claude/settings.json` → `~/.claude/settings.json` | Claude Code rewrites it (`/config`, `/model`, plugins) |
| `config/vicinae/settings.json` | Vicinae's GUI rewrites it |
| `config/herdr/config.toml` | herdr rewrites it |

Because apps write into these files, check `git status` for changes you
didn't make before you commit.

Noctalia is the exception that needs neither: its shared config is generated
read-only by `modules/home/noctalia.nix`, and anything changed in its GUI goes
to `~/.local/state/noctalia/settings.toml`, which overrides it. Per-monitor
settings belong in that state file, not in the repo.

## Fresh install (from the NixOS ISO)

The steps are the same for both machines; replace `desktop` with `laptop` as
needed.

1. **Boot the ISO in UEFI mode** with Secure Boot off (neither the ISO nor
   this Limine setup is signed; `ls /sys/firmware/efi` must succeed). Use the
   graphical or minimal ISO and get a shell as root:
   `sudo -i`. Get online: wired works automatically. For Wi-Fi on the graphical
   ISO, use the network applet. On the minimal ISO, use `nmtui` if it's there,
   otherwise `wpa_cli` (see the NixOS manual, "Networking in the installer").

2. **Partition** (UEFI, GPT). This wipes the disk. Find the disk name with
   `lsblk` and use it in place of `/dev/nvme0n1`. Make the ESP **1 GiB**:
   Limine keeps a kernel and initrd per generation on it. No swap partition is
   needed (zram is on).

   ```sh
   parted /dev/nvme0n1 -- mklabel gpt
   parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
   parted /dev/nvme0n1 -- set 1 esp on
   parted /dev/nvme0n1 -- mkpart root ext4 1GiB 100%
   mkfs.fat -F 32 -n boot /dev/nvme0n1p1
   mkfs.ext4 -L nixos /dev/nvme0n1p2
   mount /dev/disk/by-label/nixos /mnt
   mount --mkdir -o umask=077 /dev/disk/by-label/boot /mnt/boot
   ```

3. **Generate the hardware configuration** for this machine:

   ```sh
   nixos-generate-config --root /mnt
   ```

   It writes `/mnt/etc/nixos/hardware-configuration.nix` (filesystems, kernel
   modules, CPU microcode). Ignore the `configuration.nix` it writes beside it.

4. **Clone this repo** into the new home directory and put the generated file
   in place of the placeholder:

   ```sh
   nix-shell -p git
   git clone https://github.com/jpierre-7/nixos-config.git /mnt/home/john/nixos-config
   cd /mnt/home/john/nixos-config
   cp /mnt/etc/nixos/hardware-configuration.nix hosts/desktop/hardware-configuration.nix
   git add hosts/desktop/hardware-configuration.nix   # flakes only see files git tracks
   ```

   The committed `hardware-configuration.nix` files are placeholders. They
   evaluate, so `nix flake check` works before any machine exists, but a
   pre-switch check makes `nixos-install` and `nixos-rebuild` refuse to install
   them. If you see "still the placeholder", this step was skipped.

5. **Install:**

   ```sh
   nixos-install --flake /mnt/home/john/nixos-config#desktop
   ```

   It asks for a root password at the end.

6. **Set your user password** (no passwords live in this repo) and give
   yourself the checkout:

   ```sh
   nixos-enter --root /mnt -c 'passwd john'
   nixos-enter --root /mnt -c 'chown -R john:users /home/john/nixos-config'
   reboot
   ```

7. **Commit the hardware configuration** after logging in, so the next install
   of this machine has it. If `flake.lock` didn't exist yet, `nixos-install`
   created it; commit it too, and install the other machine after pushing, so
   both get the same versions:

   ```sh
   cd ~/nixos-config
   gh auth login
   git add flake.lock hosts/desktop/hardware-configuration.nix
   git commit -m "Add desktop hardware configuration"
   git push
   ```

### One-time steps after the first login

These need an account or a login, so they can't be declared:

- `sudo tailscale up`: log the machine into your tailnet
- `claude`: log in to Claude Code
- `herdr integration install claude`: writes `~/.claude/hooks/herdr-agent-state.sh`,
  which the SessionStart hook in `config/claude/settings.json` runs. If it
  rewrites `settings.json`, review the diff.
- Syncthing: open http://127.0.0.1:8384 and pair the two machines (device IDs
  are per machine).
- Open `nvim` once and let lazy.nvim install plugins.

## Everyday use

Rebuild after changing anything (the hostname picks the matching config):

```sh
sudo nixos-rebuild switch --flake ~/nixos-config        # same as #desktop on the desktop
sudo nixos-rebuild switch --flake ~/nixos-config#laptop # explicit
```

Home Manager is part of the system build, so this updates your dotfiles too.
Use `nixos-rebuild boot` instead of `switch` to apply on the next reboot.

### Routine updates

```sh
cd ~/nixos-config
nix flake update                       # all inputs
nix flake update nixpkgs-unstable      # or one input
sudo nixos-rebuild switch --flake .
git commit -am "Update flake inputs"
```

`flake.lock` pins every input to an exact commit, so both machines run the
same versions once you pull the updated lock file. Stable gets security fixes
and minor updates; the unstable exceptions get whatever is new.

### Upgrading to the next NixOS release

NixOS releases come out in May and November (26.05 → 26.11 → 27.05).

1. Read the release notes (NixOS manual → Release Notes) for breaking changes.
2. In `flake.nix`, bump **both** branches together:
   `nixos-26.05` → `nixos-26.11` and `release-26.05` → `release-26.11`.
3. `nix flake update`, then `sudo nixos-rebuild switch --flake .` and fix any
   evaluation errors or warnings.
4. **Leave `system.stateVersion` (in `hosts/*/default.nix`) and
   `home.stateVersion` (in `home/john.nix`) at `"26.05"`.** They record the
   release each machine was first installed with, so stateful services
   (databases, data formats) keep working. They are not the version you run.
   Change them only after reading what the release notes say would migrate.

### Adding a package

1. Find its attribute name: `nix search nixpkgs <name>` or https://search.nixos.org/packages
   (channel 26.05).
2. Add it to the module where it fits, e.g. `home.packages` in
   `modules/home/apps.nix` for a GUI app or `modules/home/dev.nix` for a tool.
   System-wide things go in `environment.systemPackages` in `modules/nixos/`.
   If Home Manager has a `programs.<name>` module for it, prefer that.
3. Rebuild, then commit.

If it's missing or too old on stable, add it to the `inherit (unstable)` list in
`overlays/default.nix` (and to the table below) instead of moving the whole
system to unstable.

For a one-off without installing: `nix shell nixpkgs#<name>` or
`nix run nixpkgs#<name>`.

### Rolling back

Every rebuild is a new generation, and older ones stay until garbage collection
(weekly, keeps the last 14 days; see `modules/nixos/nix.nix`).

```sh
sudo nixos-rebuild switch --rollback          # back to the previous generation
nixos-rebuild list-generations                # see what's there
```

If the system doesn't boot, pick an older generation in the Limine menu (up to
10 are listed). Home Manager rolls back with the system, because it is part of
the same generation. To undo a change for good, `git revert` it and rebuild.

### Checking changes

```sh
nix flake check     # evaluates both hosts; validates the niri and Noctalia configs
nix build .#nixosConfigurations.desktop.config.system.build.toplevel
nix build .#nixosConfigurations.laptop.config.system.build.toplevel
nix fmt             # nixfmt on every .nix file
```

## Unstable exceptions

Everything comes from stable except these, pulled from `nixpkgs-unstable` in
`overlays/default.nix`:

| Package | Why |
|---|---|
| `noctalia` | Noctalia v5; stable has 5.0.1, unstable follows the 5.x releases |
| `herdr` | Not packaged on stable |
| `claude-code` | Ships several times a week; stable is months behind |

## How the Arch setup maps

Packages from the old `packages/pacman.txt` map to nixpkgs packages or NixOS /
Home Manager modules of the same name (`programs.fish`, `services.keyd`,
`services.tailscale`, ...). The cases that need a note:

| Arch (AUR / other) | Here |
|---|---|
| `vesktop` (AUR) | nixpkgs `vesktop`, wrapped to always pass `--disable-gpu` (`modules/home/apps.nix`) |
| `vicinae-bin` (AUR) | nixpkgs `vicinae` (stable, 0.23.x) |
| `maplemono-ttf`, `maplemono-nf-unhinted`, `maplemono-nf-cn-unhinted` (AUR) | `maple-mono.truetype`, `.NF-unhinted`, `.NF-CN-unhinted` |
| `visual-studio-code-bin`, `slack-desktop`, `anydesk-bin` (AUR) | `vscode`, `slack`, `anydesk` (unfree; allowed in `modules/nixos/nix.nix`) |
| `onlyoffice-bin` (AUR) | `onlyoffice-desktopeditors`. X11-only; runs through xwayland-satellite. For Microsoft-font documents, add `corefonts` to `fonts.packages`. |
| `quarto-cli-bin` (AUR) | Dropped, along with Molten, image.nvim and quarto-nvim: notebooks moved to Colab |
| Claude Code, herdr (curl installers) | `claude-code`, `herdr` from unstable; update with `nix flake update`, not self-update |
| `pyroclear` (cargo) | Dropped |
| Molten's Python venv (pip) | Dropped with Molten |
| `rustup` | nixpkgs `cargo`, `rustc`, `rust-analyzer`, `clippy`, `rustfmt` (per-project toolchains: a flake devShell) |
| `noto-fonts-emoji` | `noto-fonts-color-emoji` (the old name is an error on 26.05) |
| `yay`, `stow`, `base-devel` | Dropped; Home Manager replaces Stow, `gcc`/`gnumake`/`pkg-config` remain |
| `grub`, `efibootmgr` | Limine (`modules/nixos/boot.nix`) |
| `firewalld` | NixOS firewall (`networking.firewall`) |
| `zram-generator` | `zramSwap.enable` |
| GPU driver packages | Mesa only (`hardware.graphics.enable`); see "Graphics" below |
| archinstall's Niri profile (alacritty, fuzzel, mako, swaybg, swayidle, swaylock, waybar), `network-manager-applet` | Dropped: Noctalia covers bar, notifications, wallpaper, lock screen and network |
| Wallpapers `git clone` | `wallpapers` flake input, linked to `~/Pictures/Wallpapers` |

Behavior that changed on the way over:

- `spawn-at-startup "xwayland-satellite"` is gone from the niri config. Niri
  starts it itself when an X11 app connects, and a second copy would clash.
- Neovim: Mason is disabled (`config/nvim/lua/plugins/nix.lua`). Language
  servers, formatters and linters are on Neovim's PATH from
  `modules/home/neovim.nix`. A LazyVim extra that needs a new tool means
  adding its nixpkgs package there.
- Starship starts in every interactive fish shell, not only login shells.
- The lsd config keeps only what changed lsd's output: `colors.yaml` had no
  effect (`color.theme: default`), and `icons.yaml` differed from the defaults
  only in the folder icon.

## Python projects

Pip wheels with compiled code (numpy, pandas, ...) can't load against Nix's
Python. Make project venvs with **uv**, which uses its own downloaded Python
builds; nix-ld (`modules/nixos/nix-ld.nix`) lets those run.
`UV_PYTHON_PREFERENCE=only-managed` is set, so uv never picks Nix's Python.

```fish
cd ~/Projects/foo
uv venv --seed venv            # --seed adds pip, for tools that call it
source venv/bin/activate.fish
uv pip install numpy pandas    # or plain `pip install`
```

For projects that need system libraries, a `flake.nix` with a devShell is the
NixOS way.

## Graphics

Both machines use Mesa (`hardware.graphics.enable` in
`modules/nixos/desktop.nix`), which runs AMD and Intel GPUs with no extra
driver. If a machine turns out to have an NVIDIA GPU that should use NVIDIA's
driver, add this to that host's `default.nix` (not to the shared modules):

```nix
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia.open = true;   # Turing (GTX 16xx / RTX 20xx) and newer
```

On a hybrid laptop, also set `hardware.nvidia.prime` with the bus IDs from
`lspci` (see the NixOS wiki page "NVIDIA").

## Secrets

The repo is public and contains no secrets, passwords or tokens. Things that
need one are done by hand after install (user password, `tailscale up`,
`gh auth login`, Claude Code login, Syncthing pairing).

To declare any of them later, use [sops-nix](https://github.com/Mic92/sops-nix)
or [agenix](https://github.com/ryantm/agenix). Both keep secrets encrypted in
the repo and decrypt them on the machine at activation time. Examples:
`users.users.john.hashedPasswordFile`,
`services.tailscale.authKeyFile`. Never put a secret in a plain Nix string: it
ends up world-readable in `/nix/store`.
