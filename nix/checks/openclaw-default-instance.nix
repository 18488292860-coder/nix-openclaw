{
  lib,
  pkgs,
  stdenv,
}:

let
  lockedPathFlake =
    name: path: narHash:
    let
      # If a fixture changes, update with: nix hash path --sri nix/tests/plugins/<name>
      storePath = builtins.path {
        inherit name path;
        sha256 = narHash;
      };
    in
    "path:${builtins.unsafeDiscardStringContext (toString storePath)}?narHash=${narHash}";

  alphaPluginSource =
    lockedPathFlake "openclaw-test-plugin-alpha" ../tests/plugins/alpha
      "sha256-FV4UN38sPy2Yp/HhqUxd0HW5l2PcIBBmUz4JzxTAOXY=";
  betaPluginSource =
    lockedPathFlake "openclaw-test-plugin-beta" ../tests/plugins/beta
      "sha256-lDKtQKHZHqOkOprjLZzBEu8cFJhAdyEzsays9hdVeqE=";

  stubModule =
    { lib, ... }:
    {
      options = {
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };

        home.homeDirectory = lib.mkOption {
          type = lib.types.str;
          default = "/tmp";
        };

        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };

        home.file = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        home.activation = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        launchd.agents = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        systemd.user.services = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        programs.git.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        lib = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  moduleEval =
    openclawConfig:
    lib.evalModules {
      modules = [
        stubModule
        ../modules/home-manager/openclaw.nix
        (
          { lib, ... }:
          {
            config = {
              home.homeDirectory = "/tmp";
              programs.git.enable = false;
              lib.file.mkOutOfStoreSymlink = path: path;
              programs.openclaw = {
                enable = true;
                launchd.enable = false;
                systemd.enable = true;
              }
              // openclawConfig;
            };
          }
        )
      ];
      specialArgs = { inherit pkgs; };
    };

  failedAssertions =
    eval: lib.filter (assertion: !(assertion.assertion or false)) eval.config.assertions;

  requireNoAssertionFailures =
    name: eval:
    let
      failures = failedAssertions eval;
      messages = map (assertion: assertion.message or "(no message)") failures;
    in
    if failures == [ ] then "ok" else throw "${name}: ${lib.concatStringsSep "; " messages}";

  requireAssertionFailure =
    name: needle: eval:
    let
      failures = failedAssertions eval;
      matching = lib.filter (assertion: lib.hasInfix needle (assertion.message or "")) failures;
    in
    if matching != [ ] then "ok" else throw "${name}: expected assertion containing `${needle}`.";

  defaultEval = moduleEval { };
  hasUnit = builtins.hasAttr "openclaw-gateway" defaultEval.config.systemd.user.services;
  defaultCheck = builtins.deepSeq (requireNoAssertionFailures "default instance" defaultEval) (
    if hasUnit then "ok" else throw "Default OpenClaw instance missing systemd.unitName."
  );

  customPluginEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
    ];
  };
  customPluginSkill = ".openclaw/workspace/skills/skill";
  hasCustomPluginSkill = builtins.hasAttr customPluginSkill customPluginEval.config.home.file;
  customPluginCheck = builtins.deepSeq (requireNoAssertionFailures "customPlugins" customPluginEval) (
    if hasCustomPluginSkill then "ok" else throw "customPlugins did not install ${customPluginSkill}."
  );

  duplicateSkillEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
      { source = betaPluginSource; }
    ];
  };
  duplicateSkillCheck =
    requireAssertionFailure "duplicate plugin skills"
      "Duplicate skill paths detected: ${customPluginSkill}"
      duplicateSkillEval;

  userPluginSkillCollisionEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
    ];
    skills = [
      {
        name = "skill";
        mode = "inline";
      }
    ];
  };
  userPluginSkillCollisionCheck =
    requireAssertionFailure "user/plugin skill collision"
      "Duplicate skill paths detected: ${customPluginSkill}"
      userPluginSkillCollisionEval;

  checkKey = builtins.deepSeq [
    defaultCheck
    customPluginCheck
    duplicateSkillCheck
    userPluginSkillCollisionCheck
  ] "ok";

in
stdenv.mkDerivation {
  pname = "openclaw-default-instance";
  version = "1";
  dontUnpack = true;
  env = {
    OPENCLAW_DEFAULT_INSTANCE = checkKey;
  };
  installPhase = "${../scripts/empty-install.sh}";
}
