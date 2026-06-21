#!/usr/bin/env bash
set -euo pipefail

VIVADO_BIN="${VIVADO:-vivado}"
EXPECTED_VERSION="${XILINX_EXPECTED_VERSION:-2025.2}"

if ! command -v "${VIVADO_BIN}" >/dev/null 2>&1; then
    echo "FAIL: Vivado executable not found: ${VIVADO_BIN}" >&2
    exit 1
fi

version_output="$("${VIVADO_BIN}" -version)"
if ! grep -Fiq "vivado v${EXPECTED_VERSION}" <<<"${version_output}"; then
    echo "FAIL: expected Vivado ${EXPECTED_VERSION}" >&2
    printf '%s\n' "${version_output}" >&2
    exit 1
fi

echo "PASS: found Vivado ${EXPECTED_VERSION}"
make xilinx-cdc VIVADO="${VIVADO_BIN}"
echo "PASS: Xilinx self-hosted runner is ready"
