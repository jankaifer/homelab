{
  description = "Homelab NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # agenix for secrets management
    # age-encrypted secrets that get decrypted at activation time
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix, ... }:
    let
      # Helper to create a NixOS system configuration
      # lib.nixosSystem is the standard way to define a NixOS machine in flakes
      mkSystem = { system ? "x86_64-linux", modules ? [] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            # Include agenix NixOS module for secrets support
            agenix.nixosModules.default
          ] ++ modules;
          # Pass flake inputs to all modules via specialArgs
          # This lets modules access 'inputs' if needed
          specialArgs = { inherit self; };
        };
    in
    {
      # NixOS configurations for each machine
      nixosConfigurations = {
        server = mkSystem {
          modules = [ ./machines/server ];
        };
      };

      # 'nix fmt' uses nixpkgs-fmt to format all .nix files
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
      formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.nixpkgs-fmt;
      formatter.x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.nixpkgs-fmt;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixpkgs-fmt;
    };
}
