// Reusable Cargo build.rs template: capture the short git SHA at build time
// without a `vergen` dependency. Copy into a crate's `build.rs`, adjust the
// `println!("cargo:rustc-env=...")` name if the crate needs a different env
// var than `ARCANA_GIT_SHA`.
//
// Integration: read the value at runtime via `env!("ARCANA_GIT_SHA")`.
// Falls back to "0000000" (preserves the `[0-9a-f]{7}` regex shape) when the
// crate is built from a crates.io tarball with no `.git` directory.

fn main() {
    let sha = std::process::Command::new("git")
        .args(["rev-parse", "--short=7", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "0000000".to_string());

    println!("cargo:rustc-env=ARCANA_GIT_SHA={sha}");
    println!("cargo:rerun-if-changed=../../.git/HEAD");
    println!("cargo:rerun-if-changed=../../.git/refs/heads");
}
