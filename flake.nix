{
  description = "NixOS configuration for john's desktop and laptop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for the few packages that are missing or too old on stable;
    # see overlays/default.nix and the README.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      # Keep this branch in step with the nixpkgs branch above.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Linked to ~/Pictures/Wallpapers; Noctalia's default wallpaper comes from here.
    wallpapers = {
      url = "github:jpierre-7/Wallpapers";
      flake = false;
    };
    # Patched AirPods daemon for the Noctalia AirPods plugin; built by pkgs/librepods.nix.
    librepods = {
      url = "github:harveywuk/librepods";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Where this repo is cloned on each machine. Configs that apps rewrite
      # themselves (and the Neovim config) are symlinked here instead of into
      # the read-only Nix store, so they stay editable without a rebuild.
      repoDir = "/home/john/nixos-config";

      mkHost =
        hostname:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${hostname}
            ./modules/nixos
            home-manager.nixosModules.home-manager
            {
              networking.hostName = hostname;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # Move pre-existing files aside instead of failing the first switch.
                backupFileExtension = "hm-backup";
                extraSpecialArgs = { inherit inputs repoDir; };
                users.john = ./home/john.nix;
              };
            }
          ];
        };

      # Package set of a real host, so checks use the same versions (and overlay) as the machines.
      pkgs = self.nixosConfigurations.desktop.pkgs;
      hm = self.nixosConfigurations.desktop.config.home-manager.users.john;
    in
    {
      nixosConfigurations = {
        desktop = mkHost "desktop";
        laptop = mkHost "laptop";
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;

      # `nix flake check` parses the hand-written niri config and the generated
      # Noctalia config with the exact versions that will run them.
      checks.${system} = {
        niri-config = pkgs.runCommand "niri-config-check" { nativeBuildInputs = [ pkgs.niri ]; } ''
          export HOME=$TMPDIR
          mkdir cfg
          cp ${./config/niri/config.kdl} cfg/config.kdl
          niri validate -c cfg/config.kdl
          # Again with the desktop's outputs in place of the optional include.
          cp ${./hosts/desktop/niri-outputs.kdl} cfg/host.kdl
          niri validate -c cfg/config.kdl
          touch $out
        '';

        noctalia-config =
          pkgs.runCommand "noctalia-config-check" { nativeBuildInputs = [ pkgs.noctalia ]; }
            ''
              export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_STATE_HOME=$TMPDIR/state
              noctalia config validate ${hm.xdg.configFile."noctalia/noctalia-config.toml".source}
              touch $out
            '';
      };
    };
}
