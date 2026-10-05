#!/bin/bash
# Generate mpfs_pac from PolarfireSoC.svd using svd2ada
# Usage: ./generate_pac.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use the SVD from the local svd directory
SVD_FILE="${SCRIPT_DIR}/svd/PolarfireSoC.svd"
OUTPUT_DIR="${SCRIPT_DIR}/src"

echo "Generating mpfs_pac from SVD..."
echo "SVD file: ${SVD_FILE}"
echo "Output directory: ${OUTPUT_DIR}"

# Check if SVD file exists
if [ ! -f "${SVD_FILE}" ]; then
    echo "Error: SVD file not found at ${SVD_FILE}"
    exit 1
fi

# svd2ada is a host tool, not a project dependency (mpfs_pac is an L1 PAC
# crate, README.md §9 -- it must not depend on a generator at build time).
# Install it once with `alr install svd2ada`, which puts it on a shared
# install prefix (`alr install --info`), not in this crate's own closure.
if ! command -v svd2ada >/dev/null 2>&1; then
    echo "Error: svd2ada not found on PATH."
    echo "Install it once with: alr install svd2ada"
    echo "Then add its install prefix's bin/ dir to PATH (alr install --info)."
    exit 1
fi

# Clean previous generation
rm -rf "${OUTPUT_DIR}"/*

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

echo "Running svd2ada..."
svd2ada \
    -o "${OUTPUT_DIR}" \
    -p MPFS_MSS \
    --gen-uint-always \
    --no-uint-subtypes \
    --boolean \
    "${SVD_FILE}"

echo "PAC generation complete."
echo "Generated files in ${OUTPUT_DIR}:"
ls -la "${OUTPUT_DIR}"

# Run deduplication on grouped peripherals
echo "Running deduplication..."

# CAN peripherals - merge all CAN files
echo "  - CAN peripherals..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-can_*.ads

# GPIO peripherals (fabrics and IO banks)
echo "  - GPIO fabrics..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-gpio_fab*.ads
echo "  - GPIO IO banks..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-gpio_iobank*.ads

# H2F interrupt
echo "  - H2F interrupt..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-h2fint*.ads

# I2C peripherals
echo "  - I2C peripherals..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-i2c*.ads

# MMUART peripherals
echo "  - MMUART peripherals..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-mmuart*.ads

# MSRTC
echo "  - MSRTC..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-msrtc*.ads

# MSTIMER
echo "  - MSTIMER..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-mstimer*.ads

# SPI peripherals
echo "  - SPI peripherals..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-spi*.ads

# WDOG peripherals
echo "  - WDOG peripherals..."
python3 "${SCRIPT_DIR}/merge_duplicates.py" "${OUTPUT_DIR}"/mpfs_mss-wdog*.ads

echo "Deduplication complete."

# svd2ada 0.1.0's Find_Common_Types/Similar_Type (descriptors-register.adb)
# merges two no-field, same-prefix registers' Ada type without checking
# their declared <size> -- confirmed against PolarfireSoC.svd's CACHE_CTRL
# peripheral: FLUSH64 (64-bit) and FLUSH32 (32-bit) get the same Ada type,
# and GNAT rejects the narrower one ("size for "UInt64" too small"). This
# corrects every such mismatch from each field's own representation clause,
# which is authoritative (it comes straight from that register's own
# <addressOffset>/<size> and never crosses a register boundary the way the
# type-sharing heuristic does). Deterministic, re-run on every regeneration
# -- see fix_mistyped_registers.py's header for the full explanation.
echo "Correcting svd2ada's cross-register type-sharing bug..."
python3 "${SCRIPT_DIR}/fix_mistyped_registers.py" "${OUTPUT_DIR}"
