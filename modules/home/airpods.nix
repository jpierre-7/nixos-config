{ inputs, pkgs, ... }:
let
  librepods = pkgs.callPackage ../../pkgs/librepods.nix { src = inputs.librepods; };
in
{
  # Daemon and librepods-ctl for the Noctalia AirPods plugin (harveywuk/airpods).
  # The plugin finds librepods-ctl on PATH, so it needs no ctl_path.
  home.packages = [ librepods ];

  # The package ships librepods.service; this links it into the user unit path
  # and enables it the way `systemctl --user enable` would.
  systemd.user.packages = [ librepods ];
  xdg.configFile."systemd/user/graphical-session.target.wants/librepods.service".source =
    "${librepods}/share/systemd/user/librepods.service";
}
