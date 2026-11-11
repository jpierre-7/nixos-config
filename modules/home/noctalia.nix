{
  config,
  inputs,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };

  # Idle timeout for every host, in seconds: nothing happens before it. The
  # idle timers below are derived from it.
  idleTimeout = 10 * 60;
  # How long the screensaver plays before the lock timer fires. The lock can't
  # share idleTimeout: Noctalia would fire both together and lock right after
  # starting the screensaver (src/idle/idle_manager.cpp), so it would never be
  # seen. Input during the screensaver locks anyway.
  screensaverRun = 5 * 60;
in
{
  # From nixpkgs-unstable (overlays/default.nix). Niri starts it (spawn-at-startup).
  # The rest are tools the enabled plugins call from PATH (each plugin.toml's
  # `dependencies`). gpu-screen-recorder is installed system-wide with its
  # capability wrapper (modules/nixos/desktop.nix).
  home.packages = with pkgs; [
    noctalia

    # noctalia/bitwarden: the `bw` CLI; wtype for its Autotype button.
    bitwarden-cli
    wtype

    # alexander/screen-toolkit. Its fullscreen recordings use gpu-screen-recorder.
    slurp # region selection
    hyprpicker # color picker
    (tesseract.override { enableLanguages = [ "eng" ]; }) # OCR; the default ships every language
    imagemagick
    zbar # QR codes
    translate-shell # OCR translation
    ffmpeg # GIF conversion, thumbnails (ffprobe too)
    wl-screenrec # region recording and microphone audio
    wf-recorder # fallback recorder
    bc
    pulseaudio # pactl only; the sound server is PipeWire (modules/nixos/audio.nix)
    mpv # recording preview
  ];

  # Settings every machine shares. This file is read-only on purpose: changes
  # made in Noctalia's GUI go to ~/.local/state/noctalia/settings.toml, which
  # overrides it, and that is where per-monitor settings belong.
  xdg.configFile."noctalia/noctalia-config.toml".source = toml.generate "noctalia-config.toml" {
    bar.default = {
      capsule = true;
      center = [
        "notes"
        "wallhaven"
        "group:g1"
        "screen-toolkit"
        "bitwarden"
      ];
      color = "secondary";
      end = [
        "sysmon"
        "notifications"
        "clipboard"
        "network"
        "bluetooth"
        "brightness"
        "battery"
        "control-center"
        "session"
      ];
      font_family = "Maple Mono";
      icon_color = "primary";
      margin_ends = 0; # full width; the default leaves a 100 px gap at each end
      start = [
        "launcher"
        "wallpaper"
        "workspaces"
        "group:g2"
        "airpods"
      ];
      widget_spacing = 10;

      capsule_group = [
        {
          accordion = false;
          accordion_direction = "end";
          enabled = true;
          fill = "surface_variant";
          id = "g1";
          members = [
            "date"
            "clock"
          ];
          opacity = 1.0;
          padding = 6.0;
        }
        {
          accordion = false;
          accordion_direction = "end";
          enabled = true;
          fill = "surface_variant";
          id = "g2";
          members = [
            "media"
            "volume"
          ];
          opacity = 1.0;
          padding = 6.0;
        }
      ];
    };

    calendar.enabled = true;

    # The only idle daemon. After idleTimeout the screensaver plays
    # (modules/home/screensaver.nix); the next input locks, then ends it. Its
    # windows don't count as activity, so after screensaverRun more the session
    # locks (which also ends it) and the monitors go off. Input from Lan Mouse
    # counts as activity: niri treats virtual input like local input.
    idle = {
      behavior_order = [
        "screensaver"
        "lock"
        "screen-off"
      ];
      behavior.screensaver = {
        timeout = idleTimeout;
        action = "command";
        command = "nixos-screensaver start";
        resume_command = "nixos-screensaver stop";
      };
      behavior.lock = {
        timeout = idleTimeout + screensaverRun;
        action = "lock";
      };
      behavior.screen-off = {
        timeout = idleTimeout + screensaverRun + 5; # just after the lock
        locked_timeout = 60; # at the lock screen, e.g. after waking it by accident
        action = "screen_off";
      };
    };

    lockscreen_widgets = {
      enabled = false;
      schema_version = 2;
      grid = {
        cell_size = 16;
        major_interval = 4;
        visible = true;
      };
    };

    notification.history_retention_hours = 24;

    # What each plugin needs on PATH is in home.packages above.
    plugins.enabled = [
      "noctalia/bitwarden"
      "noctalia/notes"
      "noctalia/wallhaven"
      "alexander/screen-toolkit"
      "harveywuk/airpods" # needs the librepods daemon from airpods.nix
    ];

    shell.font_family = "Maple Mono";
    # Empty means ~/Pictures. Screen Toolkit's annotate/OCR tools look for the
    # capture in ~/Pictures/Screenshots unless the directory is set in
    # settings.toml (it doesn't read this file), so use that folder, which is
    # also where niri saves its screenshots (config/niri/config.kdl).
    shell.screenshot.directory = "${config.home.homeDirectory}/Pictures/Screenshots";

    theme = {
      mode = "dark";
      source = "wallpaper";
      wallpaper_scheme = "faithful";

      # Noctalia re-renders these whenever its palette changes (wallpaper,
      # scheme, light/dark). They replace its built-in and community
      # templates for the same apps, whose hooks edit the apps' configs in
      # place: that fails on read-only store files and would rewrite the live
      # ones in this repo on every wallpaper change. These write only their
      # output; the apps reread it or get a reload hook. herdr needs no
      # template: its "terminal" theme draws with WezTerm's colors.
      templates.user = {
        # Included at the end of config/niri/config.kdl. Niri reloads on change.
        # Only the template: its built-in apply.sh appends the include to
        # config.kdl, which is a read-only store file here.
        niri = {
          input_path = "${pkgs.noctalia}/share/noctalia/assets/templates/niri/niri.kdl";
          output_path = "$XDG_CONFIG_HOME/niri/noctalia.kdl";
        };
        # The whole prompt config is the template, so ~/.config/starship.toml
        # is Noctalia's output, not a Home Manager link (shell.nix).
        starship = {
          input_path = "${../../config/starship.toml}";
          output_path = "$XDG_CONFIG_HOME/starship.toml";
        };
        # Reloaded through wezterm.lua's config reload watch.
        wezterm = {
          input_path = "${pkgs.noctalia}/share/noctalia/assets/templates/wezterm/wezterm.toml";
          output_path = "$XDG_CONFIG_HOME/wezterm/colors/Noctalia.toml";
        };
        # A full colorscheme, selected in config/nvim/lua/plugins/colorscheme.lua.
        # It lands in the live nvim config, where it is gitignored. Running
        # Neovims reload it on SIGUSR1.
        neovim = {
          input_path = "${inputs.noctalia-templates}/lazyvim/noctalia.lua";
          output_path = "$XDG_CONFIG_HOME/nvim/colors/noctalia.lua";
          post_hook = "${pkgs.procps}/bin/pkill -USR1 -x nvim || true";
        };
        # Selected in config/vicinae/settings.json. Re-selecting it is how the
        # community template's hook makes the running server pick up the new
        # file; with the name already set, settings.json stays unchanged.
        vicinae = {
          input_path = "${inputs.noctalia-templates}/vicinae/vicinae.toml";
          output_path = "$XDG_DATA_HOME/vicinae/themes/noctalia.toml";
          post_hook = "${config.programs.vicinae.package}/bin/vicinae theme set noctalia";
        };
        # Claude Code's UI theme, selected as "custom:noctalia" in
        # config/claude/settings.json. Claude Code reloads it on change.
        claude-code = {
          input_path = "${inputs.noctalia-templates}/claude-code/claude-code.json";
          output_path = "${config.home.homeDirectory}/.claude/themes/noctalia.json";
        };
        # Sourced by modules/home/qutebrowser.nix's config.py. The hook reloads
        # an open qutebrowser; the community template's own hook would start
        # one when none is open (its `pgrep -f qutebrowser` matches the hook's
        # own path).
        qutebrowser = {
          input_path = "${inputs.noctalia-templates}/qutebrowser/template.py";
          output_path = "$XDG_CONFIG_HOME/qutebrowser/noctalia/colors.py";
          post_hook = "${config.home.profileDirectory}/bin/qutebrowser-ipc :config-source || true";
        };
        # Sourced by the Claude Code status line (config/claude/statusline.sh).
        claude-statusline = {
          input_path = "${../../config/claude/statusline-colors.sh}";
          output_path = "$XDG_CACHE_HOME/noctalia/claude-statusline-colors.sh";
        };
        # Sourced by the screensaver (config/screensaver/screensaver.sh).
        screensaver = {
          input_path = "${../../config/screensaver/colors.sh}";
          output_path = "$XDG_CACHE_HOME/noctalia/screensaver-colors.sh";
        };
        # Read by the login screen (modules/nixos/greeter.nix), outside the
        # home directory so the greeter user can read it.
        greeter = {
          input_path = "${../../config/greeter/palette.json}";
          output_path = "/var/lib/greeter-palette/palette.json";
        };
      };
    };

    wallpaper.default.path = "${config.home.homeDirectory}/Pictures/Wallpapers/armored_girl.png";

    # noctalia/bitwarden has no bar widget of its own (it adds the /bw launcher
    # search and some panels), so this button opens the launcher on /bw.
    widget.bitwarden = {
      type = "custom_button";
      glyph = "shield-lock";
      tooltip = "Bitwarden";
      actions.left = "panel-toggle launcher /bw";
    };
    widget.airpods = {
      type = "harveywuk/airpods:airpods";
      hide_when_disconnected = false;
    };
    widget.clock.format = "{:%I:%M %p}";
    widget.media = {
      max_length = 100;
      title_scroll = "always";
    };
    widget.notes.type = "noctalia/notes:notes";
    widget.screen-toolkit.type = "alexander/screen-toolkit:widget";
    widget.wallhaven.type = "noctalia/wallhaven:wallhaven";
  };

  # Your Wallpapers repo, pinned in flake.lock. Read-only: add wallpapers by
  # pushing to that repo and running `nix flake update wallpapers`.
  home.file."Pictures/Wallpapers".source = inputs.wallpapers;
}
