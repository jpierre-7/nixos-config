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

  # 26.04 sends virtual keyboard input straight to clients, so Lan Mouse can't
  # trigger binds on the receiving machine (niri-wm/niri#403). Unstable has 26.04
  # too, so this is a commit from main. Drop this once a release includes 7da6ae4.
  niri =
    let
      src = final.fetchFromGitHub {
        owner = "niri-wm";
        repo = "niri";
        rev = "a8562a1126922ed4c1c94d34c1dbb26633491d05";
        hash = "sha256-AtuZOzsb9p+TTzkgaPjvl+5YRsgKc+RlIQMyozOmY5A=";
      };
    in
    prev.niri.overrideAttrs {
      version = "26.04-a8562a1";
      inherit src;
      cargoDeps = final.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-4VQqTrVB6p8M3U7xqF+K6vSKrQcqhW+OnZyAp6j/fGA=";
      };
      doCheck = false;
      doInstallCheck = false;
    };

  inherit (unstable)
    herdr # not packaged on stable
    hunk # not packaged on stable
    lan-mouse # 0.11 adds the DTLS encryption and wlroots modifier emulation; stable has 0.10
    kanata # 1.12 adds defhands and tap-hold-opposite-hand, which the home-row mods use
    claude-code # ships several times a week; stable lags months behind
    ;
}
