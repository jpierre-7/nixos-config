# Vencord with userplugins compiled in, for Vesktop's `withSystemVencord`.
# Userplugins can't be loaded at runtime: Vencord has to be built with them in
# src/userplugins/. Based on HefKer/nixos-config's pkgs/vencord-userplugins.
# `plugins` maps a folder name to its source (a `flake = false` input).
{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  vencord,
  plugins,
}:
vencord.overrideAttrs (
  finalAttrs: old: {
    pname = "vencord-with-userplugins";
    # nixpkgs' release lags Vencord's, and an outdated one's patches can
    # break Discord's newest client to a blank window.
    version = "1.15.16";
    src = fetchFromGitHub {
      owner = "Vendicated";
      repo = "Vencord";
      tag = "v${finalAttrs.version}";
      hash = "sha256-aUJubLJpyLAZWiOezqFxPY6oVPgWVPQpajFqrJvrO9U=";
    };
    # nixpkgs' lockfile patch and @types/react fix are for its older release;
    # newer ones pin @types/react through a pnpm catalog instead.
    patches = [ ];
    # A plugin's own tsconfig points at its dev checkout; inside the tree
    # Vencord's root one applies.
    postPatch = lib.concatStrings (
      lib.mapAttrsToList (name: src: ''
        mkdir -p src/userplugins
        cp -r ${src} src/userplugins/${name}
        chmod -R u+w src/userplugins/${name}
        rm -f src/userplugins/${name}/tsconfig.json
      '') plugins
    );
    # Built without postPatch: the plugins add no dependencies.
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        patches
        ;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-HS8uZNepvDefjrsG3buVLFCVv7sHvazcwdpcT3EQ/78=";
    };
  }
)
