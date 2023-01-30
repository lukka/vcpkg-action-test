// Simplified from https://github.com/rustdesk/rustdesk/blob/dd2315a5186ff23950efc7afaa36548513a2c7f9/libs/scrap/build.rs

use std::{
    env, fs,
    path::{Path, PathBuf},
};

fn generate_bindings(
    ffi_header: &Path,
    include_paths: &[PathBuf],
    ffi_rs: &Path,
    exact_file: &Path,
) {
    let mut b = bindgen::builder()
        .header(ffi_header.to_str().unwrap())
        .allowlist_type("^[vV].*")
        .allowlist_var("^[vV].*")
        .allowlist_function("^[vV].*")
        .rustified_enum("^v.*")
        .trust_clang_mangling(false)
        .layout_tests(false) // breaks 32/64-bit compat
        .generate_comments(false); // vpx comments have prefix /*!\

    for dir in include_paths {
        b = b.clang_arg(format!("-I{}", dir.display()));
    }

    b.generate().unwrap().write_to_file(ffi_rs).unwrap();
    fs::copy(ffi_rs, exact_file).ok(); // ignore failure
}

fn gen_vpx() {
    let library = vcpkg::Config::new()
        .emit_includes(true)
        .find_package("libvpx")
        .unwrap();

    let includes = library.include_paths;
    let src_dir = env::var_os("CARGO_MANIFEST_DIR").unwrap();
    let src_dir = Path::new(&src_dir);
    let out_dir = env::var_os("OUT_DIR").unwrap();
    let out_dir = Path::new(&out_dir);

    let ffi_header = src_dir.join("vpx_ffi.h");
    println!("rerun-if-changed={}", ffi_header.display());

    for dir in &includes {
        println!("rerun-if-changed={}", dir.display());
    }

    let ffi_rs = out_dir.join("vpx_ffi.rs");
    let exact_file = src_dir.join("generated").join("vpx_ffi.rs");
    generate_bindings(&ffi_header, &includes, &ffi_rs, &exact_file);
}

fn main() {
    env::remove_var("CARGO_CFG_TARGET_FEATURE");
    env::set_var("CARGO_CFG_TARGET_FEATURE", "crt-static");

    gen_vpx();
}
