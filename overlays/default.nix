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
  inherit (unstable)
    noctalia # Noctalia v5: stable has 5.0.1, unstable follows the 5.x releases
    herdr # not packaged on stable
    claude-code # ships several times a week; stable lags months behind
    ;
}
