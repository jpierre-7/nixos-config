# Chromium browser that draws in the terminal, used by the terminal-browser
# Claude Code plugin (config/claude/settings.json). Not in nixpkgs. Upstream
# only ships prebuilt Electron tarballs, and its installer and `upgrade` write
# to ~/.local/share and assume FHS libraries, so a new version means bumping
# version and hash here. Both are in the script at https://terminal-browser.sh/install.
{
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  autoPatchelfHook,
  cairo,
  cups,
  dbus,
  expat,
  fetchurl,
  glib,
  gtk3,
  lib,
  libGL,
  libgbm,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  makeWrapper,
  nspr,
  nss,
  pango,
  stdenv,
  systemd,
  vulkan-loader,
}:
stdenv.mkDerivation rec {
  pname = "terminal-browser";
  version = "0.15.3";

  src = fetchurl {
    url = "https://terminal-browser.sh/install/dl/stable/v${version}/terminal-browser-linux-x64.tar.gz";
    sha256 = "244e995b554edb29f66cf07f7f830a76885ae6a6fa233dec53980bfb0a509541";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    (lib.getLib stdenv.cc.cc)
    systemd
  ];

  # Chromium dlopens these, so autoPatchelf can't see them in its ELF headers.
  runtimeDependencies = [
    libGL
    vulkan-loader
  ];

  dontBuild = true;
  # Stripping corrupts Electron's binary.
  dontStrip = true;

  # The opt-out covers usage events and crash reports alike. It's set here so
  # every launch gets it: the shell, the Claude plugin, and anything else.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/terminal-browser $out/bin
    cp -r . $out/lib/terminal-browser
    makeWrapper $out/lib/terminal-browser/bin/terminal-browser $out/bin/terminal-browser \
      --set TERMINAL_BROWSER_NO_TELEMETRY 1
    runHook postInstall
  '';

  meta = {
    description = "Chromium browser that runs in a terminal over the kitty graphics protocol";
    homepage = "https://github.com/zenbu-labs/terminal-browser";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
