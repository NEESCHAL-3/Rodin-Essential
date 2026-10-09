#![cfg(not(target_os = "android"))]

use rodin_essential_backend::handle_command;
use std::fs;
use std::process::Command;

#[test]
fn service_lifecycle_survives_process_restart() {
    if let Ok(expected) = std::env::var("RODIN_TEST_EXPECT_ENABLED") {
        let snapshot = handle_command("GET snapshot");
        assert!(
            snapshot.contains(&format!("service_enabled={expected}")),
            "{snapshot}"
        );
        if expected == "0" {
            assert!(handle_command("SET cpu.gov 0 performance").contains("disabled"));
            assert!(handle_command("SET system.colors.wallpaper").contains("disabled"));
            assert!(handle_command("ACTION gpu.uncap_full_speed").contains("disabled"));
        }
        return;
    }
    let dir = std::env::temp_dir().join(format!("rodin-service-test-{}", std::process::id()));
    fs::create_dir(&dir).unwrap();
    // This test executable has one test, with no concurrent environment access.
    unsafe {
        std::env::set_var("RODIN_STATE_DIR", &dir);
    }
    assert_eq!(handle_command("SET service.enabled 0"), "OK applied");
    let disabled = fs::read_to_string(dir.join("service.json")).unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&disabled).unwrap()["enabled"],
        false
    );
    let run_child = |enabled: &str| {
        let status = Command::new(std::env::current_exe().unwrap())
            .arg("--exact")
            .arg("service_lifecycle_survives_process_restart")
            .env("RODIN_TEST_EXPECT_ENABLED", enabled)
            .status()
            .unwrap();
        assert!(status.success());
    };
    run_child("0");
    assert_eq!(handle_command("SET service.enabled 1"), "OK applied");
    // OEM selection requires no vendor HAL and persists as no override.
    for command in ["SET touch 0", "SET display.color -1", "SET display.temp -1"] {
        assert_eq!(handle_command(command), "OK applied", "{command}");
    }
    let oem = handle_command("GET snapshot");
    for field in ["touch=-1", "display_color=-1", "display_temp=-1"] {
        assert!(oem.split(';').any(|value| value == field), "{oem}");
    }
    // This is a non-Android test executable: no GPU driver exists. The
    // attempted selection still populates the applied-selection cache, which
    // Reset must invalidate even when the hardware apply could not verify.
    let _ = handle_command("SET perf 2");
    assert!(
        handle_command("GET snapshot")
            .split(';')
            .any(|v| v == "perf=2")
    );
    assert_eq!(handle_command("ACTION service.reset"), "OK applied");
    let snapshot = handle_command("GET snapshot");
    for field in ["perf=-1", "touch=-1", "display_color=-1", "display_temp=-1"] {
        assert!(
            snapshot.split(';').any(|value| value == field),
            "stale {field}: {snapshot}"
        );
    }
    let reset = fs::read_to_string(dir.join("state.conf")).unwrap();
    for setting in [
        "charging=-1",
        "touch=-1",
        "cpu_manual=-1",
        "perf=-1",
        "zram_size_mb=-1",
        "zram_algorithm=",
        "zram_swappiness=-1",
        "display_color=-1",
        "display_temp=-1",
        "display_width=-1",
        "display_height=-1",
        "display_density=-1",
        "sunlight=-1",
        "silky=-1",
        "video=-1",
        "dolby=-1",
        "gpu_min_freq_mhz=-1",
        "gpu_max_freq_mhz=-1",
        "gpu_governor=",
        "gpu_power_policy=",
        "gpu_ged_boost=-1",
        "cpu_min_freq0=-1",
        "cpu_max_freq0=-1",
        "cpu0=",
        "cpu4=",
        "cpu7=",
        "io=",
        "bypass_charging=0",
    ] {
        assert!(
            reset.lines().any(|line| line == setting),
            "missing {setting}"
        );
    }
    let control: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.join("service.json")).unwrap()).unwrap();
    assert_eq!(control["enabled"], true);
    assert_eq!(control["configured"], false);
    assert_eq!(control["release_pending"], false);
    run_child("1");
    // Only remove the exact temporary test directory created above.
    fs::remove_file(dir.join("state.conf")).unwrap();
    fs::remove_file(dir.join("service.json")).unwrap();
    fs::remove_file(dir.join("app-profiles.json")).unwrap();
    fs::remove_dir(dir).unwrap();
}
