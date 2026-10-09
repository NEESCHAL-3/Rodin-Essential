//! Per-app ownership and persistence. Android adapters must acknowledge writes
//! before the UI can describe a profile as active.
//!
//! NEESCHAL's rule: borrow global controls, never steal their saved preferences.
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

const SCHEMA: u64 = 1;
const MAX_CONFIG_BYTES: u64 = 512 * 1024;
const MAX_PROFILES: usize = 512;
const O_NOFOLLOW: i32 = 0x20000;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct App {
    pub user: u32,
    pub package: String,
}

impl App {
    pub fn new(user: u32, package: &str) -> Result<Self, String> {
        if user > 100_000 || package.is_empty() || package.len() > 255 {
            return Err("invalid Android app identity".into());
        }
        if !package.split('.').all(|part| {
            !part.is_empty()
                && part
                    .bytes()
                    .next()
                    .is_some_and(|c| c.is_ascii_alphabetic() || c == b'_')
                && part.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
        }) {
            return Err("invalid Android package name".into());
        }
        Ok(Self {
            user,
            package: package.to_owned(),
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum Control {
    Touch,
    Refresh,
    Gpu,
    CpuRange(u8),
    CpuGovernor(u8),
    CpuCores,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Target {
    Touch(u8),
    /// Zero means OEM adaptive, not a manufactured fixed refresh rate.
    Refresh(u16),
    Gpu(u8),
    CpuRange {
        min: u32,
        max: u32,
    },
    CpuGovernor(String),
    CpuCores(u8),
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct Profile {
    pub enabled: bool,
    pub controls: BTreeMap<Control, Target>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct Config {
    pub enabled: bool,
    pub notify: bool,
    pub profiles: BTreeMap<App, Profile>,
}

/// Only detected hardware is accepted. Frequency tables are never guessed.
#[derive(Clone, Debug, Default)]
pub(super) struct Capabilities {
    pub touch: BTreeSet<u8>,
    pub refresh: BTreeSet<u16>,
    pub gpu: BTreeSet<u8>,
    pub cpu_frequencies: BTreeMap<u8, BTreeSet<u32>>,
    pub cpu_governors: BTreeMap<u8, BTreeSet<String>>,
    pub manual_cores: bool,
}

impl Capabilities {
    pub fn validate(&self, profile: &Profile) -> Result<(), String> {
        for (control, target) in &profile.controls {
            let supported = match (control, target) {
                (Control::Touch, Target::Touch(value)) => self.touch.contains(value),
                (Control::Refresh, Target::Refresh(value)) => self.refresh.contains(value),
                (Control::Gpu, Target::Gpu(value)) => self.gpu.contains(value),
                (Control::CpuRange(policy), Target::CpuRange { min, max }) => {
                    min <= max
                        && self
                            .cpu_frequencies
                            .get(policy)
                            .is_some_and(|table| table.contains(min) && table.contains(max))
                }
                (Control::CpuGovernor(policy), Target::CpuGovernor(value)) => self
                    .cpu_governors
                    .get(policy)
                    .is_some_and(|table| table.contains(value)),
                (Control::CpuCores, Target::CpuCores(mask)) => self.manual_cores && mask & 1 != 0,
                _ => false,
            };
            if !supported {
                return Err(format!("unsupported per-app control: {control:?}"));
            }
        }
        Ok(())
    }
}

fn fields(value: &Value, allowed: &[&str]) -> Result<(), String> {
    let object = value.as_object().ok_or("expected JSON object")?;
    if let Some(key) = object.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(format!("unknown per-app field: {key}"));
    }
    Ok(())
}

fn boolean(value: &Value, key: &str) -> Result<bool, String> {
    value.get(key).map_or(Ok(false), |v| {
        v.as_bool().ok_or_else(|| format!("invalid {key}"))
    })
}

fn integer(value: &Value, key: &str, max: u64) -> Result<u64, String> {
    value[key]
        .as_u64()
        .filter(|v| *v <= max)
        .ok_or_else(|| format!("invalid {key}"))
}

impl Profile {
    pub fn parse(value: &Value) -> Result<Self, String> {
        fields(
            value,
            &["enabled", "touch", "refresh", "gpu", "cpu", "cores"],
        )?;
        let mut profile = Self {
            enabled: boolean(value, "enabled")?,
            ..Self::default()
        };
        for (key, max) in [("touch", 3), ("gpu", 3), ("cores", 255), ("refresh", 120)] {
            if value.get(key).is_none_or(Value::is_null) {
                continue;
            }
            let number = integer(value, key, max)?;
            let (control, target) = match key {
                "touch" => (Control::Touch, Target::Touch(number as u8)),
                "gpu" => (Control::Gpu, Target::Gpu(number as u8)),
                "cores" if number & 1 != 0 => (Control::CpuCores, Target::CpuCores(number as u8)),
                "refresh" if matches!(number, 0 | 60 | 90 | 120) => {
                    (Control::Refresh, Target::Refresh(number as u16))
                }
                _ => return Err(format!("invalid {key}")),
            };
            profile.controls.insert(control, target);
        }
        if let Some(cpu) = value.get("cpu").filter(|v| !v.is_null()) {
            fields(cpu, &["0", "4", "7"])?;
            for policy in [0u8, 4, 7] {
                let key = policy.to_string();
                let Some(cluster) = cpu.get(&key) else {
                    continue;
                };
                fields(cluster, &["range", "governor"])?;
                if let Some(range) = cluster.get("range").filter(|v| !v.is_null()) {
                    let values = range
                        .as_array()
                        .ok_or("CPU range must contain minimum and maximum")?;
                    if values.len() != 2 {
                        return Err("CPU range must contain two values".into());
                    }
                    let min = values[0]
                        .as_u64()
                        .filter(|v| *v > 0 && *v <= 10_000)
                        .ok_or("invalid CPU minimum")?;
                    let max = values[1]
                        .as_u64()
                        .filter(|v| *v >= min && *v <= 10_000)
                        .ok_or("invalid CPU maximum")?;
                    profile.controls.insert(
                        Control::CpuRange(policy),
                        Target::CpuRange {
                            min: min as u32,
                            max: max as u32,
                        },
                    );
                }
                if let Some(governor) = cluster.get("governor").filter(|v| !v.is_null()) {
                    let governor = governor
                        .as_str()
                        .filter(|v| {
                            !v.is_empty()
                                && v.len() <= 64
                                && v.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
                        })
                        .ok_or("invalid CPU governor")?;
                    profile.controls.insert(
                        Control::CpuGovernor(policy),
                        Target::CpuGovernor(governor.to_owned()),
                    );
                }
            }
        }
        Ok(profile)
    }

    pub fn json(&self) -> Value {
        let mut value = json!({"enabled": self.enabled});
        for (control, target) in &self.controls {
            match (control, target) {
                (Control::Touch, Target::Touch(v)) => value["touch"] = json!(v),
                (Control::Refresh, Target::Refresh(v)) => value["refresh"] = json!(v),
                (Control::Gpu, Target::Gpu(v)) => value["gpu"] = json!(v),
                (Control::CpuCores, Target::CpuCores(v)) => value["cores"] = json!(v),
                (Control::CpuRange(policy), Target::CpuRange { min, max }) => {
                    let key = policy.to_string();
                    if value.get("cpu").is_none() {
                        value["cpu"] = json!({});
                    }
                    if value["cpu"].get(&key).is_none() {
                        value["cpu"][&key] = json!({});
                    }
                    value["cpu"][&key]["range"] = json!([min, max]);
                }
                (Control::CpuGovernor(policy), Target::CpuGovernor(v)) => {
                    let key = policy.to_string();
                    if value.get("cpu").is_none() {
                        value["cpu"] = json!({});
                    }
                    if value["cpu"].get(&key).is_none() {
                        value["cpu"][&key] = json!({});
                    }
                    value["cpu"][&key]["governor"] = json!(v);
                }
                _ => unreachable!("validated control-target pair"),
            }
        }
        value
    }
}

impl Config {
    pub fn parse(raw: &str) -> Result<Self, String> {
        if raw.len() as u64 > MAX_CONFIG_BYTES {
            return Err("per-app configuration too large".into());
        }
        let value: Value = serde_json::from_str(raw).map_err(|e| format!("per-app JSON: {e}"))?;
        fields(&value, &["schema", "enabled", "notify", "profiles"])?;
        if value["schema"].as_u64() != Some(SCHEMA) {
            return Err("unsupported per-app schema".into());
        }
        let profiles = value["profiles"]
            .as_array()
            .ok_or("missing profiles array")?;
        if profiles.len() > MAX_PROFILES {
            return Err("too many app profiles".into());
        }
        let mut config = Self {
            enabled: boolean(&value, "enabled")?,
            notify: boolean(&value, "notify")?,
            ..Self::default()
        };
        for item in profiles {
            fields(item, &["user", "package", "profile"])?;
            let user = integer(item, "user", 100_000)? as u32;
            let app = App::new(user, item["package"].as_str().ok_or("missing package")?)?;
            let profile = Profile::parse(&item["profile"])?;
            if config.profiles.insert(app, profile).is_some() {
                return Err("duplicate app profile".into());
            }
        }
        Ok(config)
    }

    pub fn json(&self) -> Value {
        let profiles: Vec<_> = self.profiles.iter().map(|(app, profile)|
            json!({"user": app.user, "package": app.package, "profile": profile.json()})).collect();
        json!({"schema": SCHEMA, "enabled": self.enabled, "notify": self.notify, "profiles": profiles})
    }

    pub fn load(path: &Path) -> Result<Self, String> {
        let file = match fs::File::open(path) {
            Ok(file) => file,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(e) => return Err(format!("read app profiles: {e}")),
        };
        let mut raw = String::new();
        file.take(MAX_CONFIG_BYTES + 1)
            .read_to_string(&mut raw)
            .map_err(|e| e.to_string())?;
        Self::parse(&raw)
    }

    /// Caller serializes writes with the daemon's transition gate. Malformed
    /// configuration must never replace the last complete durable copy.
    pub fn save(&self, path: &Path) -> Result<(), String> {
        let raw = self.json().to_string();
        Self::parse(&raw)?;
        let dir = path.parent().ok_or("missing profile directory")?;
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("json.tmp");
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .custom_flags(O_NOFOLLOW) // Never follow a substituted temporary symlink.
            .open(&tmp)
            .map_err(|e| e.to_string())?;
        file.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|e| e.to_string())?;
        file.write_all(raw.as_bytes()).map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| e.to_string())?;
        drop(file);
        fs::rename(&tmp, path).map_err(|e| e.to_string())?;
        fs::File::open(dir)
            .and_then(|d| d.sync_all())
            .map_err(|e| e.to_string())
    }
}

/// Android event-log formats vary; accept only a complete resumed component
/// associated with an Android user, never infer packages from activity classes.
#[cfg(any(target_os = "android", test))]
pub(super) fn resumed_app(line: &str) -> Option<App> {
    if !line.contains("wm_set_resumed_activity") && !line.contains("wm_resume_activity") {
        return None;
    }
    let start = line.find('[')?;
    let end = line[start..].find(']')? + start;
    let parts: Vec<_> = line[start + 1..end].split(',').map(str::trim).collect();
    let user: u32 = parts.first()?.parse().ok()?;
    let component = parts.iter().skip(1).find(|part| part.contains('/'))?;
    App::new(user, component.split_once('/')?.0).ok()
}

/// The hardware adapter provides a restorable token, not just a UI label.
/// A successful apply must include supported-node readback/acknowledgment.
pub(super) trait Hardware {
    type Saved: Clone;
    fn capture(&mut self, control: &Control) -> Result<Self::Saved, String>;
    fn apply(&mut self, control: &Control, target: &Target) -> Result<(), String>;
    fn restore(&mut self, control: &Control, saved: &Self::Saved) -> Result<(), String>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum Status {
    Global,
    Active(App),
    /// Retain recovery tokens after failed writes. Never pretend rollback won.
    RecoveryRequired(String),
}

pub(super) struct Ownership<S> {
    baseline: BTreeMap<Control, S>,
    applied: BTreeMap<Control, Target>,
    pub status: Status,
}

impl<S> Default for Ownership<S> {
    fn default() -> Self {
        Self {
            baseline: BTreeMap::new(),
            applied: BTreeMap::new(),
            status: Status::Global,
        }
    }
}

impl<S: Clone> Ownership<S> {
    #[cfg(test)]
    pub fn owns(&self, control: &Control) -> bool {
        self.baseline.contains_key(control)
    }

    /// Serialized by the daemon. Off/profile reset/unprofiled foreground all
    /// select None. Disabled service always wins over any configured profile.
    pub fn transition<H: Hardware<Saved = S>>(
        &mut self,
        hardware: &mut H,
        app: Option<&App>,
        profile: Option<&Profile>,
        service_enabled: bool,
        profiles_enabled: bool,
    ) -> Result<(), String> {
        let desired = if service_enabled && profiles_enabled {
            app.zip(profile)
                .filter(|(_, p)| p.enabled && !p.controls.is_empty())
        } else {
            None
        };
        let targets = desired.map(|(_, p)| p.controls.clone()).unwrap_or_default();
        if !matches!(self.status, Status::RecoveryRequired(_)) && targets == self.applied {
            self.status = desired
                .map(|(app, _)| Status::Active(app.clone()))
                .unwrap_or(Status::Global);
            return Ok(());
        }
        // Read all originals before making any new write. Capture failure is
        // harmless and cannot leave a partially applied profile behind.
        let mut captures = BTreeMap::new();
        for control in targets.keys() {
            if !self.baseline.contains_key(control) {
                let saved = match hardware.capture(control) {
                    Ok(saved) => saved,
                    // A new app must not inherit the old app's override when
                    // one of its own originals cannot be read.
                    Err(error) => return self.rollback(hardware, error),
                };
                captures.insert(control.clone(), saved);
            }
        }
        self.baseline.extend(captures);
        let releasing: Vec<_> = self
            .baseline
            .keys()
            .filter(|c| !targets.contains_key(*c))
            .cloned()
            .collect();
        for control in releasing {
            let saved = &self.baseline[&control];
            if let Err(error) = hardware.restore(&control, saved) {
                return self.rollback(hardware, error);
            }
            self.baseline.remove(&control);
            self.applied.remove(&control);
        }
        for (control, target) in &targets {
            if self.applied.get(control) == Some(target)
                && !matches!(self.status, Status::RecoveryRequired(_))
            {
                continue;
            }
            if let Err(error) = hardware.apply(control, target) {
                return self.rollback(hardware, error);
            }
            self.applied.insert(control.clone(), target.clone());
        }
        self.status = desired
            .map(|(app, _)| Status::Active(app.clone()))
            .unwrap_or(Status::Global);
        Ok(())
    }

    fn rollback<H: Hardware<Saved = S>>(
        &mut self,
        hardware: &mut H,
        cause: String,
    ) -> Result<(), String> {
        let controls: Vec<_> = self.baseline.keys().cloned().collect();
        let mut errors = Vec::new();
        for control in controls {
            match hardware.restore(&control, &self.baseline[&control]) {
                Ok(()) => {
                    self.baseline.remove(&control);
                    self.applied.remove(&control);
                }
                Err(error) => errors.push(format!("{control:?}: {error}")),
            }
        }
        if errors.is_empty() {
            self.status = Status::Global;
        } else {
            self.status = Status::RecoveryRequired(errors.join("; "));
        }
        Err(match &self.status {
            Status::RecoveryRequired(error) => format!("{cause}; restore pending: {error}"),
            _ => cause,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct FakeHardware {
        values: BTreeMap<Control, Target>,
        writes: usize,
        fail_apply: Option<Control>,
        fail_restore: Option<Control>,
        fail_capture: Option<Control>,
    }
    impl Hardware for FakeHardware {
        type Saved = Target;
        fn capture(&mut self, c: &Control) -> Result<Target, String> {
            if self.fail_capture.as_ref() == Some(c) {
                return Err("capture rejected".into());
            }
            self.values.get(c).cloned().ok_or("no original".into())
        }
        fn apply(&mut self, c: &Control, t: &Target) -> Result<(), String> {
            self.writes += 1;
            // A write can partially take effect before its readback fails.
            self.values.insert(c.clone(), t.clone());
            if self.fail_apply.as_ref() == Some(c) {
                return Err("readback rejected".into());
            }
            Ok(())
        }
        fn restore(&mut self, c: &Control, s: &Target) -> Result<(), String> {
            self.writes += 1;
            if self.fail_restore.as_ref() == Some(c) {
                return Err("restore rejected".into());
            }
            self.values.insert(c.clone(), s.clone());
            Ok(())
        }
    }
    fn app() -> App {
        App::new(0, "com.example.game").unwrap()
    }
    fn profile() -> Profile {
        Profile::parse(&json!({"enabled":true,"touch":2,"gpu":1})).unwrap()
    }
    fn hardware() -> FakeHardware {
        FakeHardware {
            values: BTreeMap::from([
                (Control::Touch, Target::Touch(0)),
                (Control::Gpu, Target::Gpu(3)),
            ]),
            ..Default::default()
        }
    }

    #[test]
    fn absent_fields_follow_global_and_governors_are_independent() {
        let p = Profile::parse(&json!({"enabled":true,"cpu":{"0":{"range":[1000,2100]}}})).unwrap();
        assert_eq!(p.controls.len(), 1);
        assert!(!p.controls.contains_key(&Control::CpuGovernor(0)));
        assert_eq!(Profile::parse(&p.json()).unwrap(), p);
    }
    #[test]
    fn explicit_oem_is_different_from_follow_global() {
        let p = Profile::parse(&json!({"enabled":true,"touch":0,"refresh":0,"gpu":null})).unwrap();
        assert_eq!(p.controls.get(&Control::Touch), Some(&Target::Touch(0)));
        assert!(!p.controls.contains_key(&Control::Gpu));
    }
    #[test]
    fn rejects_untrusted_or_unsupported_configuration() {
        for v in [
            json!({"touch":4}),
            json!({"refresh":100}),
            json!({"cores":0}),
            json!({"enabled":"yes"}),
            json!({"zram":8192}),
            json!({"cpu":{"2":{"range":[1,2]}}}),
            json!({"cpu":{"0":{"range":[2100,1000]}}}),
            json!({"cpu":{"0":{"governor":"schedutil;reboot"}}}),
        ] {
            assert!(Profile::parse(&v).is_err(), "accepted {v}");
        }
        for name in [
            "",
            "com..app",
            "com.app;reboot",
            "../app",
            "1foo.bar",
            "com.app\n",
        ] {
            assert!(App::new(0, name).is_err());
        }
    }
    #[test]
    fn runtime_capabilities_not_marketing_caps() {
        let mut caps = Capabilities::default();
        caps.cpu_frequencies.insert(0, BTreeSet::from([1000, 2100]));
        let p = Profile::parse(&json!({"cpu":{"0":{"range":[1000,2100]}}})).unwrap();
        assert!(caps.validate(&p).is_ok());
        let unavailable = Profile::parse(&json!({"cpu":{"0":{"range":[1000,2000]}}})).unwrap();
        assert!(caps.validate(&unavailable).is_err());
        assert!(
            caps.validate(&Profile::parse(&json!({"refresh":120})).unwrap())
                .is_err()
        );
    }
    #[test]
    fn repeated_foreground_events_do_not_rewrite_hardware() {
        let mut h = hardware();
        let mut owner = Ownership::default();
        for _ in 0..1000 {
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), true, true)
                .unwrap();
        }
        assert_eq!(h.writes, 2);
        assert_eq!(owner.status, Status::Active(app()));
    }
    #[test]
    fn leaving_app_restores_custom_global_beast_not_stock() {
        let mut h = hardware();
        let originals = h.values.clone();
        let mut owner = Ownership::default();
        owner
            .transition(&mut h, Some(&app()), Some(&profile()), true, true)
            .unwrap();
        owner.transition(&mut h, None, None, true, true).unwrap();
        assert_eq!(h.values, originals);
        assert_eq!(owner.status, Status::Global);
    }
    #[test]
    fn different_app_inherits_original_global_not_previous_app() {
        let mut h = hardware();
        let mut owner = Ownership::default();
        owner
            .transition(&mut h, Some(&app()), Some(&profile()), true, true)
            .unwrap();
        let other = App::new(0, "com.example.social").unwrap();
        let p = Profile::parse(&json!({"enabled":true,"touch":1})).unwrap();
        owner
            .transition(&mut h, Some(&other), Some(&p), true, true)
            .unwrap();
        assert_eq!(h.values[&Control::Gpu], Target::Gpu(3));
        assert_eq!(h.values[&Control::Touch], Target::Touch(1));
        owner.transition(&mut h, None, None, true, true).unwrap();
        assert_eq!(h.values[&Control::Touch], Target::Touch(0));
    }
    #[test]
    fn service_disable_and_profile_disable_release_controls() {
        for (service, profiles) in [(false, true), (true, false), (false, false)] {
            let mut h = hardware();
            let initial = h.values.clone();
            let mut owner = Ownership::default();
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), true, true)
                .unwrap();
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), service, profiles)
                .unwrap();
            assert_eq!(h.values, initial);
            assert_eq!(owner.status, Status::Global);
        }
    }
    #[test]
    fn capture_failure_makes_no_writes() {
        let mut h = hardware();
        h.fail_capture = Some(Control::Gpu);
        let mut owner = Ownership::default();
        assert!(
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), true, true)
                .is_err()
        );
        assert_eq!(h.writes, 0);
        assert!(!owner.owns(&Control::Touch));
    }

    #[test]
    fn new_app_capture_failure_releases_previous_app_instead_of_leaking_it() {
        let mut h = hardware();
        let originals = h.values.clone();
        let mut owner = Ownership::default();
        let first = Profile::parse(&json!({"enabled":true,"touch":2})).unwrap();
        owner
            .transition(&mut h, Some(&app()), Some(&first), true, true)
            .unwrap();
        h.fail_capture = Some(Control::Gpu);
        let other = App::new(0, "com.example.social").unwrap();
        assert!(
            owner
                .transition(&mut h, Some(&other), Some(&profile()), true, true)
                .is_err()
        );
        assert_eq!(h.values, originals);
        assert_eq!(owner.status, Status::Global);
    }
    #[test]
    fn failed_apply_rolls_back_including_partially_written_control() {
        let mut h = hardware();
        let original = h.values.clone();
        h.fail_apply = Some(Control::Gpu);
        let mut owner = Ownership::default();
        assert!(
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), true, true)
                .is_err()
        );
        assert_eq!(h.values, original);
        assert_eq!(owner.status, Status::Global);
    }
    #[test]
    fn failed_restore_retains_owner_and_recovers_without_false_active() {
        let mut h = hardware();
        h.fail_apply = Some(Control::Gpu);
        h.fail_restore = Some(Control::Gpu);
        let mut owner = Ownership::default();
        assert!(
            owner
                .transition(&mut h, Some(&app()), Some(&profile()), true, true)
                .is_err()
        );
        assert!(matches!(owner.status, Status::RecoveryRequired(_)));
        assert!(owner.owns(&Control::Gpu));
        h.fail_restore = None;
        h.fail_apply = None;
        owner.transition(&mut h, None, None, true, true).unwrap();
        assert_eq!(h.values[&Control::Gpu], Target::Gpu(3));
        assert_eq!(owner.status, Status::Global);
    }
    #[test]
    fn config_round_trip_duplicates_and_version_guard() {
        let mut config = Config::default();
        config.profiles.insert(app(), profile());
        assert_eq!(Config::parse(&config.json().to_string()).unwrap(), config);
        let mut v = config.json();
        v["schema"] = json!(99);
        assert!(Config::parse(&v.to_string()).is_err());
        let mut v = config.json();
        let duplicate = v["profiles"][0].clone();
        v["profiles"].as_array_mut().unwrap().push(duplicate);
        assert!(Config::parse(&v.to_string()).is_err());
    }
    #[test]
    fn multi_user_profiles_never_share_an_owner() {
        let mut config = Config::default();
        config.profiles.insert(app(), profile());
        assert!(
            !config
                .profiles
                .contains_key(&App::new(10, "com.example.game").unwrap())
        );
    }
    #[test]
    fn empty_or_disabled_profile_is_global_not_false_active() {
        let mut h = hardware();
        let mut owner = Ownership::default();
        for p in [
            Profile::parse(&json!({"enabled":true})).unwrap(),
            Profile::parse(&json!({"enabled":false,"gpu":1})).unwrap(),
        ] {
            owner
                .transition(&mut h, Some(&app()), Some(&p), true, true)
                .unwrap();
            assert_eq!(owner.status, Status::Global);
        }
        assert_eq!(h.writes, 0);
    }
    #[test]
    fn resetting_current_profile_releases_all_borrowed_controls() {
        let mut config = Config::default();
        config.enabled = true;
        config.profiles.insert(app(), profile());
        let mut h = hardware();
        let original = h.values.clone();
        let mut owner = Ownership::default();
        owner
            .transition(
                &mut h,
                Some(&app()),
                config.profiles.get(&app()),
                true,
                config.enabled,
            )
            .unwrap();
        config.profiles.remove(&app());
        owner
            .transition(
                &mut h,
                Some(&app()),
                config.profiles.get(&app()),
                true,
                config.enabled,
            )
            .unwrap();
        assert_eq!(h.values, original);
        assert_eq!(owner.status, Status::Global);
    }
    #[test]
    fn identical_profiles_change_owner_without_redundant_writes() {
        let mut h = hardware();
        let mut owner = Ownership::default();
        owner
            .transition(&mut h, Some(&app()), Some(&profile()), true, true)
            .unwrap();
        let other = App::new(10, "com.example.game").unwrap();
        owner
            .transition(&mut h, Some(&other), Some(&profile()), true, true)
            .unwrap();
        assert_eq!(owner.status, Status::Active(other));
        assert_eq!(h.writes, 2);
    }
    #[test]
    fn corruption_is_reported_not_silently_enabled() {
        assert!(Config::parse("broken").is_err());
        assert!(Config::parse(r#"{"schema":1,"enabled":true,"profiles":{}}"#).is_err());
        assert!(Config::parse(&" ".repeat(MAX_CONFIG_BYTES as usize + 1)).is_err());
    }
    #[test]
    fn resumed_events_support_vendor_formats_but_not_class_only_records() {
        assert_eq!(
            resumed_app(
                "I/wm_set_resumed_activity: [0,com.miui.home/.launcher.Launcher,resumeTopActivity]"
            ),
            Some(App::new(0, "com.miui.home").unwrap())
        );
        assert_eq!(
            resumed_app(
                "I/wm_resume_activity: [10,203208245,1072,tw.nekomimi.nekogram/org.telegram.messenger.MusheenIcon]"
            ),
            Some(App::new(10, "tw.nekomimi.nekogram").unwrap())
        );
        assert_eq!(
            resumed_app(
                "I/wm_on_resume_called: [0,203208245,org.telegram.messenger.MusheenIcon,RESUME_ACTIVITY,2]"
            ),
            None
        );
        assert_eq!(
            resumed_app("wm_resume_activity: [0,com.app;reboot/.Main]"),
            None
        );
    }
    #[test]
    fn durable_storage_is_private_and_missing_is_disabled() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "rodin-profiles-test-{}-{nonce}",
            std::process::id()
        ));
        let path = dir.join("profiles.json");
        assert_eq!(Config::load(&path).unwrap(), Config::default());
        let mut config = Config::default();
        config.profiles.insert(app(), profile());
        config.save(&path).unwrap();
        assert_eq!(Config::load(&path).unwrap(), config);
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_file(path).unwrap();
        fs::remove_dir(dir).unwrap();
    }
}
