{
  description = "mAIn OS — headless OS for AI agents (Phase 0: minimal Firecracker microVM)";

  # microvm.nix gives us NixOS-in-Firecracker plumbing for free, so our own code
  # only has to express the *personality* of mAIn OS (minimal, immutable, headless
  # + the supervisor stub), not reimplement the hypervisor wiring.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # The runner microvm.nix builds — /bin/microvm-run boots the Firecracker guest.
      runner = self.nixosConfigurations.mainos.config.microvm.declaredRunner;
    in
    {
      # The mAIn OS Phase 0 system: a headless NixOS booting as a Firecracker microVM.
      nixosConfigurations.mainos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          ./nix/mainos.nix
          ./nix/supervisor.nix
        ];
      };

      packages.${system} = {
        default = runner;
        mainos-runner = runner;

        # Thin control CLI. `mainctl build|run|info`.
        mainctl = pkgs.writeShellApplication {
          name = "mainctl";
          runtimeInputs = [ pkgs.nix pkgs.coreutils ];
          text = builtins.readFile ./scripts/mainctl;
        };
      };

      # `nix run .#mainos` boots the microVM directly.
      apps.${system} = {
        default = {
          type = "app";
          program = "${runner}/bin/microvm-run";
        };
        mainos = {
          type = "app";
          program = "${runner}/bin/microvm-run";
        };
        mainctl = {
          type = "app";
          program = "${self.packages.${system}.mainctl}/bin/mainctl";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ self.packages.${system}.mainctl pkgs.firecracker ];
        shellHook = ''
          echo "mAIn OS Phase 0 dev shell — try: mainctl info"
        '';
      };
    };
}
