use std::env;
use std::path::PathBuf;

fn main() {
    let boost_include = env::var_os("UNREAL_MIRROR_BOOST_INCLUDE_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            env::var_os("UE_ROOT").map(|root| {
                PathBuf::from(root)
                    .join("..")
                    .join("..")
                    .join("Source")
                    .join("ThirdParty")
                    .join("Boost")
                    .join("Deploy")
                    .join("boost-1.85.0")
                    .join("include")
            })
        })
        .unwrap_or_else(|| {
            PathBuf::from(r"C:\Program Files\Epic Games\UE_5.7\Engine\Source\ThirdParty\Boost\Deploy\boost-1.85.0\include")
        });

    println!("cargo:rerun-if-env-changed=UNREAL_MIRROR_BOOST_INCLUDE_DIR");
    println!("cargo:rerun-if-env-changed=UE_ROOT");
    println!("cargo:rerun-if-changed=native/unreal_mirror_ipc.cpp");
    println!("cargo:rerun-if-changed=native/unreal_mirror_ipc.h");

    let mut build = cc::Build::new();
    build
        .cpp(true)
        .std("c++17")
        .include(boost_include)
        .define("BOOST_ALL_NO_LIB", None)
        .file("native/unreal_mirror_ipc.cpp");

    if cfg!(target_env = "msvc") {
        build.flag("/EHsc").flag("/utf-8");
        println!("cargo:rustc-link-lib=advapi32");
    }

    build.compile("unreal_mirror_ipc");
}
