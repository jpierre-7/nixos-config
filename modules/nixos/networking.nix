{
  networking.networkmanager.enable = true;

  # NixOS's own firewall replaces firewalld. Syncthing runs as a Home Manager
  # user service, which can't open ports, so its sync and local-discovery
  # ports are opened here.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };

  # Log in once with `sudo tailscale up`. "client" loosens reverse-path
  # filtering so exit nodes and subnet routes work.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };
}
