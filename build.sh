#!/bin/bash
set -euo pipefail

echo "=== Tabyrus Build ==="
echo ""

echo "--- Building Rust backend ---"
cargo build --release
echo ""

echo "--- Building Swift frontend ---"
swift build -c release
echo ""

echo "=== Build complete ==="
echo "Binary: .build/release/tabyrus"
echo "Library: target/release/libtabyrus_backend.dylib"
echo ""
echo "To run: swift run"
