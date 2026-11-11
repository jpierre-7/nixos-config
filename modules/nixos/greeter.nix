# Login screen in the style of Omarchy's: greetd starts a niri of its own with
# a Quickshell greeter as its only client (config/greeter/). Password checks
# go through greetd's PAM service, so the keyring unlock in desktop.nix still
# applies. To go back to cosmic-greeter, drop this file from default.nix and
# set services.displayManager.cosmic-greeter.enable in desktop.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  niri = lib.getExe config.programs.niri.package;
  hm = config.home-manager.users.john;

  # Noctalia renders its palette here as john (modules/home/noctalia.nix). It
  # can't stay in /home/john, which the greeter user can't read.
  paletteDir = "/var/lib/greeter-palette";

  # john's Lan Mouse (modules/home/lan-mouse.nix) starts with his session, so
  # the login screen gets one of its own: the other machine can cross over and
  # type the password. Same trusted peers as the host's lan-mouse.toml, minus
  # [[clients]]: the listener takes any peer in authorized_fingerprints without
  # one, and without clients the greeter never sends its own input away. The
  # certificate is the greeter user's own, since senders don't verify it.
  lanMouseConfig = (pkgs.formats.toml { }).generate "greeter-lan-mouse.toml" (
    removeAttrs (lib.importTOML hm.xdg.configFile."lan-mouse/config.toml".source) [ "clients" ]
  );

  greeter = pkgs.writeShellScript "greeter" ''
    export GREETER_USER=john
    export GREETER_HOST=${config.networking.hostName}
    export GREETER_LOGO=${../../config/screensaver/nixos-logo.txt}
    export GREETER_SESSION=${config.programs.niri.package}/bin/niri-session
    export GREETER_PALETTE=${paletteDir}/palette.json
    ${lib.getExe pkgs.lan-mouse} -c ${lanMouseConfig} \
      --cert-path ${config.users.users.greeter.home}/lan-mouse.pem daemon &
    lan_mouse=$!
    # It holds UDP 4242, which john's Lan Mouse needs once he's logged in, so it
    # has to end with the greeter however that ends.
    trap 'kill $lan_mouse 2>/dev/null' EXIT HUP TERM
    ${lib.getExe pkgs.quickshell} -p ${../../config/greeter/shell.qml}
    kill $lan_mouse 2>/dev/null
    wait $lan_mouse
    # However the greeter ended (a login or a crash), end niri too: greetd then
    # starts the session, or a new greeter.
    ${niri} msg action quit --skip-confirmation
  '';
in
{
  services.greetd = {
    enable = true;
    settings.default_session.command = "${niri} -c /etc/greetd/niri.kdl";
  };

  # The same monitor layout john's niri gets (hosts/<host>/default.nix links
  # it to ~/.config/niri/host.kdl). The flake's niri-config check validates
  # this file for both hosts.
  environment.etc."greetd/niri.kdl".text = ''
    ${builtins.readFile ../../config/greeter/niri.kdl}
    ${lib.optionalString (hm.xdg.configFile ? "niri/host.kdl") (
      builtins.readFile hm.xdg.configFile."niri/host.kdl".source
    )}
    spawn-at-startup "${greeter}"
  '';

  # A writable home for the Mesa and Quickshell caches; greetd's greeter user
  # has none.
  users.users.greeter = {
    home = "/var/lib/greeter";
    createHome = true;
  };

  systemd.tmpfiles.settings.greeter-palette.${paletteDir}.d = {
    user = "john";
    group = "users";
    mode = "0755";
  };
}
