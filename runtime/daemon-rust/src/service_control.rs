//! Durable service intent and write-ahead originals. No periodic restore writes.
use serde_json::{Map, Value};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Condvar, Mutex, OnceLock, RwLock};

pub(super) static GATE: RwLock<()> = RwLock::new(());
static CONTROL: OnceLock<Mutex<Control>> = OnceLock::new();
static WAKE: Condvar = Condvar::new();
static RESTORING: AtomicBool = AtomicBool::new(false);

pub(super) struct Restoration;
impl Restoration {
    pub(super) fn begin() -> Self {
        RESTORING.store(true, Ordering::Release);
        Self
    }
}
impl Drop for Restoration {
    fn drop(&mut self) {
        RESTORING.store(false, Ordering::Release);
    }
}

struct Control {
    enabled: bool,
    configured: bool,
    originals: Map<String, Value>,
    release_pending: bool,
}

fn control() -> &'static Mutex<Control> {
    CONTROL.get_or_init(|| {
        let raw = fs::read_to_string(super::state_dir().join("service.json"));
        let parsed = raw
            .as_ref()
            .ok()
            .and_then(|raw| serde_json::from_str::<Value>(raw).ok());
        // A corrupt intent file must not silently turn hardware control back on.
        let enabled = if raw.is_ok() {
            parsed
                .as_ref()
                .and_then(|v| v["enabled"].as_bool())
                .unwrap_or(false)
        } else {
            matches!(
                raw.as_ref().err().map(io::Error::kind),
                Some(io::ErrorKind::NotFound)
            )
        };
        let configured = parsed
            .as_ref()
            .and_then(|v| v["configured"].as_bool())
            .unwrap_or_else(|| super::state_file().exists());
        let originals = parsed
            .as_ref()
            .and_then(|v| v["originals"].as_object().cloned())
            .unwrap_or_default();
        let release_pending = parsed
            .as_ref()
            .and_then(|v| v["release_pending"].as_bool())
            .unwrap_or(false);
        Mutex::new(Control {
            enabled,
            configured,
            originals,
            release_pending,
        })
    })
}

fn save(control: &Control) -> Result<(), String> {
    let dir = super::state_dir();
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
    let data = serde_json::json!({"enabled": control.enabled, "configured": control.configured, "originals": control.originals, "release_pending": control.release_pending});
    let path = dir.join("service.json");
    let tmp = dir.join("service.json.tmp");
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)
        .map_err(|e| e.to_string())?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|e| e.to_string())?;
    file.write_all(data.to_string().as_bytes())
        .map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    fs::rename(tmp, path).map_err(|e| e.to_string())?;
    fs::File::open(dir)
        .and_then(|file| file.sync_all())
        .map_err(|e| e.to_string())
}

pub(super) fn enabled() -> bool {
    control().lock().map(|s| s.enabled).unwrap_or(false)
}
pub(super) fn active() -> bool {
    control()
        .lock()
        .map(|s| s.enabled && s.configured)
        .unwrap_or(false)
}

pub(super) fn set_intent(enabled: bool, configured: bool) -> Result<(), String> {
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    let previous = (state.enabled, state.configured);
    state.enabled = enabled;
    state.configured = configured;
    if let Err(error) = save(&state) {
        (state.enabled, state.configured) = previous;
        return Err(error);
    }
    WAKE.notify_all();
    Ok(())
}

pub(super) fn wait_until_active() {
    if let Ok(state) = control().lock() {
        drop(WAKE.wait_while(state, |s| !s.enabled || !s.configured));
    }
}

pub(super) fn release_pending() -> bool {
    control().lock().map(|s| s.release_pending).unwrap_or(true)
}
pub(super) fn set_release_pending(value: bool) -> Result<(), String> {
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    let old = state.release_pending;
    state.release_pending = value;
    if let Err(error) = save(&state) {
        state.release_pending = old;
        return Err(error);
    }
    Ok(())
}

pub(super) fn configured() -> bool {
    control().lock().map(|s| s.configured).unwrap_or(false)
}

pub(super) fn remember(key: &str, value: Value) -> Result<(), String> {
    if RESTORING.load(Ordering::Acquire) {
        return Ok(());
    }
    let key = canonical_key(key);
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    if state.originals.contains_key(&key) {
        return Ok(());
    }
    state.originals.insert(key.clone(), value);
    if let Err(error) = save(&state) {
        state.originals.remove(&key);
        return Err(error);
    }
    Ok(())
}

pub(super) fn original(key: &str) -> Option<Value> {
    control()
        .lock()
        .ok()?
        .originals
        .get(&canonical_key(key))
        .cloned()
}

fn canonical_key(key: &str) -> String {
    if key.starts_with("/sys/") {
        if let Ok(path) = fs::canonicalize(key) {
            return path.to_string_lossy().into_owned();
        }
    }
    key.to_string()
}

pub(super) fn replace(key: &str, value: Value) -> Result<(), String> {
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    let previous = state.originals.insert(key.to_string(), value);
    if let Err(error) = save(&state) {
        match previous {
            Some(old) => {
                state.originals.insert(key.into(), old);
            }
            None => {
                state.originals.remove(key);
            }
        }
        return Err(error);
    }
    Ok(())
}

pub(super) fn originals() -> Vec<(String, Value)> {
    control()
        .lock()
        .map(|s| {
            s.originals
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect()
        })
        .unwrap_or_default()
}

pub(super) fn clear_originals() -> Result<(), String> {
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    let old = std::mem::take(&mut state.originals);
    if let Err(error) = save(&state) {
        state.originals = old;
        return Err(error);
    }
    Ok(())
}

pub(super) fn forget(keys: &[String]) -> Result<(), String> {
    let mut state = control()
        .lock()
        .map_err(|_| "service state lock poisoned")?;
    let old = state.originals.clone();
    for key in keys {
        state.originals.remove(key);
    }
    if let Err(error) = save(&state) {
        state.originals = old;
        return Err(error);
    }
    Ok(())
}

fn reversible_path(path: &Path) -> bool {
    let raw = path.to_string_lossy();
    (raw.starts_with("/sys/")
        || raw.starts_with("/proc/sys/")
        || raw.starts_with("/proc/touch_boost/"))
        && !matches!(
            path.file_name().and_then(|v| v.to_str()),
            Some(
                "reset"
                    | "compact"
                    | "drop_caches"
                    | "disksize"
                    | "comp_algorithm"
                    | "bypass_charging"
                    | "bypass_charge"
            )
        )
        && raw.as_ref() != super::MI_THERMAL_CPU_LIMITS
        && raw.as_ref() != super::MTK_POWERHAL_CPU_FREQ
}

pub(super) fn normalized_original(path: &Path, raw: &str) -> String {
    if matches!(
        path.file_name().and_then(|v| v.to_str()),
        Some("custom_boost_gpu_freq" | "custom_upbound_gpu_freq")
    ) {
        return raw.lines().next().unwrap_or("").trim().to_string();
    }
    if matches!(
        path.file_name().and_then(|v| v.to_str()),
        Some("scheduler" | "power_policy")
    ) {
        if let Some(selected) = raw
            .split_whitespace()
            .find_map(|s| s.strip_prefix('[').and_then(|s| s.strip_suffix(']')))
        {
            return selected.to_string();
        }
    }
    if path.file_name().and_then(|v| v.to_str()) == Some("switch_report_rate") {
        if raw.contains("240") {
            return "0".into();
        }
        if raw.contains("480") {
            return "1".into();
        }
    }
    raw.trim().to_string()
}

pub(super) fn write(path: impl AsRef<Path>, contents: impl AsRef<[u8]>) -> io::Result<()> {
    let path = path.as_ref();
    if !RESTORING.load(Ordering::Acquire)
        && reversible_path(path)
        && original(&path.to_string_lossy()).is_none()
    {
        let raw = fs::read_to_string(path)?;
        remember(
            &path.to_string_lossy(),
            Value::String(normalized_original(path, &raw)),
        )
        .map_err(io::Error::other)?;
    }
    fs::write(path, contents)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extracts_selected_kernel_options() {
        assert_eq!(
            normalized_original(
                Path::new("/sys/block/sda/queue/scheduler"),
                "none [mq-deadline] kyber"
            ),
            "mq-deadline"
        );
        assert_eq!(
            normalized_original(
                Path::new("/sys/mali/power_policy"),
                "[coarse_demand] always_on"
            ),
            "coarse_demand"
        );
        assert_eq!(
            normalized_original(
                Path::new("/sys/kernel/ged/hal/custom_boost_gpu_freq"),
                "40\n123:pid:1 value:40"
            ),
            "40"
        );
    }
    #[test]
    fn never_journals_one_shot_or_write_only_controls() {
        for path in [
            "/sys/block/zram0/reset",
            "/sys/block/zram0/compact",
            super::super::MI_THERMAL_CPU_LIMITS,
            super::super::MTK_POWERHAL_CPU_FREQ,
        ] {
            assert!(!reversible_path(Path::new(path)));
        }
        assert!(reversible_path(Path::new(
            "/sys/module/ged/parameters/gpu_dvfs_enable"
        )));
    }
}
