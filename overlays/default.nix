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

  # StreamController freezes when a key's sidebar loads a label whose font weight
  # isn't a named Pango.Weight (e.g. 250): PyGObject 3.56 rejects it, and the
  # TypeError leaves LabelEditor's lock held, so the next sidebar update hangs
  # the main thread. Snap to the nearest named weight. Upstream main still has
  # the bare set_weight; drop this once it's fixed there.
  streamcontroller = prev.streamcontroller.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/backend/DeckManagement/HelperMethods.py \
        --replace-fail 'desc.set_weight(font_weight)' \
          'desc.set_weight(min(Pango.Weight, key=lambda w: abs(int(w) - int(font_weight))))'
    '';
  });

  # Ships several times a week; stable lags months behind. Its wrapper puts
  # alsa-lib (voice mode) on LD_LIBRARY_PATH, and every command Claude runs
  # inherits it. Unstable's alsa-lib needs a newer glibc than stable's tools, so
  # amixer and the like failed to start from a Claude shell, and Electron apps
  # died at launch. Stable's alsa-lib loads in both.
  claude-code = unstable.claude-code.override { inherit (prev) alsa-lib; };

  inherit (unstable)
    herdr # not packaged on stable
    herdr-core # not packaged on stable; the core the Herdr desktop app drives
    hunk # not packaged on stable
    lan-mouse # 0.11 adds the DTLS encryption and wlroots modifier emulation; stable has 0.10
    kanata # 1.12 adds defhands and tap-hold-opposite-hand, which the home-row mods use
    antigravity-cli # not packaged on stable
    tailscale # the admin console flags stable's 1.98 as out of date; clients should track releases
    ;
}
