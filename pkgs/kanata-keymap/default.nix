# The kanata keymap viewer (modules/home/kanata-keymap.nix). Adapted from
# HefKer/nixos-config's pkgs/kanata-keymap.
{
  fetchurl,
  keymap-drawer,
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
  systemd,
}:
let
  # keymap-drawer otherwise downloads this at draw time.
  layout = fetchurl {
    url = "https://raw.githubusercontent.com/qmk/qmk_firmware/4791cfae1af0bc15a0bd8417c5195bf482b87605/layouts/default/60_ansi/info.json";
    hash = "sha256-/nkxw7F2i69HlZqWA0M3v6ICWCVKenBr/QW4mQL2FWw=";
  };
  python = python3.withPackages (ps: [ ps.pyyaml ]);
in
# qutebrowser comes from PATH: the one programs.qutebrowser installs.
stdenvNoCC.mkDerivation {
  pname = "kanata-keymap";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    install -Dm644 -t $out/share/kanata-keymap keymap_data.py viewer.py page.html
    makeWrapper ${lib.getExe python} $out/bin/kanata-keymap-render \
      --add-flags $out/share/kanata-keymap/keymap_data.py \
      --set KEYMAP_DRAWER ${lib.getExe' keymap-drawer "keymap"} \
      --set KEYMAP_LAYOUT ${layout}
    makeWrapper ${lib.getExe python} $out/bin/kanata-keymap \
      --add-flags $out/share/kanata-keymap/viewer.py \
      --set KEYMAP_PAGE $out/share/kanata-keymap/page.html \
      --prefix PATH : ${lib.makeBinPath [ systemd ]}
  '';
  meta.mainProgram = "kanata-keymap";
}
