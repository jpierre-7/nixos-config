{ pkgs, inputs, ... }:
{
  # Snapmaker Orca, Snapmaker's OrcaSlicer fork for the U1; nixpkgs has only
  # upstream orca-slicer. The flake's module also adds the CJK fonts whose
  # absence crashes its language picker.
  imports = [ inputs.snapmaker-orca.nixosModules.default ];

  programs.snapmaker-orca = {
    enable = true;
    # The workaround forces Mesa's zink to dodge NVIDIA's EGL. Both hosts are
    # AMD/Intel on Mesa already, so use the native driver.
    package =
      inputs.snapmaker-orca.packages.${pkgs.stdenv.hostPlatform.system}.snapmaker-orca.override
        { withNvidiaGLWorkaround = false; };
  };
}
