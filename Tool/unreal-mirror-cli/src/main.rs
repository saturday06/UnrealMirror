use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};

const DEFAULT_TIMEOUT_MS: u32 = 5_000;
const RESPONSE_SIZE: usize = 8192;

extern "C" {
    fn unreal_mirror_ipc_send_command(
        command: *const std::os::raw::c_char,
        path: *const std::os::raw::c_char,
        timeout_ms: u32,
        response: *mut std::os::raw::c_char,
        response_len: usize,
    ) -> std::os::raw::c_int;
}

#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[arg(long, default_value_t = DEFAULT_TIMEOUT_MS)]
    timeout_ms: u32,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Ping,
    LoadVrm {
        #[arg(value_name = "VRM_PATH")]
        path: PathBuf,
    },
    LoadAnimation {
        #[arg(value_name = "VRMA_PATH")]
        path: PathBuf,
    },
    Screenshot {
        #[arg(value_name = "PNG_PATH")]
        path: PathBuf,
    },
    Shutdown,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let (command, path) = match cli.command {
        Command::Ping => ("ping", None),
        Command::LoadVrm { path } => ("load-vrm-model", Some(path)),
        Command::LoadAnimation { path } => ("load-vrm-animation", Some(path)),
        Command::Screenshot { path } => ("capture-png-screenshot", Some(path)),
        Command::Shutdown => ("shutdown", None),
    };

    let message = send_command(command, path, cli.timeout_ms)?;
    println!("{message}");
    Ok(())
}

fn send_command(command: &str, path: Option<PathBuf>, timeout_ms: u32) -> Result<String> {
    let path = path
        .map(|path| {
            path.canonicalize()
                .unwrap_or(path)
                .to_string_lossy()
                .into_owned()
        })
        .unwrap_or_default();
    let command = std::ffi::CString::new(command).context("command contains NUL byte")?;
    let path = std::ffi::CString::new(path).context("path contains NUL byte")?;
    let mut response = vec![0_i8; RESPONSE_SIZE];

    let code = unsafe {
        unreal_mirror_ipc_send_command(
            command.as_ptr(),
            path.as_ptr(),
            timeout_ms,
            response.as_mut_ptr(),
            response.len(),
        )
    };

    let response = unsafe { std::ffi::CStr::from_ptr(response.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    match code {
        0 => Ok(response),
        1 => bail!("{response}"),
        -2 => bail!("{response}"),
        _ => bail!("IPC failure: {response}"),
    }
}
