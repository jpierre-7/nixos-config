# Clipboard sync for Lan Mouse, which has none of its own
# (feschber/lan-mouse#105). Source pinned by the `lan-clip` flake input.
{
  lib,
  rustPlatform,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "lan-clip";
  version = "0.1.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = {
    description = "Clipboard sync between machines paired with Lan Mouse";
    homepage = "https://github.com/johanjongsma/lan-clip";
    license = lib.licenses.gpl3Plus;
    mainProgram = "lan-clip";
    platforms = lib.platforms.linux;
  };
}
