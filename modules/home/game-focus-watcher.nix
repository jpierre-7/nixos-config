# Game focus watcher: while a game has focus, every kanata instance switches
# to that game's layer in config/kanata/keymap.kbd (passthrough for osu!, game
# for Steam games), and back to the previous base layer after. It follows
# niri's event stream and talks to kanata over the TCP ports set in
# modules/nixos/kanata.nix and hosts/laptop. Script: pkgs/game-focus-watcher/.
# Adapted from HefKer/nixos-config's homes/modules/game-focus-watcher.nix.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  watcher = pkgs.callPackage ../../pkgs/game-focus-watcher { };

  # App-id regexes (whole app-id) to kanata layers; the first match wins, so
  # osu!'s steam_app_0 (osu!stable under umu, like any game without a Steam id)
  # comes before Steam's.
  layers = [
    [
      "osu!"
      "passthrough"
    ]
    [
      "steam_app_0"
      "passthrough"
    ]
    [
      "steam_app_.*"
      "game"
    ]
  ];
  # Layers a key only holds on (layer-while-held), never saved as the layer to
  # restore: restored with ChangeLayer, a held layer stays on after the key is
  # released. Read from the keymap, so a new Fn layer is covered.
  heldLayers = lib.unique (
    map lib.head (
      lib.filter lib.isList (
        builtins.split "layer-while-held ([^ )]+)" (builtins.readFile ../../config/kanata/keymap.kbd)
      )
    )
  );

  ports = lib.mapAttrsToList (_: keyboard: keyboard.port) osConfig.services.kanata.keyboards;
in
{
  systemd.user.services.game-focus-watcher = {
    Unit = {
      Description = "Switch kanata to a game's layer while that game is focused";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.escapeShellArgs (
        [
          (lib.getExe watcher)
          "--niri"
          (lib.getExe osConfig.programs.niri.package)
        ]
        ++ lib.concatMap (layer: [ "--layer" ] ++ layer) layers
        ++ lib.concatMap (layer: [
          "--held-layer"
          layer
        ]) heldLayers
        ++ lib.concatMap (port: [
          "--port"
          (toString port)
        ]) ports
      );
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
