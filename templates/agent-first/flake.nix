{
  description = "OpenClaw local";

  inputs = {
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    nixpkgs.follows = "nix-openclaw/nixpkgs";
    home-manager.follows = "nix-openclaw/home-manager";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-openclaw,
    }:
    let
      # REPLACE: aarch64-darwin (Apple Silicon), x86_64-darwin (Intel), or x86_64-linux
      system = "<system>";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-openclaw.overlays.default ];
      };
    in
    {
      # REPLACE: <user> with your username (run `whoami`)
      homeConfigurations."<user>" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          nix-openclaw.homeManagerModules.openclaw
          {
            # Required for Home Manager standalone
            home.username = "<user>";
            # REPLACE: /Users/<user> on macOS or /home/<user> on Linux
            home.homeDirectory = "<homeDir>";
            home.stateVersion = "24.11";
            programs.home-manager.enable = true;

            programs.openclaw = {
              # REPLACE: path to your managed documents directory
              documents = ./documents;

              # Schema-typed OpenClaw config (from upstream)
              config = {
                gateway = {
                  mode = "local";
                  auth = {
                    # REPLACE: long random token for gateway auth
                    token = "<gatewayToken>";
                  };
                };

                channels.telegram = {
                  # REPLACE: path to your bot token file
                  tokenFile = "<tokenPath>";
                  # REPLACE: your Telegram user ID (get from @userinfobot)
                  allowFrom = [ <allowFrom> ];
                  groups = {
                    "*" = {
                      requireMention = true;
                    };
                  };
                };
              };

              enable = true;
            };
          }
        ];
      };
    };
}
