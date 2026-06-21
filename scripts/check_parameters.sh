#!/usr/bin/env bash
set -euo pipefail

IVERILOG_BIN="${IVERILOG:-iverilog}"
VVP_BIN="${VVP:-vvp}"
BUILD_DIR="${TMPDIR:-/tmp}/async_fifo_parameter_checks"

mkdir -p "${BUILD_DIR}"

expect_failure() {
    local name="$1"
    local expected="$2"
    shift 2

    "${IVERILOG_BIN}" -g2012 -s "$@" \
        -o "${BUILD_DIR}/${name}.out" -f rtl/files.f

    if "${VVP_BIN}" "${BUILD_DIR}/${name}.out" \
        >"${BUILD_DIR}/${name}.log" 2>&1; then
        echo "FAIL: ${name} unexpectedly succeeded" >&2
        return 1
    fi

    if ! grep -Fq "${expected}" "${BUILD_DIR}/${name}.log"; then
        echo "FAIL: ${name} did not report: ${expected}" >&2
        cat "${BUILD_DIR}/${name}.log" >&2
        return 1
    fi
}

expect_failure invalid_ratio \
    "must have an integer ratio" \
    async_fifo_width_conv \
    -Pasync_fifo_width_conv.WDATA_WIDTH=24 \
    -Pasync_fifo_width_conv.RDATA_WIDTH=16 \
    -Pasync_fifo_width_conv.ADDR_WIDTH=4

expect_failure invalid_stream_width \
    "must be a positive multiple of eight" \
    async_fifo_stream \
    -Pasync_fifo_stream.WDATA_WIDTH=12 \
    -Pasync_fifo_stream.RDATA_WIDTH=32 \
    -Pasync_fifo_stream.ADDR_WIDTH=4

expect_failure invalid_address_width \
    "ADDR_WIDTH is too small" \
    async_fifo_width_conv \
    -Pasync_fifo_width_conv.WDATA_WIDTH=8 \
    -Pasync_fifo_width_conv.RDATA_WIDTH=64 \
    -Pasync_fifo_width_conv.ADDR_WIDTH=2

expect_failure invalid_reset_stages \
    "async_reset_sync STAGES must be at least two" \
    async_reset_sync \
    -Pasync_reset_sync.STAGES=1

echo "PASS: invalid parameter combinations fail with clear diagnostics"
