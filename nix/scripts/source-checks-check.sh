#!/bin/sh
set -e

if [ -z "${CONFIG_OPTIONS_CHECK_SH:-}" ]; then
  echo "CONFIG_OPTIONS_CHECK_SH is not set" >&2
  exit 1
fi
if [ ! -f "$CONFIG_OPTIONS_CHECK_SH" ]; then
  echo "CONFIG_OPTIONS_CHECK_SH not found: $CONFIG_OPTIONS_CHECK_SH" >&2
  exit 1
fi

if [ -n "${OPENCLAW_BUILD_ROOT_SH:-}" ]; then
  . "$OPENCLAW_BUILD_ROOT_SH"
  openclaw_enter_build_root
  trap openclaw_cleanup_output_build_root EXIT
fi

"$CONFIG_OPTIONS_CHECK_SH"
