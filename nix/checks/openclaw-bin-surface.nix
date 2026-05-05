{
  lib,
  stdenvNoCC,
  openclawPackage,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-bin-surface";
  version = lib.getVersion openclawPackage;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  env = {
    OPENCLAW_PACKAGE = openclawPackage;
  };

  doCheck = true;
  checkPhase = "${../scripts/check-openclaw-bin-surface.sh}";
  installPhase = "${../scripts/empty-install.sh}";
}
