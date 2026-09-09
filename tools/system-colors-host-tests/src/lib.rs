#![allow(dead_code)]

use std::process::Output as ProcessOutput;
use std::time::Duration;

fn run_process_with_timeout(
    _program: &str,
    _args: &[&str],
    _timeout: Duration,
) -> Result<ProcessOutput, String> {
    Err("Android commands are unavailable in host tests".into())
}

#[path = "../../../runtime/daemon-rust/src/system_colors.rs"]
mod system_colors;
