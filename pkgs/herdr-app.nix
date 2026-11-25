# Herdr, the desktop app for herdr-core (terminals and agents that outlive the
# window). Not in nixpkgs. Upstream ships prebuilt GPUI tarballs, and its
# installer writes to ~/.local/share and assumes FHS libraries, so a new
# version means bumping version and hash here. Both are in
# https://releases.herdr.dev/app/latest.json. The core it drives is
# nixpkgs' herdr-core (unstable, overlays/default.nix).
{
  autoPatchelfHook,
  copyDesktopItems,
  fetchurl,
  herdr-core,
  lib,
  libGL,
  libxcb,
  libxkbcommon,
  makeDesktopItem,
  makeWrapper,
  stdenv,
  vulkan-loader,
  wayland,
}:
stdenv.mkDerivation rec {
  pname = "herdr-app";
  version = "0.1.18";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${version}/herdr-app-linux-x86_64.tar.gz";
    sha256 = "8a11edd79dd40b349f7286cf51910b62e21136daf8f03005a9fd2c4dc5830f83";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
  ];

  buildInputs = [
    libxcb
    libxkbcommon
    (lib.getLib stdenv.cc.cc)
  ];

  # GPUI dlopens these, so autoPatchelf can't see them in its ELF headers.
  runtimeDependencies = [
    libGL
    vulkan-loader
    wayland
  ];

  dontBuild = true;

  # The icon goes to share/icons, not next to the binary: the app's
  # self-updater only runs from a folder holding both (src/update.rs
  # find_root), and it can't replace a store path anyway.
  # Its usage telemetry is on by default; HERDR_TELEMETRY=0 turns it off.
  # herdr-core goes on its PATH, so a launcher start (no shell PATH) still finds
  # it instead of offering to curl the upstream core into ~/.local/bin.
  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-app $out/libexec/herdr-app
    install -Dm644 herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
    makeWrapper $out/libexec/herdr-app $out/bin/herdr-app \
      --set HERDR_TELEMETRY 0 \
      --prefix PATH : ${lib.makeBinPath [ herdr-core ]}
    runHook postInstall
  '';

  # Same entry the upstream installer writes.
  desktopItems = [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      categories = [ "Development" ];
      startupWMClass = "herdr-app";
    })
  ];

  meta = {
    description = "Desktop app for herdr-core: terminals and coding agents that keep running";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    mainProgram = "herdr-app";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
