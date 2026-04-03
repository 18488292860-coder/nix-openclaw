{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  nodejs_22,
  pnpm_10,
  fetchPnpmDeps,
  pkg-config,
  jq,
  python3,
  node-gyp,
  vips,
  git,
  zstd,
  sourceInfo,
  pnpmDepsHash ? (sourceInfo.pnpmDepsHash or null),
}:

let
  common =
    import ../lib/openclaw-gateway-common.nix
      {
        inherit
          lib
          stdenv
          fetchFromGitHub
          fetchurl
          nodejs_22
          pnpm_10
          fetchPnpmDeps
          pkg-config
          jq
          python3
          node-gyp
          git
          zstd
          ;
      }
      {
        pname = "openclaw-source-smoke";
        sourceInfo = sourceInfo;
        pnpmDepsHash = pnpmDepsHash;
        pnpmDepsPname = "openclaw-gateway";
        enableSharp = true;
        extraBuildInputs = [ vips ];
      };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw-source-smoke";
  inherit (common) version;

  src = common.resolvedSrc;
  pnpmDeps = common.pnpmDeps;

  nativeBuildInputs = common.nativeBuildInputs;
  buildInputs = common.buildInputs;

  env = common.env // {
    OPENCLAW_BUILD_MODE = "source-smoke";
    PNPM_DEPS = finalAttrs.pnpmDeps;
  };

  passthru = common.passthru;

  postPatch = "${../scripts/gateway-postpatch.sh}";
  buildPhase = "${../scripts/gateway-build.sh}";
  installPhase = "${../scripts/empty-install.sh}";
  dontPatchShebangs = true;
})
