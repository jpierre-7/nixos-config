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

  # ASMedia USB-SATA bridge (174c:55aa) in the dual-bay drive enclosure: under
  # UAS it times out and resets every ~30s and the disks never become readable.
  # The `u` flag makes the kernel use plain usb-storage for it instead.
  boot.kernelParams = [ "usb-storage.quirks=174c:55aa:u" ];
}
