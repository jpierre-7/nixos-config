# Idle screensaver in the style of Omarchy's: the NixOS logo animated by
# terminaltexteffects in fullscreen WezTerms, one per monitor, until the next
# input locks the session. Noctalia's idle service starts and stops it
# (`idle.behavior` in noctalia.nix); its colors are a Noctalia template there
# too. Niri opens the windows fullscreen (config/niri/config.kdl).
{ config, pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "nixos-screensaver";
      runtimeInputs = with pkgs; [
        config.programs.wezterm.package
        coreutils
        jq
        niri
        noctalia
        terminaltexteffects
        util-linux # setsid
      ];
      runtimeEnv.SCREENSAVER_LOGO = ../../config/screensaver/nixos-logo.txt;
      text = builtins.readFile ../../config/screensaver/screensaver.sh;
    })
  ];
}
