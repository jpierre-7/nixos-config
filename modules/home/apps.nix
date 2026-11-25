{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Vesktop (Discord client) with GPU acceleration off: the known fix carried
  # over from Arch. Its desktop entry runs `vesktop` from PATH, so launching
  # from Vicinae/Noctalia also goes through this wrapper.
  # Its Vencord is built in the store with the QuickActions userplugin
  # (HefKer/vc-actions) compiled in, instead of the copy Vesktop downloads.
  vesktopWithPlugins = pkgs.vesktop.override {
    withSystemVencord = true;
    vencord = pkgs.callPackage ../../pkgs/vencord-userplugins.nix {
      plugins.vcActions = inputs.vc-actions;
    };
  };
  vesktop = pkgs.symlinkJoin {
    name = "vesktop-${vesktopWithPlugins.version}";
    paths = [ vesktopWithPlugins ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/vesktop --add-flags "--disable-gpu"
    '';
  };
in
{
  home.packages = with pkgs; [
    # Widevine as on Arch. No proprietaryCodecs: nixpkgs' chromium-codecs-ffmpeg-extra
    # lags Vivaldi and it fails to start (undefined av_* symbol). Without it, Vivaldi
    # downloads matching codecs into ~/.local/lib/vivaldi on first run, as on Arch.
    (vivaldi.override { enableWidevine = true; })
    signal-desktop
    slack
    teams-for-linux # unofficial client; Microsoft has no native Linux app
    libfido2 # Teams runs its fido2-* tools from PATH (see config.json below)
    vesktop

    # File manager; niri floats it (config.kdl). Trash and mounts need gvfs (desktop.nix).
    nautilus

    vscode
    zed-editor

    # X11-only (forces QT_QPA_PLATFORM=xcb); runs through xwayland-satellite.
    onlyoffice-desktopeditors

    # osu!lazer. The official AppImage, not the source build (osu-lazer): osu!'s
    # servers only take scores from official builds. Lazer can't update itself
    # in the store, so new versions come with nixpkgs updates.
    osu-lazer-bin

    remmina
    freerdp
    anydesk
  ];

  programs.calibre.enable = true;

  # Backup browser; qutebrowser is the default (qutebrowser.nix).
  programs.google-chrome.enable = true;

  # qutebrowser opens links. mimeapps.list stays writable (Claude Code,
  # Vesktop and Slack register their URL handlers in it), so this sets only
  # the browser entries instead of owning the file through xdg.mimeApps.
  home.activation.defaultBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.xdg-utils}/bin/xdg-mime default org.qutebrowser.qutebrowser.desktop \
      text/html x-scheme-handler/http x-scheme-handler/https \
      x-scheme-handler/about x-scheme-handler/unknown
  '';

  # The magnifying lamp's camera in "PC Camera" mode is a plain UVC webcam
  # (GENERAL - UVC, 1b3f:2002) that only offers MJPG 1280x720 at 30 fps. The
  # by-id path stays the same when /dev/videoN renumbers (the Brio is video0).
  # Low-latency flags so the picture keeps up with the soldering iron.
  xdg.desktopEntries.magnifier-camera = {
    name = "Magnifier camera";
    comment = "Live view from the magnifying lamp's USB camera";
    icon = "camera-web";
    exec = lib.concatStringsSep " " [
      (lib.getExe pkgs.mpv)
      ''"--title=Magnifier camera"''
      "--profile=low-latency"
      "--untimed"
      "--demuxer-lavf-format=video4linux2"
      "--demuxer-lavf-o=input_format=mjpeg,video_size=1280x720"
      "av://v4l2:/dev/v4l/by-id/usb-GENERAL_GENERAL_-_UVC-video-index0"
    ];
    categories = [ "AudioVideo" ];
    settings.Keywords = "webcam;microscope;magnifier;lamp;";
  };

  # Account switcher (experimental, off by default). The app only reads this file;
  # its profiles and logins stay in its own state under ~/.config/teams-for-linux.
  # The security key beta is on for accounts that default to a passkey: Electron
  # can't open the key prompt on Linux, so sign-in hangs. With the beta, finding
  # no key fails the prompt and Microsoft offers "Sign in another way".
  xdg.configFile."teams-for-linux/config.json".text = builtins.toJSON {
    multiAccount.enabled = true;
    auth.webauthn.enabled = true;
  };
}
