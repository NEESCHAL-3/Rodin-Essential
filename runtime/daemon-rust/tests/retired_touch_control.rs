#![cfg(not(target_os = "android"))]

use rodin_essential_backend::handle_command;
use std::fs;

#[test]
fn removed_wake_control_is_not_restored_reported_or_saved_after_upgrade() {
    let dir = std::env::temp_dir().join(format!("rodin-retired-touch-{}", std::process::id()));
    fs::create_dir(&dir).unwrap();
    fs::write(
        dir.join("state.conf"),
        "touch=-1\ndt2w=1\ndisplay_color=2\n",
    )
    .unwrap();
    fs::write(
        dir.join("service.json"),
        r#"{"enabled":true,"configured":true,"release_pending":false,"originals":{"touch.dt2w":true}}"#,
    )
    .unwrap();
    // This executable has one test and no concurrent environment access.
    unsafe { std::env::set_var("RODIN_STATE_DIR", &dir) };

    let snapshot = handle_command("GET snapshot");
    assert!(!snapshot.contains("dt2w"), "{snapshot}");
    for value in [0, 1] {
        assert_eq!(
            handle_command(&format!("SET touch.dt2w {value}")),
            "ERR unknown command"
        );
    }
    // A normal OEM touch selection rewrites only supported preferences.
    assert_eq!(handle_command("SET touch 0"), "OK applied");
    let saved = fs::read_to_string(dir.join("state.conf")).unwrap();
    assert!(!saved.contains("dt2w"));
    assert!(saved.lines().any(|line| line == "display_color=2"));
    let service: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(dir.join("service.json")).unwrap()).unwrap();
    assert!(service["originals"].get("touch.dt2w").is_none());
    assert_eq!(service["enabled"], true);
    fs::remove_file(dir.join("state.conf")).unwrap();
    fs::remove_file(dir.join("service.json")).unwrap();
    fs::remove_dir(dir).unwrap();
}
