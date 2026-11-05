# Packages taken from nixpkgs-unstable because they are missing or too old on
# the stable branch. Everything else comes from stable. Keep this list short
# and keep the README's "Unstable exceptions" table in sync with it.
{ inputs }:
final: prev:
let
  unstable = import inputs.nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    config.allowUnfree = true; # claude-code is unfree
  };
in
{
  # Noctalia v5: stable has 5.0.1, unstable follows the 5.x releases. Plugins can
  # only copy plain text, so Vicinae's and Noctalia's clipboard histories would
  # both keep Bitwarden passwords. The patch marks that plugin's copies with the
  # password hint they both skip.
  noctalia = unstable.noctalia.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./noctalia-bitwarden-password-hint.patch ];
  });

  inherit (unstable)
    herdr # not packaged on stable
    hunk # not packaged on stable
    kanata # 1.12 adds defhands and tap-hold-opposite-hand, which the home-row mods use
    claude-code # ships several times a week; stable lags months behind
    ;
}
