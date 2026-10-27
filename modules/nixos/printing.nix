{
  # CUPS plus mDNS discovery of network printers (archinstall's printing option on Arch).
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  programs.system-config-printer.enable = true;
}
