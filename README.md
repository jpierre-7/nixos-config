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
| Login | Omarchy-style Quickshell greeter on greetd, GNOME Keyring unlocked through PAM |
| Terminal, shell, prompt | WezTerm, Fish, Starship |
| Editor | Neovim with LazyVim; LSPs and formatters from Nix |
| Launcher | Vicinae |
| Boot | Limine (UEFI) |
| Network | NetworkManager, Tailscale, NixOS firewall |
| Sync | Syncthing (user service) |
| Mouse, keyboard, clipboard sharing | Lan Mouse + lan-clip, over the tailnet |
| Keys | kanata: home-row mods, Caps Lock → Escape (`config/kanata/keymap.kbd`) |
| Font | Maple Mono (+ Nerd Font builds), Noto, Noto Color Emoji |

## Layout

```
flake.nix               inputs, the two hosts, checks, formatter
overlays/default.nix    the only packages not taken from stable nixpkgs
pkgs/                   local derivations (librepods, lan-clip)
hosts/<host>/           default.nix (hostname-specific bits, stateVersion)
                        hardware-configuration.nix (generated on the machine)
                        niri-outputs.kdl (desktop only: monitor layout)
                        lan-mouse.toml (screen side and trusted peer)
secrets/                encrypted secrets and who can read them (see SECURITY.md)
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
| `config/claude/settings.json` → `~/.claude/settings.json` | Claude Code rewrites it (`/config`, `/model`, plugins). Linked directly by an activation script, because its writes fail through a store link |
| `config/claude/keybindings.json` → `~/.claude/keybindings.json` | `/keybindings` opens it for editing |
| `config/claude/CLAUDE.md` → `~/.claude/CLAUDE.md` | `/memory` opens it for editing |
| `config/claude/rules/pstack-models.md` → `~/.claude/rules/pstack-models.md` | `/pstack:setup-pstack` rewrites it. Linked directly by an activation script, like `settings.json` |
| `config/vicinae/settings.json` | Vicinae's GUI rewrites it |
| `config/herdr/config.toml` | herdr rewrites it |

Because apps write into these files, check `git status` for changes you
didn't make before you commit.

Noctalia is the exception that needs neither: its shared config is generated
read-only by `modules/home/noctalia.nix`, and anything changed in its GUI goes
to `~/.local/state/noctalia/settings.toml`, which overrides it. Per-monitor
settings belong in that state file, not in the repo.

Two things follow from that:

- A key set in the state file replaces the repo's value as a whole. Enabling
  one plugin in the GUI saves the machine's entire `plugins.enabled` list
  there, so plugins added to the repo later never reach that machine. To
  share a GUI change, copy it into `noctalia.nix` and delete the key from the
  state file.
- Noctalia downloads enabled plugins only when it starts. After a rebuild
  that adds a plugin, log out and back in (or restart Noctalia) before its
  widget shows up.

The window rims, terminal, prompt, editor, launcher, screensaver and Claude
Code (theme and status line) take their colors from Noctalia. `noctalia.nix` registers a template
for each, and Noctalia renders them again each time its palette changes (new
wallpaper, palette source, scheme or light/dark mode):

| Output | Template | Picked up by |
|---|---|---|
| `~/.config/niri/noctalia.kdl` | Noctalia's niri template | `config/niri/config.kdl` includes it; niri reloads when it changes |
| `~/.config/wezterm/colors/Noctalia.toml` | Noctalia's WezTerm template | `wezterm.lua` loads it and reloads when it changes |
| `~/.config/starship.toml` | `config/starship.toml` | Starship, on the next prompt |
| `~/.config/nvim/colors/noctalia.lua` (gitignored) | community `lazyvim` | LazyVim's colorscheme; open Neovims reload on SIGUSR1 |
| `~/.local/share/vicinae/themes/noctalia.toml` | community `vicinae` | Vicinae, through `vicinae theme set noctalia` |
| `~/.claude/themes/noctalia.json` | community `claude-code` | Claude Code (`"theme": "custom:noctalia"` in `config/claude/settings.json`), on change |
| `~/.cache/noctalia/claude-statusline-colors.sh` | `config/claude/statusline-colors.sh` | `statusline.sh`, on its next update |
| `~/.cache/noctalia/screensaver-colors.sh` | `config/screensaver/colors.sh` | The [idle screensaver](#idle-screensaver), when it starts |

herdr uses its built-in `terminal` theme, which draws with WezTerm's colors,
so it follows along without a template. Its
[agent cards](#agent-cards-in-herdr) read WezTerm's `colors/Noctalia.toml`
directly. The community templates come from the `noctalia-templates` flake
input; `nix flake update noctalia-templates`
refreshes them.

The outputs are Noctalia's, so don't edit them. `config/starship.toml` is the
whole prompt config, with the palette as template placeholders, so Home
Manager doesn't link `starship.toml`: to change the prompt, edit the repo
file and rebuild. If an output looks stale, run `noctalia msg
templates-apply`. Don't enable the matching templates under Noctalia's
Templates page. Their hooks edit the apps' configs in place, which fails on
the read-only ones and rewrites the live ones in this repo.

## Fresh install (from the NixOS ISO)

The steps are the same for both machines. Every command reads the machine from
`$host`, so the blocks can be pasted as they are.

1. **Boot the ISO in UEFI mode** with Secure Boot off (neither the ISO nor
   this Limine setup is signed; `ls /sys/firmware/efi` must succeed). Use the
   graphical or minimal ISO and get a shell as root:
   `sudo -i`. Get online: wired works automatically. For Wi-Fi on the graphical
   ISO, use the network applet. On the minimal ISO, use `nmtui` if it's there,
   otherwise `wpa_cli` (see the NixOS manual, "Networking in the installer").
   Then name the machine you are installing:

   ```sh
   host=laptop    # or: host=desktop
   ```

   If it has an NVIDIA GPU, read "Graphics" below first.

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

3. **Clone this repo and generate the hardware configuration** (filesystems,
   kernel modules, CPU microcode) straight into it. The ISO has git.

   ```sh
   git clone https://github.com/jpierre-7/nixos-config.git /mnt/home/john/nixos-config
   cd /mnt/home/john/nixos-config
   nixos-generate-config --root /mnt --show-hardware-config > hosts/$host/hardware-configuration.nix
   git add hosts/$host/hardware-configuration.nix   # flakes only see files git tracks
   ```

   Don't skip this on a reinstall. The committed `hardware-configuration.nix`
   is from the machine's previous install and mounts filesystems by UUID.
   Formatting gave the partitions new UUIDs, so the old file still installs
   but the system can't find its disks at boot.

4. **Delete old Limine boot entries.** The firmware keeps its boot entries
   when the disk is wiped. If one named `Limine` is left from an earlier
   install, NixOS reuses it at its old place in the boot order instead of
   putting Limine first, and the machine keeps booting something else. With no
   old entry, the new one goes first.

   ```sh
   for n in $(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Limine.*/\1/p'); do efibootmgr -q -b $n -B; done
   ```

5. **Install:**

   ```sh
   nixos-install --flake /mnt/home/john/nixos-config#$host
   ```

   It asks for a root password at the end.

6. **Set your user password** (no passwords live in this repo) and give
   yourself the checkout:

   ```sh
   nixos-enter --root /mnt -c 'passwd john'
   nixos-enter --root /mnt -c 'chown -R john:users /home/john/nixos-config'
   reboot
   ```

   You should get the Limine menu, then the login screen, then niri.
   If the machine starts something else instead, open the firmware setup
   (usually F2 or Del at power-on) and make Limine the first boot option. The
   desktop's firmware ignored boot-order changes made from Linux.

7. **Commit the hardware configuration** after logging in, so the next install
   of this machine has it. `gh auth login` also sets up git to push over HTTPS.

   ```sh
   cd ~/nixos-config
   gh auth login
   git add hosts/*/hardware-configuration.nix
   git commit -m "Add hardware configuration"
   git push
   ```

### Already installed with the graphical installer

This is how the desktop was set up. It works, with a few extra steps:

- Name the installer's user **`john`**. This config declares only `john`, and
  the first rebuild deletes any other account the installer created.
- Clone and generate the hardware configuration as above, without `--root`.
  The installed system has no git yet, so get a shell with it first:

  ```sh
  nix-shell -p git
  git clone https://github.com/jpierre-7/nixos-config.git ~/nixos-config
  cd ~/nixos-config
  nixos-generate-config --show-hardware-config > hosts/laptop/hardware-configuration.nix
  git add hosts/laptop/hardware-configuration.nix
  ```

- In a terminal window (sudo can't ask for a password elsewhere), apply it for
  the next boot. A live `switch` would end the GNOME session, and the boot
  loader changes from systemd-boot to Limine:

  ```sh
  sudo nixos-rebuild boot --flake ~/nixos-config#laptop
  reboot
  ```

- If you still get systemd-boot's menu (GNOME entries), make Limine the first
  boot option in the firmware setup.
- `sudo rm /etc/nixos/configuration.nix`, so a rebuild without `--flake` fails
  instead of bringing GNOME back. Then commit as in step 7.

### One-time steps after the first login

These need an account or a login, so they can't be declared:

- Copy `~/.ssh/id_ed25519` from the other machine before rebuilding again, so
  agenix can decrypt secrets (see [SECURITY.md](SECURITY.md)).
- `nix develop` in `~/nixos-config`: installs the pre-commit leak check. You can
  leave the shell right after.
- `sudo tailscale up`: log the machine into your tailnet
- `claude`: log in to Claude Code
- `herdr integration install claude`: writes `~/.claude/hooks/herdr-agent-state.sh`,
  which the SessionStart hook in `config/claude/settings.json` runs. If it
  rewrites `settings.json`, review the diff.
- Syncthing: open http://127.0.0.1:8384 and pair the two machines (device IDs
  are per machine). Don't share `~/nixos-config` there; git keeps it in sync
  (see [Everyday use](#everyday-use)).
- Lan Mouse: trust each machine's certificate on the other one (see
  [Sharing the mouse and keyboard](#sharing-the-mouse-and-keyboard)).
- Open `nvim` once and let lazy.nvim install plugins. It installs the commits
  in `config/nvim/lazy-lock.json`. `:Lazy update` and `:Lazy sync` (`U`/`S` in
  its window) move past them; commit the lock file after updating on purpose,
  or `:Lazy restore` to go back.
- Vivaldi downloads its media codecs on first start; restart it when it asks.
- rbw (Bitwarden for qutebrowser): `rbw config set email <your Bitwarden email>`,
  then `rbw login`. The email stays out of the repo (see
  [qutebrowser](#qutebrowser)).
- Wake-on-LAN (desktop): in the firmware setup, turn on wake from LAN/PCIe
  ("Power On By PCI-E", "Wake on LAN") and turn off ErP / deep sleep, which
  cuts power to the NIC. See [Waking the desktop](#waking-the-desktop) for the
  router side.

## Everyday use

Rebuild after changing anything (the hostname picks the matching config):

```sh
sudo nixos-rebuild switch --flake ~/nixos-config        # same as #desktop on the desktop
sudo nixos-rebuild switch --flake ~/nixos-config#laptop # explicit
```

Home Manager is part of the system build, so this updates your dotfiles too.
Use `nixos-rebuild boot` instead of `switch` to apply on the next reboot.
The fish abbreviation `nrs` expands to the first line.

### Login screen

The login screen copies the look of [Omarchy](https://github.com/basecamp/omarchy)'s
SDDM theme: the hostname in large letters over a lock and an outlined password
box. Type the password and press Enter; Escape clears it. The box and lock turn
red after a wrong password. There is no user or session to pick: it logs `john`
into niri. To power off from it, press the power button.

greetd runs it as a niri of its own with a Quickshell greeter as the only
client (`modules/nixos/greeter.nix`, `config/greeter/`). That niri has no key
binds and gets the host's monitor layout. The other machine's mouse and keyboard
reach it through Lan Mouse (see [Sharing the mouse and
keyboard](#sharing-the-mouse-and-keyboard)). Colors are Noctalia's: Noctalia
renders them to `/var/lib/greeter-palette/palette.json`, outside your home so
the greeter user can read it. Until it has run once, the greeter uses Omarchy's
Tokyo Night colors.

If the login screen is broken, press Ctrl+Alt+F2 for a text login, then
`sudo nixos-rebuild switch --rollback`, or pick the previous generation in the
Limine menu (see [Rolling back](#rolling-back)).

### Keeping both machines in sync

Git is the only sync for this repo. Commit and push from the machine where you
made the change, then on the other one:

```sh
nup   # git pull, then nixos-rebuild switch
```

Each machine has to rebuild on its own; pulling only changes the files.

### Waking the desktop

From the laptop, at home or away:

```sh
wake-desktop && ssh john@desktop
```

The desktop arms Wake-on-LAN on its wired ports (`hosts/desktop/default.nix`).
A magic packet only travels inside the home LAN, so `wake-desktop`
(`hosts/laptop/default.nix`) SSHes into the router over Tailscale and has it
send one with `etherwake`, then waits until the desktop answers
`tailscale ping`. It wakes from shutdown and from suspend, but not after a
power cut until the desktop has been switched on once.

One-time router setup (GL.iNet GL-BE9300, which is in the tailnet):

1. Admin panel → System → Advanced Settings opens LuCI (install it if asked).
   There, System → Administration → SSH-Keys: add the laptop's
   `~/.ssh/id_ed25519.pub`.
2. SSH into the router and run `opkg update && opkg install etherwake` if
   `etherwake` isn't there yet. Firmware upgrades can remove it. The login is
   line 1 of `/run/agenix/wake-desktop`.
3. Test from the laptop while the desktop is off: `wake-desktop`.

If `wake-desktop` times out while `tailscale ping` still answers, the router is
dropping what arrives over Tailscale. Turning off Enable in its admin panel
(Applications → Tailscale), applying, then turning it back on fixed this once.
The restart also cleared Run Exit Node and the two Advertise toggles, so check
them afterwards.

### Sharing the mouse and keyboard

[Lan Mouse](https://github.com/feschber/lan-mouse) moves the cursor between the
machines across a screen edge: the laptop sits below the desktop. To move it,
change `position` in both `hosts/*/lan-mouse.toml`. Left Ctrl+Shift+Super+Alt
brings a stuck cursor back.

Each machine generates its own certificate on first start and rejects the other
until it trusts it. On each machine, print the fingerprint:

```sh
nix shell nixpkgs#openssl -c openssl x509 -in ~/.config/lan-mouse/lan-mouse.pem -outform DER | sha256sum | cut -d' ' -f1 | sed 's/../&:/g; s/:$//'
```

Add it under `[authorized_fingerprints]` in the *other* host's `lan-mouse.toml`
as `"<fingerprint>" = "<hostname>"`. Fingerprints aren't secret; never commit
`lan-mouse.pem`, which holds the private key. A reinstall generates a new
certificate, so update its fingerprint on the other host; until then the
machines reject each other.

Traffic stays on the tailnet: UDP 4242 is open only on `tailscale0`, and the
peers are addressed by their tailnet hostnames. Lan Mouse's sender doesn't verify
the receiver's certificate, so WireGuard does that part.

Both daemons run as user services, so they start when you log in. The login
screen runs a Lan Mouse of its own (`modules/nixos/greeter.nix`) that only
receives: cross over from the logged-in machine and type the password. It trusts
the same fingerprints as the host's `lan-mouse.toml` and has its own certificate
in `/var/lib/greeter`, which the sender doesn't check, so there's nothing to add
on the other host. It never sends the login screen's input away, and lan-clip
doesn't run there. The lock screen works too. Suspend doesn't, including
Noctalia's "Lock and suspend": use that machine's own keyboard to wake it.

[lan-clip](https://github.com/johanjongsma/lan-clip) adds clipboard sharing: every
copy of text, HTML or a PNG goes to the other machine at once, over TCP 4243 on
the tailnet, using Lan Mouse's certificates. Files aren't shared. Copies marked
`x-kde-passwordManagerHint` stay local, which covers the Noctalia Bitwarden
plugin. A password copied from something that doesn't set that type, such as a
browser extension, does get sent. `lan-clip status` shows the peer and the last
sync; `lan-clip pause` and `lan-clip resume` turn sharing off and on until the
daemon restarts.

The `lan-clip` flake input is pinned to a reviewed commit, because the daemon
reads the private key and every copy. Read the diff before moving it.

### Idle screensaver

After 5 idle minutes the NixOS logo plays on every monitor, animated by
[terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects) in
fullscreen WezTerms, as on [Omarchy](https://github.com/basecamp/omarchy). Each
round picks a random effect, in the current Noctalia colors. Any key or mouse
move locks the session first and then ends the screensaver, so it never leads
back to an unlocked desktop. After 15 idle minutes the session locks and the
monitors go off; at the lock screen they go off after one idle minute.

Noctalia's idle settings run it (`idle` in `modules/home/noctalia.nix`); there is
no other idle daemon. Its caffeine toggle and apps that inhibit idle (video)
hold it off. `nixos-screensaver start` shows it right away and
`nixos-screensaver stop` locks and ends it. The script is
`config/screensaver/screensaver.sh`, the logo `config/screensaver/nixos-logo.txt`
(from `fastfetch --print-logos`).

The shared mouse and keyboard count as input on the idle machine, so crossing
over with Lan Mouse wakes it and types the password. The lock screen hides Lan
Mouse's edge, so the cursor can't cross back until that machine is unlocked;
Left Ctrl+Shift+Super+Alt brings it back.

### qutebrowser

A keyboard-driven second browser; Vivaldi stays the default. The config is in
`modules/home/qutebrowser.nix`, with ideas from
[HefKer's](https://github.com/HefKer/dots/tree/main/qutebrowser). Its colors
follow Noctalia like the other apps.

**Bitwarden.** [qutewarden](https://github.com/HefKer/qutewarden) fills from
the vault through `rbw`. It matches Items by URI, not by name. The picker is
Vicinae, and the master password prompt is pinentry-qt. Binds:

| Keys | Does |
|---|---|
| `,qf` | fill login (or TOTP on a code-only page) |
| `,qt` | fill TOTP |
| `,qg` | generate a password, save it, fill it |
| `,qv` | pick any Item from the vault |
| `,qc` / `,qi` | fill a card / an address |
| `,qu` `,ql` `,qs` `,qS` | unlock, lock, sync, status |

It needs the one-time `rbw config set email` and `rbw login`
([above](#one-time-steps-after-the-first-login)). The email is set by hand
because Home Manager would put it into the store. A rebuild sets only rbw's
pinentry. rbw is a separate client from the `bw` CLI that Noctalia's
Bitwarden plugin uses, so each one has its own login.

**Ad blocking.** qutebrowser's built-in blocker runs EasyList, EasyPrivacy
and uBlock Origin's lists. A user timer refreshes them while qutebrowser is
open: when the list changes, and otherwise weekly. Run `:adblock-update` to do
it now. The blocker only blocks requests. It can't hide page elements, and it
can't run uBO's scriptlets. YouTube serves its ads from its own servers, so
`config/qutebrowser/youtube-ads.js` (greasemonkey) hides the ad slots and
fast-forwards video ads. When YouTube changes its markup, update that file's
selectors.

### Agent cards in herdr

The `agent-cards` plugin replaces herdr's sidebar with a panel at the left of
every tab. Its look follows herdr's desktop app, as
[herdr-layout-catppuccin](https://github.com/MarcozVD/herdr-layout-catppuccin)
paints it: spaces with colored letter tiles, agents grouped by state, and
Settings at the bottom. The tab pills and pane cards aren't here, because the
terminal herdr draws its own tab bar and pane dividers.

Each agent is a pixel Claude bot in its own costume, kept until the agent ends.
A bot walks while its agent works, waves when it needs you, raises its arms
when it's done, and blinks when it's idle. There are 16 costumes, and a 17th
agent shares one. The choices are in
`~/.local/state/herdr/agent-cards-costumes.json`. Other panes in an agent's tab
hang from it on a tree guide. The time beside an agent is how long it's been in
that state. A panel can only time changes it saw, so it's blank at first.

Click a row to go there. Right-click a space to rename it, open a new tab in it,
or close it, and right-click an agent or pane to rename or close it. Closing
asks first. `+` beside Spaces asks for a name and creates a space. Enter
confirms, Esc cancels.

`Ctrl+Space w` moves the keyboard into the panel: `j`/`k` step through the rows,
Enter goes to the highlighted one, `r` renames it, Esc goes back. `Ctrl+Space a`
closes or reopens the panel in the current tab. Herdr's own picker moved to
`Ctrl+Space W`, since its highlight is in the hidden sidebar, and renaming a
space moved from there to `Ctrl+Space S`.

Settings opens `config/herdr/config.toml` in Neovim and reloads it when you quit.
Herdr's `menu` is in its hidden sidebar: `Ctrl+Space b` shows it.

Colors come from the palette Noctalia writes for WezTerm, so the panel and the
bots' costumes change with the wallpaper. The bots themselves stay Claude orange
(`#D77757`) on every wallpaper. A wallpaper's palette is often one hue, so the
plugin fans out the brightest accent's hue to tell spaces apart.

On a screen 64 columns wide or less, like Terminus on a phone, the panel shrinks
to a thin rail of status marks. Tap it or press `Ctrl+Space w` to open it, and
pick a row or press Esc to shrink it again. With another client attached at the
same time, herdr sizes the layout for the one that attached or typed last, so
the rail or panel can look off on the other until you use it.

Herdr plugins can only draw in panes, which has a few consequences:

- Each tab holds its own panel pane, and zooming a pane covers it.
- A new tab docks by itself. Herdr can't add a pane at a layout's root, so a
  tab that's already split when the panel opens gets it beside the top-left
  pane only, not at full height.
- A session restore brings the panes back as shells, and the plugin's startup
  hook restarts the panels in them. A panel closes itself when its tab has no
  other panes left.

After the first rebuild, herdr only docks new tabs. Run `herdr-agent-cards dock`
in a herdr pane to dock the existing ones, and press `Ctrl+Space b` to hide the
sidebar until herdr's next launch hides it.

A panel that's already open keeps running its old code after a rebuild. New tabs
get the new code, and the rest get it the next time herdr's server starts
(`herdr server stop`, then `herdr`).

The code is `config/herdr/agent-cards/`, packaged and linked by
`modules/home/herdr.nix`.

### Session graph in herdr

`Ctrl+Space Z` on a pane running Claude Code opens
[zoetrope](https://github.com/furkankly/zoetrope) over it: a live graph of the
agent, its subagents, and their tool calls. The same key or `q` closes it. It
finds the session through herdr's Claude integration, like the session diff
below, and an agent started before that integration was installed has to be
restarted first. `nix flake update zoetrope` updates it, which also helps when a
Claude Code update changes the transcript format it reads. Its package is
`pkgs/zoetrope.nix`, and `modules/home/herdr.nix` links its plugin.

The package patches its fixed colors to the terminal's own, so the graph follows
the wallpaper like everything else. If `nix flake update zoetrope` fails on a
`substituteInPlace` line, upstream moved one of those colors.

### Reviewing a Claude session's changes

In herdr, `Ctrl+Space d` on a pane running Claude Code opens
[hunk](https://www.hunk.dev) in a split to its right, showing what that
session changed. The diff updates as the session works. `q` in hunk, or
`Ctrl+Space d` again, closes it. It finds the session through herdr's Claude
integration, so `herdr integration install claude` (a
[one-time step](#one-time-steps-after-the-first-login)) has to have run on
that machine. Without it, `Ctrl+Space d` shows a notification that says so.

Claude Code hooks in `config/claude/settings.json` run `claude-session-diff`
(`config/claude/session-diff.sh`). At the session's start they save the repo's
work tree as a baseline, and after each Edit, Write or Bash call they record
which files changed. The view shows baseline → now for those files only, so
other sessions in the same repo stay out of it, but your own edits to the same
files show up. `/clear` starts a new session, and with it a new baseline.
State is in `~/.local/state/claude-session-diff/`. Each baseline is a git tree
object, kept from `git gc` by a ref, `refs/claude-session-diff/<session>`,
which goes away with the session's state after 30 days without changes. If the
baseline is lost anyway (the repo's `.git` was re-created), the view says so
and offers to take a new one, so the diff starts from that point.

To ask the session about its changes, press `c` on a line in hunk, write a
note ("explain this", "rename this"), and save it with `Ctrl+S`. Then tell
Claude to look at the diff notes. The `diff-notes` skill
(`config/claude/skills/diff-notes/`) reads the notes you haven't had an
answer to, acts on them, replies under each note in hunk, and answers in the
chat. `R` on a note replies to it, and a reply counts as a new note. Notes
exist only while the hunk pane is open, so keep it open until Claude has
answered. Notes stick to line numbers, so they can move off their line when
the file changes under them.

### Git guardrails

A Claude Code hook checks every Bash command, in every project, for risky git
commands. A plain `git push` opens a prompt, so Claude can push once you approve.
Force-pushes, `reset --hard`, `clean -f`, `branch -D`, `checkout .`, `restore .`,
`filter-repo` and `filter-branch` are blocked: run those yourself if you mean them.

`gh` commands that git can't see also open a prompt: merging a pull request,
changing or deleting a repo, deleting an issue or release, secrets, and writes
through `gh api`. Everyday ones like `gh pr create` and `gh issue create` don't.

It looks at the commands that will run, not at text that only mentions them. A
commit message, a `gh issue create --body`, or a `cat > notes.md <<'EOF'` that
names `git reset --hard` goes through. Text that a shell runs is still checked:
`bash -c "..."`, `eval`, a heredoc fed to `bash`, `ssh host "..."`, and `$(...)`.
Shell code it can't read, like `bash -c "$cmd"` or `curl ... | sh`, opens a
prompt.

It's a guard against mistakes, not a sandbox: commands inside a script file, or
inside another language's code (`python3 -c "..."`), aren't seen. The script is
`config/claude/block-dangerous-git.sh`, and the `git-guardrails` check in
`flake.nix` tests it with sample commands (`nix log` on the check prints each
case and its result).

### Prompt cache meter

The `prompt-cache-control` mod draws a row above the Claude Code prompt: how
much of the last request the cache served, and a countdown to when the cache
lapses. `/cache` opens a pane with one row per turn; `/cache stop` closes it.
It's vendored in `config/claude/mods/prompt-cache-control/`, and Claude Code
loads it by itself from `~/.claude/skills`. Its options go in
`config/claude/settings.json`, under
`pluginConfigs."prompt-cache-control@skills-dir".options`. They're listed in
the mod's README.

### Pasted image preview

Paste an image into the Claude Code prompt with Ctrl+V and a thumbnail of it
shows above the prompt, captioned `Image #N` and its size, until you send the
prompt or delete the `[Image #N]` token. The `pasted-image-preview` mod in
`config/claude/mods/pasted-image-preview/` draws it; Claude Code loads it from
`~/.claude/skills`, like the cache meter.

Claude Code holds a pasted image in memory and only lets a mod read it once the
prompt is sent, so the mod reads the clipboard instead: when a new
`[Image #N]` lands in the prompt it runs `claude-paste-preview`
(`config/claude/paste-preview.sh`, packaged in `modules/home/claude.nix`),
which thumbnails the clipboard's image, the one Ctrl+V just attached. A copied
path to an image file works too. An image attached from a dropped or typed
file path never touches the clipboard, so its tile says there's nothing to
preview, or shows whatever image the clipboard still holds. The thumbnail size
is `pluginConfigs."pasted-image-preview@skills-dir".options.rows` (terminal
rows, default 8).

The pictures draw in herdr, which passes kitty graphics on to WezTerm (see
below). In a plain WezTerm tab you get the caption only: Claude Code places
images with kitty's Unicode placeholders, which WezTerm doesn't support.

### Terminal browser

The `terminal-browser` plugin opens a Chromium page inside Claude Code with
`/browser`. `config/claude/settings.json` declares the plugin and sets
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`, which it needs. The browser itself is
`pkgs/terminal-browser.nix`, a pinned upstream binary, so `terminal-browser
upgrade` does not apply: bump the version and hash there instead. Claude Code
only draws images on kitty and Ghostty, and herdr identifies itself as
`libghostty`, so the page stays blank until
`CLAUDE_CODE_FORCE_TERMINAL_IMAGES` skips that check. Fish sets it only in
herdr's panes (`HERDR_ENV`, `modules/home/shell.nix`): in a plain WezTerm tab
the forced images come out as boxes, with the picture drawn at the cursor. It's
tested in herdr on WezTerm, with `experimental.kitty_graphics` on in
`config/herdr/config.toml`.
`modules/home/claude.nix` links the browser's skill, so Claude can drive an open
tab, and turns off the links the browser would make itself. The package sets
`TERMINAL_BROWSER_NO_TELEMETRY`, which stops its usage events and crash reports.

### ADHD mode

`config/claude/CLAUDE.md` imports the `i-have-adhd` skill, so every session
starts with its rules and nobody has to type `/i-have-adhd`. "stop adhd mode"
turns it off for one session. To turn it off everywhere, delete the import.

### Finding a machine that dropped off the network

Work up from the bottom and stop at the first layer that fails. An SSH error only
tells you about SSH once the layers under it pass.

| Layer | Check | If it fails |
| --- | --- | --- |
| Tailnet | `tailscale status` | `offline, last seen ...` means it can't reach Tailscale at all, so look at the layers below instead of SSH |
| Power | LEDs on the machine | Off: check the outlet and power supply |
| Link | Lights on the switch port and the machine's port | Off at either end: reseat or swap the cable, try another port |
| IP | The router's DHCP client list | Not listed: no lease, or a static IP from an old setup. A USB network adapter has its own MAC, so look for that too |
| Reachability | `ping -c2 <ip>`, then `ip neigh show <ip>` | `FAILED` or `INCOMPLETE`: nothing answered at that IP |
| SSH | `ssh -v <host>` | Timed out: a firewall or wrong IP. Refused: `sshd` isn't running. Host key error: the machine or its OS changed |

If the IP changed, `ssh-keyscan -t ed25519 <ip>` shows the key a machine presents.
Compare it with `ssh-keygen -F <host>` to confirm it's the machine you want.

If power and link are fine but it never gets an IP, plug in a monitor. It may be
stuck at boot, for example on a disk that's no longer attached.

If it only drops off when the cable is in a USB network adapter, run `lsusb`
after a cold boot. Some Realtek 2.5 Gb adapters start as a driver CD-ROM
(`0bda:8151`), so no network driver loads. A re-plug often hides this, because
the adapter then comes up as a network card. A `udev` rule that runs
`usb_modeswitch` on that ID switches it at boot.

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
(weekly, keeps the last 7 days; see `modules/nixos/nix.nix`).

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
| `noctalia` | Noctalia v5; stable has 5.0.1, unstable follows the 5.x releases. Patched so Bitwarden plugin copies stay out of clipboard histories |
| `herdr` | Not packaged on stable |
| `hunk` | Not packaged on stable |
| `lan-mouse` | 0.11 adds DTLS encryption and wlroots modifier emulation; stable has 0.10 |
| `kanata` | 1.12 adds `defhands` and opposite-hand tap-hold, which the home-row mods need |
| `claude-code` | Ships several times a week; stable is months behind |

`niri` is the one package from neither branch: it is pinned to a commit on
upstream's main, because 26.04 doesn't run binds for virtual keyboards, so Lan
Mouse can't trigger them on the receiving machine. Remove the override once a
release includes the fix (commit `7da6ae4`).

## How the Arch setup maps

Packages from the old `packages/pacman.txt` map to nixpkgs packages or NixOS /
Home Manager modules of the same name (`programs.fish`,
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
| `keyd` | kanata (`modules/nixos/kanata.nix`), which adds home-row mods |
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

The repo is public and contains no plain-text secrets, passwords or tokens. Most
things that need one are done by hand after install (user password, `tailscale up`,
`gh auth login`, Claude Code login, Syncthing pairing).

The rest are encrypted in `secrets/` with [agenix](https://github.com/ryantm/agenix)
and decrypted on the machine at activation time. [SECURITY.md](SECURITY.md) covers
adding a secret, adding a machine, and losing a key. Never put a secret in a plain
Nix string: it ends up world-readable in `/nix/store`.
