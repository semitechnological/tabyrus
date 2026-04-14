# eq-swift

UniFFI bridge crate for generating a Swift-friendly API from Rust.

## What it gives you

- `String` <-> Swift `String`
- `Vec<u8>` <-> Swift `Data`
- Rust records <-> Swift structs
- Rust objects <-> Swift classes
- `Option<T>` and lists mapped into native Swift shapes

## Build

```bash
cargo build --manifest-path eq-swift/Cargo.toml
```

The build script generates the Rust scaffolding and, when `uniffi-bindgen` is available, writes Swift bindings to `eq-swift/swift/Generated/`.

## Override the generator

```bash
UNIFFI_BINDGEN=/path/to/uniffi-bindgen cargo build --manifest-path eq-swift/Cargo.toml
```
