{
  config,
  lib,
  pkgs,
}:

let
  cfg = config.programs.openclaw;
  homeDir = config.home.homeDirectory;
  autoExcludeTools = lib.optionals config.programs.git.enable [ "git" ];
  effectiveExcludeTools = lib.unique (cfg.excludeTools ++ autoExcludeTools);
  toolOverrides = {
    toolNamesOverride = cfg.toolNames;
    excludeToolNames = effectiveExcludeTools;
  };
  toolOverridesEnabled = cfg.toolNames != null || effectiveExcludeTools != [ ];
  toolSets = import ../../../tools/extended.nix ({ inherit pkgs; } // toolOverrides);
  defaultPackage =
    if toolOverridesEnabled && cfg.package == pkgs.openclaw then
      (pkgs.openclawPackages.withTools toolOverrides).openclaw
    else
      cfg.package;
  appPackage = if cfg.appPackage != null then cfg.appPackage else defaultPackage;
  generatedConfigOptions = import ../../../generated/openclaw-config-options.nix { lib = lib; };
  pluginCatalog = import ./plugin-catalog.nix;

  bundledPluginSources =
    let
      openclawToolsRev = "08955054f466e2eb55628763c1d7ee2de5af9f6d";
      openclawToolsNarHash = "sha256-IsgLwW0Y6JYiWXbxmzN1FDO0//Osu2YpeID1tFMbwkk=";
      openclawTools =
        tool:
        "github:openclaw/nix-openclaw-tools?dir=tools/${tool}&rev=${openclawToolsRev}&narHash=${openclawToolsNarHash}";
    in
    lib.mapAttrs (_name: plugin: plugin.source or (openclawTools plugin.tool)) pluginCatalog;

  bundledPlugins = lib.filter (p: p != null) (
    lib.mapAttrsToList (
      name: source:
      let
        pluginCfg = cfg.bundledPlugins.${name};
      in
      if (pluginCfg.enable or false) then
        {
          inherit source;
          config = pluginCfg.config or { };
        }
      else
        null
    ) bundledPluginSources
  );

  effectivePlugins = cfg.customPlugins ++ bundledPlugins;

  resolvePath = p: if lib.hasPrefix "~/" p then "${homeDir}/${lib.removePrefix "~/" p}" else p;

  toRelative = p: if lib.hasPrefix "${homeDir}/" p then lib.removePrefix "${homeDir}/" p else p;

in
{
  inherit
    cfg
    homeDir
    toolOverrides
    toolOverridesEnabled
    toolSets
    defaultPackage
    appPackage
    generatedConfigOptions
    bundledPluginSources
    bundledPlugins
    effectivePlugins
    resolvePath
    toRelative
    ;
}
