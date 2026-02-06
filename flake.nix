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

    # disko for declarative disk partitioning
    # Used by nixos-anywhere for automated installations
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # deploy-rs for safe, atomic NixOS deployments
    # Automatic rollback on failure
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix, disko, deploy-rs, ... }:
    let
      # Helper to create a NixOS system configuration
      # lib.nixosSystem is the standard way to define a NixOS machine in flakes
      mkSystem = { system ? "x86_64-linux", modules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            # Include agenix NixOS module for secrets support
            agenix.nixosModules.default
            # Include disko for declarative disk partitioning
            disko.nixosModules.disko
          ] ++ modules;
          # Pass flake inputs to all modules via specialArgs
          # This lets modules access 'inputs' if needed
          specialArgs = { inherit self; };
        };
    in
    {
      # Expose a pinned, project-local deploy command.
      # Usage: nix run .#deploy -- .#frame1 --skip-checks
      apps = builtins.mapAttrs (system: _:
        let
          deployPkg = deploy-rs.packages.${system}.deploy-rs;
        in
        {
          deploy = {
            type = "app";
            program = "${deployPkg}/bin/deploy";
          };
        }) deploy-rs.packages;

      # Dev shell with deploy-rs available as `deploy`.
      # Usage: nix develop, then run: deploy .#frame1 --skip-checks
      devShells = builtins.mapAttrs (system: _:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              deploy-rs.packages.${system}.deploy-rs
            ];
          };
        }) deploy-rs.packages;

      # NixOS configurations for each machine
      nixosConfigurations = {
        # Production server (x86_64) - for actual deployment
        frame1 = mkSystem {
          system = "x86_64-linux";
          modules = [ ./machines/frame1 ];
        };

        # VM for testing on Apple Silicon Macs (aarch64)
        # Use this for local development: nix build .#nixosConfigurations.frame1-vm.config.system.build.vm
        frame1-vm = mkSystem {
          system = "aarch64-linux";
          modules = [
            ./machines/frame1
            ./machines/frame1/vm.nix  # VM-specific: mounts host SSH for agenix
          ];
        };

        # Installer ISO for bootstrapping new servers
        # Build with: ./scripts/build-installer-iso.sh
        installer-iso = mkSystem {
          system = "x86_64-linux";
          modules = [ ./machines/installer-iso ];
        };
      };

      # 'nix fmt' uses nixpkgs-fmt to format all .nix files
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
      formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.nixpkgs-fmt;
      formatter.x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.nixpkgs-fmt;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixpkgs-fmt;

      # deploy-rs deployment configuration
      deploy.nodes = {
        frame1 = {
          # Connection details
          hostname = "192.168.2.241";

          # SSH settings
          sshUser = "jankaifer";

          # Profile configuration
          profiles.system = {
            # Use the NixOS system configuration
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.frame1;

            # Magic rollback settings
            # If activation fails or SSH breaks, auto-rollback after timeout
            magicRollback = true;
            autoRollback = true;
            confirmTimeout = 30; # seconds - confirm within 30s or rollback
          };
        };

        # VM testing target (Docker VM on localhost:2222)
        frame1-vm = {
          hostname = "localhost";
          sshUser = "jankaifer";
          sshOpts = [ "-p" "2222" ]; # VM SSH port

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.frame1-vm;

            magicRollback = true;
            autoRollback = true;
            confirmTimeout = 30;
          };
        };
      };

      # deploy-rs checks - validates deployment configuration
      # Run with: nix flake check
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
