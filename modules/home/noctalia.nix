{
  config,
  inputs,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };
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
      ];
      color = "secondary";
      end = [
        "sysmon"
        "claude-cockpit"
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
      start = [
        "launcher"
        "wallpaper"
        "workspaces"
        "group:g2"
        "airpods"
        "bitwarden"
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
      "nightwatch75/claude-cockpit" # Claude Code sessions and usage; claude from claude.nix
    ];

    shell.font_family = "Maple Mono";
    # Empty means ~/Pictures. Screen Toolkit's annotate/OCR tools look for the
    # capture in ~/Pictures/Screenshots unless the directory is set in
    # settings.toml (it doesn't read this file), so use that folder, which is
    # also where niri saves its screenshots (config/niri/config.kdl).
    shell.screenshot.directory = "${config.home.homeDirectory}/Pictures/Screenshots";

    theme = {
      builtin = "Gruvbox";
      mode = "dark";
      source = "builtin";
      wallpaper_scheme = "m3-content";
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
    widget.claude-cockpit.type = "nightwatch75/claude-cockpit:widget";
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
