{
  networking.networkmanager.enable = true;

  # systemd-resolved owns DNS instead of openresolv. Tailscale hands MagicDNS
  # to it per interface rather than rewriting /etc/resolv.conf, which lost the
  # router as upstream resolver on the desktop.
  services.resolved.enable = true;

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

  # Lan Mouse (modules/home/lan-mouse.nix) is a HM user service too. Only the
  # tailnet may reach it: its sender doesn't verify the receiver's certificate,
  # so WireGuard is what authenticates the peer.
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [ 4242 ];

  # Log in once with `sudo tailscale up`. "client" loosens reverse-path
  # filtering so exit nodes and subnet routes work. --ssh turns on Tailscale
  # SSH: `ssh john@desktop` from the tailnet, no sshd or open port needed.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraSetFlags = [ "--ssh" ];
  };
}
