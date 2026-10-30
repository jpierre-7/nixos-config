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
  home.packages = [ pkgs.noctalia ];

  # Settings every machine shares. This file is read-only on purpose: changes
  # made in Noctalia's GUI go to ~/.local/state/noctalia/settings.toml, which
  # overrides it, and that is where per-monitor settings belong.
  xdg.configFile."noctalia/noctalia-config.toml".source = toml.generate "noctalia-config.toml" {
    bar.default = {
      capsule = true;
      center = [ "group:g1" ];
      color = "secondary";
      end = [
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

    plugins.enabled = [
      "noctalia/bitwarden"
      "noctalia/bongocat"
      "noctalia/notes"
      "noctalia/wallhaven"
      "harveywuk/airpods" # needs the librepods daemon from airpods.nix
      "nightwatch75/claude-cockpit" # Claude Code sessions and usage; claude from claude.nix
    ];

    shell.font_family = "Maple Mono";

    theme = {
      builtin = "Gruvbox";
      mode = "dark";
      source = "builtin";
      wallpaper_scheme = "m3-content";
    };

    wallpaper.default.path = "${config.home.homeDirectory}/Pictures/Wallpapers/armored_girl.png";

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
  };

  # Your Wallpapers repo, pinned in flake.lock. Read-only: add wallpapers by
  # pushing to that repo and running `nix flake update wallpapers`.
  home.file."Pictures/Wallpapers".source = inputs.wallpapers;
}
