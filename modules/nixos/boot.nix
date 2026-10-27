{
  boot.loader = {
    limine = {
      enable = true;
      efiSupport = true;
      # Every generation keeps its kernel and initrd on the ESP; capping the
      # menu keeps /boot from filling up. Older generations still exist in the
      # store until garbage-collected (modules/nixos/nix.nix).
      maxGenerations = 10;
    };
    # Normal UEFI install: let NixOS add Limine to the firmware's boot entries.
    efi.canTouchEfiVariables = true;
  };

  # linux-firmware and sof-firmware (laptop audio); also turns on the CPU
  # microcode updates that the generated hardware-configuration.nix asks for.
  hardware.enableRedistributableFirmware = true;

  # Compressed swap in RAM (what archinstall's zram-generator set up on Arch).
  zramSwap.enable = true;
}
