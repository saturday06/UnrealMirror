use std::{
    fs::File,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const APP_START_TIMEOUT: Duration = Duration::from_secs(60);
const APP_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(15);
const CLI_PROCESS_TIMEOUT: Duration = Duration::from_secs(45);
const CLI_TIMEOUT_MS: &str = "30000";

struct UnrealMirrorApp {
    app_root: PathBuf,
    child: Child,
    log_path: PathBuf,
    stdout_path: PathBuf,
}

impl UnrealMirrorApp {
    fn log_tail(&self) -> String {
        let log_path = if self.log_path.is_file() {
            &self.log_path
        } else {
            &self.stdout_path
        };

        match std::fs::read_to_string(log_path) {
            Ok(log) => {
                let mut lines = log.lines().rev().take(80).collect::<Vec<_>>();
                lines.reverse();
                lines.join("\n")
            }
            Err(error) => format!("failed to read app log {}: {error}", log_path.display()),
        }
    }

    fn request_shutdown_and_wait(&mut self) -> anyhow::Result<()> {
        run_cli_without_path("shutdown")?;
        self.wait_for_exit(APP_SHUTDOWN_TIMEOUT)
    }

    fn wait_for_exit(&mut self, timeout: Duration) -> anyhow::Result<()> {
        let deadline = Instant::now() + timeout;
        loop {
            if !self.is_running()? {
                return Ok(());
            }
            if Instant::now() >= deadline {
                return Err(anyhow::anyhow!(
                    "UnrealMirror app did not exit within {} seconds after shutdown command",
                    timeout.as_secs()
                ));
            }
            thread::sleep(Duration::from_millis(250));
        }
    }

    fn is_running(&mut self) -> anyhow::Result<bool> {
        let child_running = self.child.try_wait()?.is_none();

        #[cfg(windows)]
        {
            Ok(child_running || windows_app_processes_running(&self.app_root)?)
        }

        #[cfg(not(windows))]
        {
            Ok(child_running)
        }
    }
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

    let log_path = temp_log_path();
    let stdout_path = temp_file_path("stdout.log");
    let stdout_log = File::create(&stdout_path)?;
    let stderr_log = stdout_log.try_clone()?;

    let mut command = Command::new(&app);
    command
        .args([
            "-RenderOffscreen",
            "-unattended",
            "-nosplash",
            "-nopause",
            "-stdout",
            "-FullStdOutLogOutput",
        ])
        .arg(format!("-abslog={}", log_path.display()))
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout_log))
        .stderr(Stdio::from(stderr_log));

    #[cfg(windows)]
    {
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let child = command.spawn()?;
    Ok(UnrealMirrorApp {
        app_root,
        child,
        log_path,
        stdout_path,
    })
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

#[cfg(windows)]
fn windows_app_processes_running(app_root: &Path) -> anyhow::Result<bool> {
    let app_root = app_root.to_string_lossy().replace('\'', "''");
    let script = format!(
        "$root = [IO.Path]::GetFullPath('{app_root}').TrimEnd('\\') + '\\'; \
         $process = Get-CimInstance Win32_Process | \
         Where-Object {{ $_.ExecutablePath -and $_.ExecutablePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) }} | \
         Select-Object -First 1; \
         if ($process) {{ '1' }} else {{ '0' }}"
    );

    let output = Command::new("pwsh")
        .args(["-NoProfile", "-Command", &script])
        .stdin(Stdio::null())
        .output()?;

    if !output.status.success() {
        return Err(anyhow::anyhow!(
            "failed to inspect UnrealMirror app processes\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim() == "1")
}

struct CliOutput {
    success: bool,
    stdout: String,
    stderr: String,
    timed_out: bool,
}

fn run_cli_process(
    command: &str,
    path: Option<&Path>,
    timeout_ms: &str,
    process_timeout: Duration,
) -> anyhow::Result<CliOutput> {
    let stdout_path = temp_file_path("cli.stdout.log");
    let stderr_path = temp_file_path("cli.stderr.log");
    let stdout_log = File::create(&stdout_path)?;
    let stderr_log = File::create(&stderr_path)?;

    let mut process = Command::new(env!("CARGO_BIN_EXE_unreal-mirror-cli"));
    process
        .args(["--timeout-ms", timeout_ms, command])
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout_log))
        .stderr(Stdio::from(stderr_log));
    if let Some(path) = path {
        process.arg(path);
    }

    let mut child = process.spawn()?;
    let deadline = Instant::now() + process_timeout;
    let mut timed_out = false;
    let success = loop {
        if let Some(status) = child.try_wait()? {
            break status.success();
        }
        if Instant::now() >= deadline {
            timed_out = true;
            let _ = child.kill();
            let _ = child.wait();
            break false;
        }
        thread::sleep(Duration::from_millis(100));
    };

    let stdout = std::fs::read_to_string(&stdout_path).unwrap_or_default();
    let stderr = std::fs::read_to_string(&stderr_path).unwrap_or_default();
    let _ = std::fs::remove_file(stdout_path);
    let _ = std::fs::remove_file(stderr_path);

    Ok(CliOutput {
        success,
        stdout,
        stderr,
        timed_out,
    })
}

fn run_cli(command: &str, path: &Path) -> anyhow::Result<()> {
    let output = run_cli_process(command, Some(path), CLI_TIMEOUT_MS, CLI_PROCESS_TIMEOUT)?;

    if output.success {
        Ok(())
    } else {
        let timeout_message = if output.timed_out {
            format!(
                "\nprocess timeout: exceeded {} seconds",
                CLI_PROCESS_TIMEOUT.as_secs()
            )
        } else {
            String::new()
        };
        Err(anyhow::anyhow!(
            "CLI command failed: {command}{timeout_message}\nstdout:\n{}\nstderr:\n{}",
            output.stdout,
            output.stderr
        ))
    }
}

fn run_cli_without_path(command: &str) -> anyhow::Result<()> {
    let output = run_cli_process(command, None, CLI_TIMEOUT_MS, CLI_PROCESS_TIMEOUT)?;

    if output.success {
        Ok(())
    } else {
        let timeout_message = if output.timed_out {
            format!(
                "\nprocess timeout: exceeded {} seconds",
                CLI_PROCESS_TIMEOUT.as_secs()
            )
        } else {
            String::new()
        };
        Err(anyhow::anyhow!(
            "CLI command failed: {command}{timeout_message}\nstdout:\n{}\nstderr:\n{}",
            output.stdout,
            output.stderr
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
    temp_file_path("png")
}

fn temp_log_path() -> PathBuf {
    temp_file_path("log")
}

fn temp_file_path(extension: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before UNIX_EPOCH")
        .as_nanos();
    std::env::temp_dir().join(format!("unreal-mirror-ipc-{nanos}.{extension}"))
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
        let output = run_cli_process(command, Some(&path), "1000", Duration::from_secs(5))
            .expect("failed to run CLI");

        assert!(
            output.success,
            "{command} command failed\nstdout:\n{}\nstderr:\n{}",
            output.stdout, output.stderr
        );
    }

    let _ = std::fs::remove_file(output_png);
}

#[test]
#[ignore = "requires packaged UnrealMirror app; set UNREAL_MIRROR_APP_EXE or run Tool/build.ps1 first"]
fn packaged_unreal_app_accepts_ipc_commands() -> anyhow::Result<()> {
    let mut app = start_unreal_mirror_app()?;
    wait_for_ipc_server()?;

    run_cli("load-animation", &resource_path("vrma/nop.vrma"))?;
    thread::sleep(Duration::from_millis(500));

    let output_png = temp_png_path();
    let _ = std::fs::remove_file(&output_png);
    run_cli("screenshot", &output_png).map_err(|error| {
        anyhow::anyhow!("{error}\n\nUnrealMirror log tail:\n{}", app.log_tail())
    })?;

    let actual_png = std::fs::read(&output_png)?;
    assert!(
        actual_png.len() > 256,
        "rendered PNG is unexpectedly small: {} bytes",
        actual_png.len()
    );
    assert_eq!(&actual_png[..8], b"\x89PNG\r\n\x1a\n");

    let _ = std::fs::remove_file(output_png);
    app.request_shutdown_and_wait()?;
    Ok(())
}
