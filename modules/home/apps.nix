{ pkgs, ... }:
let
  # Vesktop (Discord client) with GPU acceleration off: the known fix carried
  # over from Arch. Its desktop entry runs `vesktop` from PATH, so launching
  # from Vicinae/Noctalia also goes through this wrapper.
  vesktop = pkgs.symlinkJoin {
    name = "vesktop-${pkgs.vesktop.version}";
    paths = [ pkgs.vesktop ];
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
    vesktop

    # File manager; niri floats it (config.kdl). Trash and mounts need gvfs (desktop.nix).
    nautilus

    vscode
    zed-editor

    # X11-only (forces QT_QPA_PLATFORM=xcb); runs through xwayland-satellite.
    onlyoffice-desktopeditors

    remmina
    freerdp
    anydesk
  ];
}
