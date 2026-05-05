{
  description = "nix-openclaw: declarative OpenClaw packaging";

  nixConfig = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-openclaw-tools.url = "github:openclaw/nix-openclaw-tools";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      home-manager,
      nix-openclaw-tools,
    }:
    let
      openclawToolPkgsFor =
        system:
        if nix-openclaw-tools ? packages && builtins.hasAttr system nix-openclaw-tools.packages then
          nix-openclaw-tools.packages.${system}
        else
          { };
      overlay =
        final: prev:
        import ./nix/overlay.nix {
          openclawToolPkgs = openclawToolPkgsFor prev.stdenv.hostPlatform.system;
        } final prev;
      sourceInfoStable = import ./nix/sources/openclaw-source.nix;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
        openclawToolPkgs = openclawToolPkgsFor system;
        packageSetStable = import ./nix/packages {
          pkgs = pkgs;
          sourceInfo = sourceInfoStable;
          openclawToolPkgs = openclawToolPkgs;
        };
      in
      {
        formatter = pkgs.nixfmt-tree.override {
          settings = {
            global.excludes = [ "nix/generated/openclaw-config-options.nix" ];
          };
        };

        packages = packageSetStable // {
          default = packageSetStable.openclaw;
        };

        apps = {
          openclaw = flake-utils.lib.mkApp { drv = packageSetStable.openclaw-gateway; };
        };

        checks =
          let
            baseChecks = {
              gateway = packageSetStable.openclaw-gateway;
              bin-surface = pkgs.callPackage ./nix/checks/openclaw-bin-surface.nix {
                openclawPackage = packageSetStable.openclaw;
              };
              package-contents = pkgs.callPackage ./nix/checks/openclaw-package-contents.nix {
                openclawGateway = packageSetStable.openclaw-gateway;
              };
              config-validity = pkgs.callPackage ./nix/checks/openclaw-config-validity.nix {
                openclawGateway = packageSetStable.openclaw-gateway;
              };
              gateway-smoke = pkgs.callPackage ./nix/checks/openclaw-gateway-smoke.nix {
                openclawGateway = packageSetStable.openclaw-gateway;
              };
            }
            // (
              if pkgs.stdenv.hostPlatform.isLinux then
                let
                  sourceChecks = pkgs.callPackage ./nix/checks/openclaw-source-checks.nix {
                    sourceInfo = sourceInfoStable;
                    openclawGateway = packageSetStable.openclaw-gateway;
                  };
                in
                {
                  config-options = sourceChecks;
                  source-checks = sourceChecks;
                  default-instance = pkgs.callPackage ./nix/checks/openclaw-default-instance.nix { };
                  hm-activation = import ./nix/checks/openclaw-hm-activation.nix {
                    inherit pkgs home-manager;
                  };
                }
              else
                { }
            );
          in
          baseChecks
          // {
            # CI aggregator: build the expensive gateway once, then run all checks in the
            # same build machine/store to avoid cache-miss races between parallel jobs.
            ci = pkgs.symlinkJoin {
              name = "nix-openclaw-ci";
              paths = [
                packageSetStable.openclaw
                packageSetStable.openclaw-gateway
              ]
              ++ (builtins.attrValues baseChecks);
            };
          };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.git
            pkgs.nixfmt-tree
            pkgs.nil
          ];
        };
      }
    )
    // {
      overlays.default = overlay;
      templates.agent-first = {
        path = ./templates/agent-first;
        description = "Agent-first Home Manager setup for OpenClaw through Nix.";
      };
      nixosModules.openclaw-gateway = import ./nix/modules/nixos/openclaw-gateway.nix;
      homeManagerModules.openclaw = import ./nix/modules/home-manager/openclaw.nix;
      darwinModules.openclaw = import ./nix/modules/darwin/openclaw.nix;
    };
}
