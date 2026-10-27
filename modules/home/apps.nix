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
    # Codecs and Widevine are what Vivaldi downloads by itself on Arch.
    (vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = true;
    })
    signal-desktop
    slack
    vesktop

    vscode
    zed-editor

    # X11-only (forces QT_QPA_PLATFORM=xcb); runs through xwayland-satellite.
    onlyoffice-desktopeditors

    remmina
    freerdp
    anydesk
  ];
}
