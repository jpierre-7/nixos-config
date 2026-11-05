# Mouse and keyboard sharing across screen edges. Niri has no InputCapture portal
# or EIS, so Lan Mouse falls through to its layer-shell backend and emulates with
# wlr-virtual-pointer and virtual-keyboard. Each host links its own config.toml
# (hosts/*/lan-mouse.toml). The key in ~/.config/lan-mouse/lan-mouse.pem is
# generated on first start and stays out of the repo.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.lan-mouse ];

  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "Lan Mouse";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      X-Restart-Triggers = [ "${config.xdg.configFile."lan-mouse/config.toml".source}" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.lan-mouse} daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
