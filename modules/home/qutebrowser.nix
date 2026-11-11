# qutebrowser, a keyboard-driven second browser; Vivaldi stays the default
# (apps.nix). Ideas taken from HefKer's config (github.com/HefKer/dots), but
# nothing copied: that repo has no license. Its colors are a Noctalia template
# (noctalia.nix), Bitwarden comes through qutewarden and rbw, and ads are
# blocked by qutebrowser's own adblock plus a YouTube script.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Runs qutebrowser commands in the open instance, as `qutebrowser :cmd`
  # would, but never starts a new one. Same socket and message as Home
  # Manager's own config.py reload. Fails when qutebrowser isn't open.
  # noctalia.nix calls it from the user profile to reload the colors.
  qutebrowser-ipc = pkgs.writeShellApplication {
    name = "qutebrowser-ipc";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      socat
    ];
    text = ''
      hash=$(printf %s "$(id -un)" | md5sum | cut -d' ' -f1)
      socket="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qutebrowser/ipc-$hash"
      [ -S "$socket" ] || exit 1
      jq -cn '{args: $ARGS.positional, target_arg: null, protocol_version: 1}' --args "$@" |
        socat -lf /dev/null - UNIX-CONNECT:"$socket"
    '';
  };

  # The adblock engine reads uBlock Origin's syntax but not its `!#include`
  # lines, so the files that filters.txt and privacy.txt include are listed
  # one by one. uBO starts a new filters-<year>.txt each year: add it here.
  # filters-mobile.txt is left out on purpose.
  ubo = name: "https://github.com/uBlockOrigin/uAssets/raw/master/filters/${name}.txt";
  adblockLists = [
    "https://easylist.to/easylist/easylist.txt"
    "https://easylist.to/easylist/easyprivacy.txt"
  ]
  ++ map ubo [
    "filters"
    "filters-general"
    "filters-2020"
    "filters-2021"
    "filters-2022"
    "filters-2023"
    "filters-2024"
    "filters-2025"
    "filters-2026"
    "ubo-link-shorteners"
    "privacy"
    "resource-abuse"
    "badware"
    "quick-fixes"
    "unbreak"
    "annoyances-cookies"
  ];
  listsHash = builtins.hashString "sha256" (builtins.toJSON adblockLists);

  # qutebrowser only fetches its lists on `:adblock-update`. The timer below
  # runs this every hour; it updates when the lists above changed or the
  # last update is a week old, and only while qutebrowser is open, because
  # the update runs inside it.
  adblock-update = pkgs.writeShellApplication {
    name = "qutebrowser-adblock-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      qutebrowser-ipc
    ];
    text = ''
      stamp="''${XDG_STATE_HOME:-$HOME/.local/state}/qutebrowser/adblock-lists"
      if [ "$(cat "$stamp" 2>/dev/null)" = ${listsHash} ] && [ -z "$(find "$stamp" -mtime +6)" ]; then
        exit 0
      fi
      qutebrowser-ipc :adblock-update || exit 0 # not open: try again next hour
      mkdir -p "$(dirname "$stamp")"
      echo ${listsHash} >"$stamp"
    '';
  };

  # qutewarden's picker is Vicinae, which already is the launcher, rather than
  # its default, fuzzel. qutewarden passes its prompt ("Fill which Item?",
  # "Replace the password?") only to pickers it knows by name, so this adapter
  # is called `dmenu`: it gets `-p <prompt>` and shows it as Vicinae's title
  # and placeholder. Vicinae returns typed text when nothing matches, which
  # `generate` needs to ask for a username.
  vicinae-picker = pkgs.writeShellScriptBin "dmenu" ''
    prompt=
    if [ "''${1-}" = -p ]; then
      prompt=$2
      shift 2
    fi
    exec ${lib.getExe config.programs.vicinae.package} dmenu --no-quick-look \
      -n "$prompt" -p "$prompt" "$@"
  '';

  rbw = lib.getExe config.programs.rbw.package;
  # Userscripts have no terminal, so rbw needs a graphical pinentry.
  pinentry = "${pkgs.pinentry-qt}/bin/pinentry-qt";
in
{
  imports = [ inputs.qutewarden.homeManagerModules.default ];

  programs.qutebrowser = {
    enable = true;
    # Keeps what qutebrowser saves at runtime: site permissions (notifications,
    # camera) and `:set -u` per-site overrides. It loads first, so a global
    # value set here still wins after a restart.
    loadAutoconfig = true;

    settings = {
      fonts.default_family = "Maple Mono"; # as in Noctalia and WezTerm
      fonts.default_size = "12pt";
      # Noctalia runs in dark mode (theme.mode in noctalia.nix); sites that
      # have a dark theme use it.
      colors.webpage.preferred_color_scheme = "dark";

      content.autoplay = false;
      # "both": the hosts lists (default: Peter Lowe's) and the adblock engine.
      content.blocking = {
        enabled = true;
        method = "both";
        adblock.lists = adblockLists;
      };

      downloads.location.directory = "~/Downloads";
      confirm_quit = [ "downloads" ];
      input.insert_mode.auto_load = true;
      # Ctrl+E in a text field edits it in Neovim, as everywhere else here.
      editor.command = [
        "wezterm"
        "start"
        "--always-new-process"
        "--"
        "nvim"
        "+call cursor({line}, {column})"
        "{file}"
      ];
    };

    # The blocker stays off on YouTube pages: with it on, videos stop after
    # about 40 seconds with "Something went wrong. Refresh or try again
    # later." The YouTube script below still mutes and skips the ads there.
    perDomainSettings."*://*.youtube.com/*".content.blocking.enabled = false;

    searchEngines = {
      DEFAULT = "https://duckduckgo.com/?q={}";
      g = "https://www.google.com/search?q={}";
      gh = "https://github.com/search?q={}&type=repositories";
      yt = "https://www.youtube.com/results?search_query={}";
      w = "https://en.wikipedia.org/w/index.php?search={}";
      # Same channel and release as flake.nix.
      nix = "https://search.nixos.org/packages?channel=26.05&query={}";
      nixopt = "https://search.nixos.org/options?channel=26.05&query={}";
      hm = "https://home-manager-options.extranix.com/?query={}&release=release-26.05";
      nw = "https://wiki.nixos.org/w/index.php?search={}";
      aw = "https://wiki.archlinux.org/?search={}"; # still the best Linux wiki
    };

    # Noctalia's colors (theme.templates.user.qutebrowser in noctalia.nix). The
    # file is missing until Noctalia first renders it.
    extraConfig = ''
      if (config.configdir / "noctalia" / "colors.py").exists():
          config.source("noctalia/colors.py")
    '';
  };

  xdg.configFile."qutebrowser/greasemonkey/youtube-ads.js".source =
    ../../config/qutebrowser/youtube-ads.js;

  home.packages = [ qutebrowser-ipc ];

  systemd.user.services.qutebrowser-adblock-update = {
    Unit.Description = "Update qutebrowser's adblock lists when they are due";
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe adblock-update;
    };
  };
  systemd.user.timers.qutebrowser-adblock-update = {
    Unit.Description = "Check hourly whether qutebrowser's adblock lists are due";
    Timer = {
      OnStartupSec = "5min";
      OnUnitActiveSec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Bitwarden: qutewarden reads the vault through rbw. The `,q` prefix keeps
  # its binds together. The module links it into
  # qutebrowser's userscripts directory, as `spawn --userscript` doesn't
  # search PATH.
  programs.qutewarden = {
    enable = true;
    settings.picker = "${vicinae-picker}/bin/dmenu";
    keyBindings = {
      ",qf" = "fill";
      ",qt" = "totp";
      ",qg" = "generate";
      ",qv" = "vault";
      ",qc" = "card";
      ",qi" = "identity";
      ",qu" = "unlock";
      ",ql" = "lock";
      ",qs" = "sync";
      ",qS" = "status";
    };
  };

  # Package only: Home Manager would write rbw's config.json, with the
  # Bitwarden email, into the world-readable store and this public repo. The
  # email is set by hand (README); this sets only the pinentry, and restarts
  # the agent, which keeps using the old one until then.
  programs.rbw.enable = true;
  home.activation.rbwPinentry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(${rbw} config show 2>/dev/null | ${lib.getExe pkgs.jq} -r .pinentry)" != ${pinentry} ]; then
      run ${rbw} config set pinentry ${pinentry}
      run ${rbw} stop-agent 2>/dev/null || true
    fi
  '';
}
