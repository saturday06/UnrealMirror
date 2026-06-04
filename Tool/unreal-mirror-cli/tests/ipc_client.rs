use std::path::{Path, PathBuf};

fn resource_path(relative_path: impl AsRef<Path>) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("resources")
        .join(relative_path)
}

#[test]
fn test_data_files_are_available() {
    let vrm = resource_path("vrm/triangle.vrm");
    let vrma = resource_path("vrma/nop.vrma");
    let png = resource_path("png/dummy.png");

    assert!(vrm.is_file(), "missing test VRM: {}", vrm.display());
    assert!(vrma.is_file(), "missing test VRMA: {}", vrma.display());
    assert!(png.is_file(), "missing test PNG: {}", png.display());

    let png_bytes = std::fs::read(&png).expect("failed to read dummy PNG");
    assert_eq!(&png_bytes[..8], b"\x89PNG\r\n\x1a\n");
}

#[test]
#[ignore = "requires UnrealMirror runtime with IPC server running"]
fn unreal_ipc_server_accepts_test_data_paths() {
    let test_cases = [
        ("load-vrm", resource_path("vrm/triangle.vrm")),
        ("load-animation", resource_path("vrma/nop.vrma")),
        ("screenshot", resource_path("png/dummy.png")),
    ];

    for (command, path) in test_cases {
        let status = std::process::Command::new(env!("CARGO_BIN_EXE_unreal-mirror-cli"))
            .args(["--timeout-ms", "1000", command])
            .arg(path)
            .status()
            .expect("failed to run CLI");

        assert!(status.success(), "{command} command failed");
    }
}
