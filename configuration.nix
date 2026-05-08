{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  
  # Keybinds
  services.xserver.xkb.options = "caps:escape";

  services.power-profiles-daemon.enable = true;

  services.upower.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  
  fonts = {
      packages = with pkgs; [
        maple-mono.truetype
      ];
    };

  # Enable CUPS to print documents.
  services.printing.enable = true;
  
  # Enable Bluetooth
  hardware.bluetooth.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    home = "/home/john";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # onlyoffice
  services.onlyoffice = {
    enable = true;
    securityNonceFile = "/run/secrets/onlyoffice-nonce";
  };

  systemd.tmpfiles.rules = [
    "f /run/secrets/onlyoffice-nonce 0600 onlyoffice onlyoffice -"
  ];

  # Programs
  programs = {
      fish.enable = true;
      pay-respects.enable = true;
      git.enable = true;
      niri.enable = true;
      neovim.enable = true;
  };

  programs.nix-ld.enable = true;

  programs.vscode = {
    enable = true;

    extensions = with pkgs.vscode-extensions; [
      ms-python.python
      ms-toolsai.jupyter
      mechatroner.rainbow-csv
      dracula-theme.theme-dracula
    ];
  }; 

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.lazygit.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    xwayland-satellite # Needed for X11 apps
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    ani-cli
    gcc
    imagemagick
    lua55Packages.luarocks
    fd
    ripgrep
    vicinae
    burpsuite
    unzip
    gnumake
    kdePackages.kate
    starship
    fastfetch
    wezterm
    python315
    wget
    discord
    vivaldi
  ];

  services.tailscale.enable = true;

  # Enable the OpenSSH daemon.
   services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
