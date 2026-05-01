{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.4.29";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.4.29/OpenClaw-2026.4.29.zip";
    hash = "sha256-be0ZZ2bsvhnyZZZdRxIsmIvM7f6cPeOxBxeQMJH1zRU=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
