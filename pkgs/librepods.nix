# The patched librepods fork the Noctalia AirPods plugin needs (upstream lacks
# its status file and control verbs). Source pinned by the `librepods` flake input.
{
  lib,
  stdenv,
  src,
  cmake,
  ninja,
  pkg-config,
  qt6,
  openssl,
  libpulseaudio,
}:
stdenv.mkDerivation {
  pname = "librepods";
  version = "0-unstable-${src.lastModifiedDate or "unknown"}";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.qttools # LinguistTools
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative # Quick, QuickControls2
    qt6.qtconnectivity # Bluetooth
    qt6.qtwayland
    openssl
    libpulseaudio
  ];

  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];

  # The unit expects a ~/.local install; point it at the store instead.
  postPatch = ''
    substituteInPlace librepods.service \
      --replace-fail '%h/.local/bin/librepods' "$out/bin/librepods"
  '';

  meta = {
    description = "AirPods daemon (patched fork for the Noctalia AirPods plugin)";
    homepage = "https://github.com/harveywuk/librepods";
    license = lib.licenses.gpl3Only;
    mainProgram = "librepods";
    platforms = lib.platforms.linux;
  };
}
