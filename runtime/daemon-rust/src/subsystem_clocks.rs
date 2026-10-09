//! NEESCHAL: a memory/storage request is not a licence to poke raw PLLs.
//! Session locks use supported devfreq bounds, never voltage/force-OPP nodes.
//! No saved maximum is replayed at boot. A write-ahead original is recovered
//! on daemon restart; a kernel hang still requires external recovery.
use super::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeMap;

const TRIAL_SECONDS: u64 = 30;
#[derive(Clone, Copy, Debug, Ord, PartialOrd, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    Memory,
    Storage,
}
impl Kind {
    fn parse(s: &str) -> Result<Self, String> {
        match s {
            "memory" => Ok(Self::Memory),
            "storage" => Ok(Self::Storage),
            _ => Err("unknown subsystem".into()),
        }
    }
    fn root(self) -> PathBuf {
        PathBuf::from(match self {
            Self::Memory => "/sys/class/devfreq/mtk-dvfsrc-devfreq",
            Self::Storage => "/sys/class/devfreq/112b0000.ufshci",
        })
    }
    fn name(self) -> &'static str {
        match self {
            Self::Memory => "mtk-dvfsrc-devfreq",
            Self::Storage => "112b0000.ufshci",
        }
    }
}
#[derive(Default)]
struct Trials {
    originals: BTreeMap<Kind, Original>,
    deadlines: BTreeMap<Kind, Instant>,
    targets: BTreeMap<Kind, (u64, u64)>,
    error: Option<String>,
    journal_invalid: bool,
}
#[derive(Clone, Copy, Serialize, Deserialize)]
#[serde(untagged)]
enum Original {
    Legacy(u64),
    Range { min_hz: u64, max_hz: u64 },
}
static TRIALS: OnceLock<(Mutex<Trials>, Condvar)> = OnceLock::new();
fn trials() -> &'static (Mutex<Trials>, Condvar) {
    TRIALS.get_or_init(|| (Mutex::new(Trials::default()), Condvar::new()))
}
fn number(root: &Path, name: &str) -> Result<u64, String> {
    fs::read_to_string(root.join(name))
        .map_err(|e| format!("{name}: {e}"))?
        .trim()
        .parse()
        .map_err(|_| format!("invalid {name}"))
}
fn table(raw: &str) -> Result<Vec<u64>, String> {
    let mut values = raw
        .split_whitespace()
        .map(|v| {
            v.parse::<u64>()
                .map_err(|_| "invalid frequency table".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    values.sort_unstable();
    values.dedup();
    if values.is_empty()
        || values.len() > 32
        || values.iter().any(|&v| v == 0 || v > 20_000_000_000)
    {
        return Err("unsupported frequency table".into());
    }
    Ok(values)
}
fn inspect(kind: Kind, root: &Path) -> Result<Value, String> {
    let name = fs::read_to_string(root.join("name")).map_err(|e| e.to_string())?;
    if name.trim() != kind.name() {
        return Err("unexpected devfreq device".into());
    }
    let frequencies =
        table(&fs::read_to_string(root.join("available_frequencies")).map_err(|e| e.to_string())?)?;
    let governor = fs::read_to_string(root.join("governor")).map_err(|e| e.to_string())?;
    let min = number(root, "min_freq")?;
    let max = number(root, "max_freq")?;
    let reason = if kind == Kind::Memory && governor.trim() != "userspace" {
        Some("Memory trial requires the OEM userspace governor; no governor will be changed")
    } else {
        None
    };
    Ok(json!({"supported": reason.is_none(), "reason": reason,
        "frequencies_hz": frequencies, "driver_hz": number(root, "cur_freq").ok(),
        "min_hz": min, "max_hz": max, "governor": governor.trim()}))
}
fn journal_path() -> PathBuf {
    state_dir().join("subsystem-clock-originals.json")
}
fn journal(originals: &BTreeMap<Kind, Original>) -> Result<(), String> {
    let path = journal_path();
    fs::create_dir_all(state_dir()).map_err(|e| e.to_string())?;
    let temp = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temp)
        .map_err(|e| e.to_string())?;
    file.write_all(
        serde_json::to_string(originals)
            .map_err(|e| e.to_string())?
            .as_bytes(),
    )
    .map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    fs::rename(&temp, &path).map_err(|e| e.to_string())?;
    fs::File::open(state_dir())
        .and_then(|f| f.sync_all())
        .map_err(|e| e.to_string())
}
fn write_floor(root: &Path, hz: u64) -> Result<(), String> {
    fs::write(root.join("min_freq"), hz.to_string()).map_err(|e| e.to_string())?;
    if number(root, "min_freq")? != hz {
        return Err("driver did not accept the requested floor".into());
    }
    Ok(())
}
fn write_range(root: &Path, min: u64, max: u64) -> Result<(), String> {
    if min > max {
        return Err("invalid frequency range".into());
    }
    // Keep the range valid at each step, including OEM restoration.
    if min > number(root, "max_freq")? {
        fs::write(root.join("max_freq"), max.to_string()).map_err(|e| e.to_string())?;
        write_floor(root, min)?;
    } else {
        write_floor(root, min)?;
        fs::write(root.join("max_freq"), max.to_string()).map_err(|e| e.to_string())?;
    }
    if number(root, "max_freq")? != max || number(root, "min_freq")? != min {
        return Err("driver did not accept the exact frequency range".into());
    }
    Ok(())
}
fn apply_max(kind: Kind, root: &Path) -> Result<u64, String> {
    let status = inspect(kind, root)?;
    if status["supported"] != true {
        return Err(status["reason"].as_str().unwrap_or("unsupported").into());
    }
    let original = status["min_hz"].as_u64().ok_or("missing original floor")?;
    let max = status["frequencies_hz"]
        .as_array()
        .and_then(|a| a.last())
        .and_then(Value::as_u64)
        .ok_or("missing highest supported state")?;
    if max > status["max_hz"].as_u64().ok_or("missing ceiling")? {
        return Err("The existing driver ceiling excludes its highest state".into());
    }
    write_floor(root, max)?;
    Ok(original)
}
#[cfg(test)]
fn apply_level(kind: Kind, root: &Path, hz: u64, ceiling: u64) -> Result<(), String> {
    apply_supported_range(kind, root, hz, hz, ceiling)
}
fn validate_range(kind: Kind, root: &Path, min: u64, max: u64, ceiling: u64) -> Result<(), String> {
    let status = inspect(kind, root)?;
    if kind == Kind::Memory && status["governor"] != "userspace" {
        return Err("The OEM memory governor is not supported".into());
    }
    let levels = status["frequencies_hz"]
        .as_array()
        .ok_or("missing supported states")?;
    if min > max
        || ![min, max]
            .iter()
            .all(|hz| levels.iter().any(|v| v.as_u64() == Some(*hz)))
    {
        return Err("Choose a frequency advertised by this driver".into());
    }
    if max > ceiling {
        return Err("This frequency exceeds the existing driver ceiling".into());
    }
    Ok(())
}
fn apply_supported_range(
    kind: Kind,
    root: &Path,
    min: u64,
    max: u64,
    ceiling: u64,
) -> Result<(), String> {
    validate_range(kind, root, min, max, ceiling)?;
    write_range(root, min, max)
}
fn restore_one(state: &mut Trials, kind: Kind) -> Result<(), String> {
    if let Some(&original) = state.originals.get(&kind) {
        let hz = match original {
            Original::Legacy(hz) => hz,
            Original::Range { min_hz, .. } => min_hz,
        };
        let root = kind.root();
        // Never write a stale journal into a different driver or table.
        let status = inspect(kind, &root)?;
        let values = status["frequencies_hz"].as_array().unwrap();
        let low = values
            .first()
            .and_then(Value::as_u64)
            .ok_or("missing lower state")?;
        let high = values
            .last()
            .and_then(Value::as_u64)
            .ok_or("missing upper state")?;
        // A ROM's floor request may sit between OPPs; retain that exact request.
        if hz != 0 && !(low..=high).contains(&hz) {
            return Err("original floor is outside the supported request range".into());
        }
        match original {
            Original::Legacy(_) => write_floor(&root, hz)?,
            Original::Range { min_hz, max_hz } => {
                if max_hz != 0 && !(low..=high).contains(&max_hz) {
                    return Err("original ceiling is outside the supported range".into());
                }
                write_range(&root, min_hz, max_hz)?;
            }
        }
        let mut remaining = state.originals.clone();
        remaining.remove(&kind);
        journal(&remaining)?;
        state.originals = remaining;
        state.deadlines.remove(&kind);
        state.targets.remove(&kind);
    }
    Ok(())
}
pub(super) fn restore_all() -> Result<(), String> {
    let mut state = trials().0.lock().map_err(|_| "clock trial lock poisoned")?;
    if state.journal_invalid {
        return Err("clock recovery journal is invalid; no hardware writes permitted".into());
    }
    for kind in [Kind::Memory, Kind::Storage] {
        restore_one(&mut state, kind)?;
    }
    state.error = None;
    trials().1.notify_one();
    Ok(())
}
pub(super) fn start() {
    let loaded = match fs::read(journal_path()) {
        Ok(bytes) => {
            serde_json::from_slice::<BTreeMap<Kind, Original>>(&bytes).map_err(|e| e.to_string())
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(BTreeMap::new()),
        Err(e) => Err(e.to_string()),
    };
    {
        let mut state = trials().0.lock().unwrap();
        match loaded {
            Ok(originals) => state.originals = originals,
            Err(e) => {
                state.error = Some(e);
                state.journal_invalid = true;
            }
        }
    }
    if trials().0.lock().unwrap().error.is_none() {
        if let Err(e) = restore_all() {
            trials().0.lock().unwrap().error = Some(e);
        }
    }
    std::thread::spawn(|| {
        let (lock, wake) = trials();
        let mut state = lock.lock().unwrap();
        loop {
            let expired: Vec<_> = state
                .deadlines
                .iter()
                .filter(|(_, deadline)| **deadline <= Instant::now())
                .map(|(&kind, _)| kind)
                .collect();
            for kind in expired {
                if let Err(e) = restore_one(&mut state, kind) {
                    state.error = Some(e);
                    // No sysfs fighting/retry loop. Preserve journal for explicit recovery.
                    state.deadlines.remove(&kind);
                }
            }
            let wait = state
                .deadlines
                .values()
                .min()
                .map(|d| d.saturating_duration_since(Instant::now()));
            state = match wait {
                Some(wait) => wake.wait_timeout(state, wait).unwrap().0,
                None => wake.wait(state).unwrap(),
            };
        }
    });
}
pub(super) fn is_command(cmd: &str) -> bool {
    cmd == "GET subsystem.clocks"
        || cmd == "ACTION subsystem.clocks.reset"
        || cmd.starts_with("ACTION subsystem.clocks.trial ")
        || cmd.starts_with("ACTION subsystem.clocks.level ")
        || cmd.starts_with("ACTION subsystem.clocks.range ")
        || cmd.starts_with("ACTION subsystem.clocks.oem ")
}
pub(super) fn command(cmd: &str) -> Result<Value, String> {
    if cmd == "ACTION subsystem.clocks.reset" {
        restore_all()?;
    }
    if let Some(arg) = cmd.strip_prefix("ACTION subsystem.clocks.oem ") {
        let kind = Kind::parse(arg)?;
        let mut state = trials()
            .0
            .lock()
            .map_err(|_| "clock control lock poisoned")?;
        if state.journal_invalid {
            return Err("invalid recovery journal".into());
        }
        restore_one(&mut state, kind)?;
        state.error = None;
        trials().1.notify_one();
    }
    if let Some((arg, range)) = cmd
        .strip_prefix("ACTION subsystem.clocks.level ")
        .map(|a| (a, false))
        .or_else(|| {
            cmd.strip_prefix("ACTION subsystem.clocks.range ")
                .map(|a| (a, true))
        })
    {
        if !service_control::enabled() {
            return Err("Rodin Essential is disabled".into());
        }
        let parts: Vec<_> = arg.split_whitespace().collect();
        if parts.len() != if range { 3 } else { 2 } {
            return Err("expected subsystem and supported frequency bounds".into());
        }
        let kind = Kind::parse(parts[0])?;
        let hz = parts[1].parse::<u64>().map_err(|_| "invalid frequency")?;
        let max = if range {
            parts[2]
                .parse::<u64>()
                .map_err(|_| "invalid upper frequency")?
        } else {
            hz
        };
        let root = kind.root();
        let mut state = trials()
            .0
            .lock()
            .map_err(|_| "clock control lock poisoned")?;
        if state.journal_invalid || state.error.is_some() {
            return Err("restore previous controls first".into());
        }
        let ceiling = match state.originals.get(&kind) {
            Some(Original::Range { max_hz, .. }) => *max_hz,
            _ => number(&root, "max_freq")?,
        };
        // Reject malformed requests before altering the journal or active policy.
        validate_range(kind, &root, hz, max, ceiling)?;
        if !state.originals.contains_key(&kind) {
            let min_hz = number(&root, "min_freq")?;
            let max_hz = number(&root, "max_freq")?;
            state
                .originals
                .insert(kind, Original::Range { min_hz, max_hz });
            if let Err(e) = journal(&state.originals) {
                state.originals.remove(&kind);
                return Err(e);
            }
        }
        if let Err(e) = apply_supported_range(kind, &root, hz, max, ceiling) {
            if let Err(restore) = restore_one(&mut state, kind) {
                state.error = Some(restore);
            }
            return Err(e);
        }
        state.deadlines.remove(&kind);
        state.targets.insert(kind, (hz, max));
        trials().1.notify_one();
    }
    if let Some(arg) = cmd.strip_prefix("ACTION subsystem.clocks.trial ") {
        if !service_control::enabled() {
            return Err("Rodin Essential is disabled".into());
        }
        let kind = Kind::parse(arg)?;
        let root = kind.root();
        let mut state = trials().0.lock().map_err(|_| "clock trial lock poisoned")?;
        if state.error.is_some() {
            return Err("restore the previous trial before starting another".into());
        }
        let status = inspect(kind, &root)?;
        if status["supported"] != true {
            return Err(status["reason"].as_str().unwrap_or("unsupported").into());
        }
        if state.originals.contains_key(&kind) {
            return Err("trial already running".into());
        }
        let min_hz = number(&root, "min_freq")?;
        let max_hz = number(&root, "max_freq")?;
        state
            .originals
            .insert(kind, Original::Range { min_hz, max_hz });
        if let Err(e) = journal(&state.originals) {
            state.originals.remove(&kind);
            return Err(e);
        }
        if let Err(e) = apply_max(kind, &root) {
            if let Err(restore) = restore_one(&mut state, kind) {
                state.error = Some(restore);
            }
            return Err(e);
        }
        state
            .deadlines
            .insert(kind, Instant::now() + Duration::from_secs(TRIAL_SECONDS));
        trials().1.notify_one();
    }
    let state = trials().0.lock().map_err(|_| "clock trial lock poisoned")?;
    let mut result =
        json!({"trial_seconds": TRIAL_SECONDS, "error": state.error, "boot_persistent": false});
    for (kind, key) in [(Kind::Memory, "memory"), (Kind::Storage, "storage")] {
        let mut item = inspect(kind, &kind.root())
            .unwrap_or_else(|e| json!({"supported": false, "reason": e}));
        item["remaining_seconds"] = json!(
            state
                .deadlines
                .get(&kind)
                .map(|d| d.saturating_duration_since(Instant::now()).as_secs() + 1)
                .unwrap_or(0)
        );
        item["restore_pending"] = json!(state.originals.contains_key(&kind));
        item["controlled"] =
            json!(state.originals.contains_key(&kind) && !state.deadlines.contains_key(&kind));
        if let Some(&(min, max)) = state.targets.get(&kind) {
            item["target_min_hz"] = json!(min);
            item["target_max_hz"] = json!(max);
            item["verified"] =
                json!(item["min_hz"].as_u64() == Some(min) && item["max_hz"].as_u64() == Some(max));
        }
        // A custom cap must not disable moving the slider back up within the
        // original ROM ceiling. The daemon still validates every request.
        if let Some(Original::Range { max_hz, .. }) = state.originals.get(&kind) {
            item["oem_max_hz"] = json!(max_hz);
        }
        result[key] = item;
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_and_normalizes_tables() {
        assert_eq!(
            table("499200000 273000000 499200000").unwrap(),
            vec![273000000, 499200000]
        );
        for bad in ["", "0", "-1", "90000000000", "273 nope"] {
            assert!(table(bad).is_err());
        }
    }
    #[test]
    fn rejects_unrecognized_targets() {
        assert!(Kind::parse("../voltage").is_err());
        assert!(!is_command("SET subsystem.voltage 9"));
    }
    #[test]
    fn supported_locks_restore_both_bounds_and_preserve_other_nodes() {
        let root = std::env::temp_dir().join(format!("rodin-clock-test-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        for (name, value) in [
            ("name", "112b0000.ufshci"),
            ("available_frequencies", "273000000 499200000"),
            ("governor", "simple_ondemand"),
            ("min_freq", "273000000"),
            ("max_freq", "499200000"),
            ("cur_freq", "273000000"),
        ] {
            fs::write(root.join(name), value).unwrap();
        }
        assert_eq!(apply_max(Kind::Storage, &root).unwrap(), 273000000);
        assert_eq!(number(&root, "min_freq").unwrap(), 499200000);
        assert_eq!(number(&root, "max_freq").unwrap(), 499200000);
        assert_eq!(
            fs::read_to_string(root.join("governor")).unwrap(),
            "simple_ondemand"
        );
        write_floor(&root, 273000000).unwrap();
        apply_level(Kind::Storage, &root, 273000000, 499200000).unwrap();
        assert_eq!(number(&root, "max_freq").unwrap(), 273000000);
        apply_level(Kind::Storage, &root, 499200000, 499200000).unwrap();
        assert_eq!(number(&root, "min_freq").unwrap(), 499200000);
        assert_eq!(number(&root, "max_freq").unwrap(), 499200000);
        assert!(apply_level(Kind::Storage, &root, 400000000, 499200000).is_err());
        assert!(
            apply_supported_range(Kind::Storage, &root, 499200000, 273000000, 499200000).is_err()
        );
        apply_supported_range(Kind::Storage, &root, 273000000, 499200000, 499200000).unwrap();
        write_range(&root, 273000000, 499200000).unwrap();
        assert_eq!(number(&root, "min_freq").unwrap(), 273000000);
        assert_eq!(number(&root, "max_freq").unwrap(), 499200000);
        assert!(apply_level(Kind::Storage, &root, 499200000, 273000000).is_err());
        fs::write(root.join("max_freq"), "273000000").unwrap();
        assert!(apply_max(Kind::Storage, &root).is_err());
        assert_eq!(number(&root, "min_freq").unwrap(), 273000000);
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn recovery_accepts_legacy_and_exact_range_records() {
        let legacy =
            serde_json::from_str::<BTreeMap<Kind, Original>>(r#"{"memory":757000000}"#).unwrap();
        assert!(matches!(legacy[&Kind::Memory], Original::Legacy(757000000)));
        let range = serde_json::from_str::<BTreeMap<Kind, Original>>(
            r#"{"storage":{"min_hz":273000000,"max_hz":499200000}}"#,
        )
        .unwrap();
        assert!(matches!(
            range[&Kind::Storage],
            Original::Range {
                min_hz: 273000000,
                max_hz: 499200000
            }
        ));
    }
}
