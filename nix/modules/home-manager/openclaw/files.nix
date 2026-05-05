{
  config,
  lib,
  pkgs,
  openclawLib,
  enabledInstances,
  plugins,
}:

let
  cfg = openclawLib.cfg;
  resolvePath = openclawLib.resolvePath;
  toRelative = openclawLib.toRelative;
  toolSets = openclawLib.toolSets;
  documentsEnabled = cfg.documents != null;
  instanceWorkspaceDirs = map (inst: resolvePath inst.workspaceDir) (lib.attrValues enabledInstances);

  renderSkill =
    skill:
    let
      frontmatterLines = [
        "---"
        "name: ${skill.name}"
        "description: ${skill.description or ""}"
      ]
      ++ lib.optionals (skill ? homepage && skill.homepage != null) [ "homepage: ${skill.homepage}" ]
      ++ lib.optionals (skill ? openclaw && skill.openclaw != null) [
        "openclaw:"
        "  ${builtins.toJSON skill.openclaw}"
      ]
      ++ [ "---" ];
      frontmatter = lib.concatStringsSep "\n" frontmatterLines;
      body = if skill ? body then skill.body else "";
    in
    "${frontmatter}\n\n${body}\n";

  duplicateSkillAssertion =
    let
      targetsForInstance =
        instName: inst:
        let
          base = "${toRelative (resolvePath inst.workspaceDir)}/skills";
          userTargets = map (skill: "${base}/${skill.name}") cfg.skills;
          pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
          pluginTargets = lib.flatten (
            map (p: map (skillPath: "${base}/${builtins.baseNameOf skillPath}") p.skills) pluginsForInstance
          );
        in
        userTargets ++ pluginTargets;
      skillTargets = lib.flatten (lib.mapAttrsToList targetsForInstance enabledInstances);
      counts = lib.foldl' (acc: path: acc // { "${path}" = (acc.${path} or 0) + 1; }) { } skillTargets;
      duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
    in
    if duplicates == [ ] then
      [ ]
    else
      [
        {
          assertion = false;
          message = "Duplicate skill paths detected: ${lib.concatStringsSep ", " duplicates}";
        }
      ];

  skillFiles =
    let
      entriesForInstance =
        instName: inst:
        let
          base = "${toRelative (resolvePath inst.workspaceDir)}/skills";
          entryFor =
            skill:
            let
              mode = skill.mode or "symlink";
              source = if skill ? source && skill.source != null then resolvePath skill.source else null;
            in
            if mode == "inline" then
              {
                name = "${base}/${skill.name}/SKILL.md";
                value = {
                  text = renderSkill skill;
                };
              }
            else if mode == "copy" then
              {
                name = "${base}/${skill.name}";
                value = {
                  source = builtins.path {
                    name = "openclaw-skill-${skill.name}";
                    path = source;
                  };
                  recursive = true;
                };
              }
            else
              {
                name = "${base}/${skill.name}";
                value = {
                  source = config.lib.file.mkOutOfStoreSymlink source;
                  recursive = true;
                };
              };
          pluginEntriesFor =
            p:
            map (skillPath: {
              name = "${base}/${builtins.baseNameOf skillPath}";
              value = {
                source = skillPath;
                recursive = true;
              };
            }) p.skills;
          pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
        in
        (map entryFor cfg.skills) ++ (lib.flatten (map pluginEntriesFor pluginsForInstance));
    in
    lib.listToAttrs (lib.flatten (lib.mapAttrsToList entriesForInstance enabledInstances));

  documentsRequiredFiles = [
    "AGENTS.md"
    "SOUL.md"
    "TOOLS.md"
  ];

  documentsOptionalFiles = [
    "IDENTITY.md"
    "USER.md"
    "LORE.md"
    "HEARTBEAT.md"
    "PROMPTING-EXAMPLES.md"
  ];

  documentsFileNames =
    if documentsEnabled then
      let
        extra = lib.filter (file: builtins.pathExists (cfg.documents + "/${file}")) documentsOptionalFiles;
      in
      documentsRequiredFiles ++ extra
    else
      [ ];

  documentsAssertions = lib.optionals documentsEnabled [
    {
      assertion = builtins.pathExists cfg.documents;
      message = "programs.openclaw.documents must point to an existing directory.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/AGENTS.md");
      message = "Missing AGENTS.md in programs.openclaw.documents.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/SOUL.md");
      message = "Missing SOUL.md in programs.openclaw.documents.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/TOOLS.md");
      message = "Missing TOOLS.md in programs.openclaw.documents.";
    }
  ];

  documentsGuard = lib.optionalString documentsEnabled (
    let
      guardLine = file: ''
        if [ -e "${file}" ] && [ ! -L "${file}" ]; then
          echo "OpenClaw documents are managed by Nix. Please adopt ${file} into your documents directory and re-run." >&2
          exit 1
        fi
      '';
      guardForDir = dir: ''
        ${lib.concatStringsSep "\n" (map (name: guardLine "${dir}/${name}") documentsFileNames)}
      '';
    in
    lib.concatStringsSep "\n" (map guardForDir instanceWorkspaceDirs)
  );

  toolsReport =
    if documentsEnabled then
      let
        toolNames = toolSets.toolNames or [ ];
        renderPkgName = pkg: if pkg ? pname then pkg.pname else lib.getName pkg;
        renderPlugin =
          plugin:
          let
            pkgNames = map renderPkgName (lib.filter (p: p != null) plugin.packages);
            pkgSuffix = if pkgNames == [ ] then "" else " — " + (lib.concatStringsSep ", " pkgNames);
          in
          "- " + plugin.name + pkgSuffix + " (" + plugin.source + ")";
        pluginLinesFor =
          instName: inst:
          let
            pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
            lines = if pluginsForInstance == [ ] then [ "- (none)" ] else map renderPlugin pluginsForInstance;
          in
          [
            ""
            "### Instance: ${instName}"
          ]
          ++ lines;
        reportLines = [
          "<!-- BEGIN NIX-REPORT -->"
          ""
          "## Nix-managed tools"
          ""
          "### Built-in toolchain"
        ]
        ++ (if toolNames == [ ] then [ "- (none)" ] else map (name: "- " + name) toolNames)
        ++ [
          ""
          "## Nix-managed plugin report"
          ""
          "Plugins enabled per instance (last-wins on name collisions):"
        ]
        ++ lib.concatLists (lib.mapAttrsToList pluginLinesFor enabledInstances)
        ++ [
          ""
          "Tools: batteries-included toolchain + plugin-provided CLIs."
          ""
          "<!-- END NIX-REPORT -->"
        ];
        reportText = lib.concatStringsSep "\n" reportLines;
      in
      pkgs.writeText "openclaw-tools-report.md" reportText
    else
      null;

  toolsWithReport =
    if documentsEnabled then
      pkgs.runCommand "openclaw-tools-with-report.md" { } ''
        cat ${cfg.documents + "/TOOLS.md"} > $out
        echo "" >> $out
        cat ${toolsReport} >> $out
      ''
    else
      null;

  documentsFiles =
    if documentsEnabled then
      let
        mkDocFiles =
          dir:
          let
            mkDoc = name: {
              name = toRelative (dir + "/${name}");
              value = {
                source = if name == "TOOLS.md" then toolsWithReport else cfg.documents + "/${name}";
              };
            };
          in
          lib.listToAttrs (map mkDoc documentsFileNames);
      in
      lib.mkMerge (map mkDocFiles instanceWorkspaceDirs)
    else
      { };

in
{
  inherit
    documentsEnabled
    documentsAssertions
    documentsGuard
    documentsFiles
    duplicateSkillAssertion
    skillFiles
    ;
}
