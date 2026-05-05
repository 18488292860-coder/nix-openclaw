{
  openclawToolPkgs ? { },
}:
final: prev:
let
  packages = import ./packages {
    pkgs = prev;
    openclawToolPkgs = openclawToolPkgs;
  };
  toolNames =
    (import ./tools/extended.nix {
      pkgs = prev;
      openclawToolPkgs = openclawToolPkgs;
    }).toolNames;
  withTools =
    {
      toolNamesOverride ? null,
      excludeToolNames ? [ ],
    }:
    import ./packages {
      pkgs = prev;
      openclawToolPkgs = openclawToolPkgs;
      inherit toolNamesOverride excludeToolNames;
    };
in
packages
// {
  openclawPackages = packages // {
    inherit toolNames withTools;
  };
}
