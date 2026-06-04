#[test]
#[ignore = "requires UnrealMirror runtime with IPC server running"]
fn unreal_ipc_server_accepts_command() {
    let status = std::process::Command::new(env!("CARGO_BIN_EXE_unreal-mirror-cli"))
        .args([
            "--timeout-ms",
            "1000",
            "screenshot",
            "C:\\Temp\\unreal-mirror-test.png",
        ])
        .status()
        .expect("failed to run CLI");

    assert!(status.success());
}
