{
  # Syncthing as a user service. Devices and folders are added in its web UI
  # (http://127.0.0.1:8384); device IDs are per machine, so they aren't
  # declared here. The override flags keep Home Manager from deleting them if
  # `settings` is ever filled in. Firewall ports: modules/nixos/networking.nix.
  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
  };
}
