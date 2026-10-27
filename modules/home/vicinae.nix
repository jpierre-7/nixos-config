{ config, repoDir, ... }:
{
  # Package only. Niri starts `vicinae server` (spawn-at-startup in config.kdl),
  # so Home Manager's systemd unit stays off.
  programs.vicinae.enable = true;

  # Live link, because Vicinae's GUI rewrites settings.json itself.
  xdg.configFile."vicinae/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${repoDir}/config/vicinae/settings.json";
}
