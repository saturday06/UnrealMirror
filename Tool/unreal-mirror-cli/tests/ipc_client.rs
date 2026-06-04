use std::{
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const APP_START_TIMEOUT: Duration = Duration::from_secs(60);
const CLI_TIMEOUT_MS: &str = "5000";

struct UnrealMirrorApp {
    app_root: PathBuf,
    child: Child,
}

impl Drop for UnrealMirrorApp {
    fn drop(&mut self) {
        #[cfg(windows)]
        terminate_windows_app_processes(&self.app_root, self.child.id());

        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn resource_path(relative_path: impl AsRef<Path>) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("resources")
        .join(relative_path)
}

fn project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("CLI crate should live under Tool/unreal-mirror-cli")
        .to_path_buf()
}

fn find_unreal_mirror_app() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("UNREAL_MIRROR_APP_EXE") {
        return Some(PathBuf::from(path));
    }

    let root = project_root();
    [
        root.join("ArchivedBuilds"),
        root.join("Saved").join("StagedBuilds"),
    ]
    .into_iter()
    .find_map(|path| find_file_named(&path, "UnrealMirror.exe"))
}

fn find_file_named(directory: &Path, file_name: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(directory).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file()
            && path
                .file_name()
                .is_some_and(|name| name.eq_ignore_ascii_case(file_name))
        {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = find_file_named(&path, file_name) {
                return Some(found);
            }
        }
    }
    None
}

fn start_unreal_mirror_app() -> anyhow::Result<UnrealMirrorApp> {
    let app = find_unreal_mirror_app().ok_or_else(|| {
        anyhow::anyhow!(
            "UnrealMirror.exe was not found. Set UNREAL_MIRROR_APP_EXE to a packaged app binary."
        )
    })?;
    let app_root = app
        .parent()
        .ok_or_else(|| anyhow::anyhow!("app path has no parent: {}", app.display()))?
        .to_path_buf();

    let mut command = Command::new(&app);
    command
        .args(["-nullrhi", "-unattended", "-nosplash", "-nopause"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(windows)]
    {
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let child = command.spawn()?;
    Ok(UnrealMirrorApp { app_root, child })
}

#[cfg(windows)]
fn terminate_windows_app_processes(app_root: &Path, root_pid: u32) {
    let _ = Command::new("taskkill")
        .args(["/PID", &root_pid.to_string(), "/T", "/F"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();

    let app_root = app_root.to_string_lossy().replace('\'', "''");
    let script = format!(
        "$root = [IO.Path]::GetFullPath('{app_root}').TrimEnd('\\') + '\\'; \
         Get-CimInstance Win32_Process | \
         Where-Object {{ $_.ExecutablePath -and $_.ExecutablePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) }} | \
         Sort-Object ProcessId -Descending | \
         ForEach-Object {{ Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }}"
    );

    let _ = Command::new("pwsh")
        .args(["-NoProfile", "-Command", &script])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn run_cli(command: &str, path: &Path) -> anyhow::Result<()> {
    let output = Command::new(env!("CARGO_BIN_EXE_unreal-mirror-cli"))
        .args(["--timeout-ms", CLI_TIMEOUT_MS, command])
        .arg(path)
        .output()?;

    if output.status.success() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(
            "CLI command failed: {command}\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ))
    }
}

fn wait_for_ipc_server() -> anyhow::Result<()> {
    let deadline = Instant::now() + APP_START_TIMEOUT;
    let vrm = resource_path("vrm/triangle.vrm");

    loop {
        match run_cli("load-vrm", &vrm) {
            Ok(()) => return Ok(()),
            Err(error) if Instant::now() < deadline => {
                eprintln!("waiting for UnrealMirror IPC server: {error}");
                thread::sleep(Duration::from_secs(1));
            }
            Err(error) => return Err(error),
        }
    }
}

fn temp_png_path() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before UNIX_EPOCH")
        .as_nanos();
    std::env::temp_dir().join(format!("unreal-mirror-ipc-{nanos}.png"))
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
    let output_png = temp_png_path();
    let test_cases = [
        ("load-vrm", resource_path("vrm/triangle.vrm")),
        ("load-animation", resource_path("vrma/nop.vrma")),
        ("screenshot", output_png.clone()),
    ];

    for (command, path) in test_cases {
        let status = std::process::Command::new(env!("CARGO_BIN_EXE_unreal-mirror-cli"))
            .args(["--timeout-ms", "1000", command])
            .arg(path)
            .status()
            .expect("failed to run CLI");

        assert!(status.success(), "{command} command failed");
    }

    let _ = std::fs::remove_file(output_png);
}

#[test]
#[ignore = "requires packaged UnrealMirror app; set UNREAL_MIRROR_APP_EXE or run Tool/build.ps1 first"]
fn packaged_unreal_app_accepts_ipc_commands() -> anyhow::Result<()> {
    let _app = start_unreal_mirror_app()?;
    wait_for_ipc_server()?;

    run_cli("load-animation", &resource_path("vrma/nop.vrma"))?;

    let output_png = temp_png_path();
    let _ = std::fs::remove_file(&output_png);
    run_cli("screenshot", &output_png)?;

    let expected_png = std::fs::read(resource_path("png/dummy.png"))?;
    let actual_png = std::fs::read(&output_png)?;
    assert_eq!(actual_png, expected_png);

    let _ = std::fs::remove_file(output_png);
    Ok(())
}
