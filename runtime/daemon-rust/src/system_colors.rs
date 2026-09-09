//! Android's native Material You palette, not display-panel calibration.
//! No fabricated overlays, APK permissions, boot hooks, or reapply timers.

use serde_json::{Map, Value};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const SETTING: &str = "theme_customization_overlay_packages";
const PALETTE: &str = "android.theme.customization.system_palette";
const ACCENT: &str = "android.theme.customization.accent_color";
const SOURCE: &str = "android.theme.customization.color_source";
const STYLE: &str = "android.theme.customization.theme_style";
const TIMESTAMP: &str = "_applied_timestamp";
const CONTRAST: &str = "contrast_level";
const COLOR_KEYS: [&str; 8] = [
    PALETTE,
    ACCENT,
    SOURCE,
    STYLE,
    "android.theme.customization.dynamic_color",
    "android.theme.customization.color_index",
    "android.theme.customization.color_both",
    TIMESTAMP,
];
const STYLES: [&str; 7] = [
    "TONAL_SPOT",
    "VIBRANT",
    "EXPRESSIVE",
    "SPRITZ",
    "RAINBOW",
    "FRUIT_SALAD",
    "MONOCHROMATIC",
];
const RESOURCES: [&str; 5] = [
    "android:color/system_accent1_500",
    "android:color/system_accent2_500",
    "android:color/system_accent3_500",
    "android:color/system_neutral1_500",
    "android:color/system_neutral2_500",
];
const CONTRAST_RESOURCES: [&str; 4] = [
    "android:color/system_primary_container_light",
    "android:color/system_on_primary_container_light",
    "android:color/system_primary_container_dark",
    "android:color/system_on_primary_container_dark",
];
static TRANSACTION: Mutex<()> = Mutex::new(());

#[derive(Clone, Copy, Debug)]
struct Environment {
    user: i32,
    sdk: i32,
    supported: bool,
}

#[derive(Clone, Copy)]
enum Selection {
    Wallpaper,
    Custom { seed: u32, style: usize },
}

#[derive(Debug)]
struct PaletteState {
    environment: Environment,
    mode: i32,
    seed: i32,
    style: i32,
    colors: [u32; 5],
    // 0: read/already selected; 1: resources changed;
    // 2: wallpaper following restored with the same resolved colors.
    outcome: i32,
}

#[derive(Debug)]
struct ContrastState {
    supported: bool,
    level: i32,
    colors: [u32; 4],
}

impl ContrastState {
    fn encode(&self) -> String {
        format!(
            "supported={};level={};light_container={};light_on_container={};dark_container={};dark_on_container={}",
            i32::from(self.supported),
            self.level,
            self.colors[0],
            self.colors[1],
            self.colors[2],
            self.colors[3],
        )
    }
}

impl PaletteState {
    fn encode(&self) -> String {
        format!(
            "supported={};mode={};seed={};style={};primary={};secondary={};tertiary={};neutral={};neutral_variant={};sdk={};user={};outcome={}",
            i32::from(self.environment.supported),
            self.mode,
            self.seed,
            self.style,
            self.colors[0],
            self.colors[1],
            self.colors[2],
            self.colors[3],
            self.colors[4],
            self.environment.sdk,
            self.environment.user,
            self.outcome,
        )
    }
}

trait PaletteIo {
    fn environment(&self) -> Environment;
    fn read_setting(&mut self) -> Result<Option<String>, String>;
    fn write_setting(&mut self, value: &str) -> Result<(), String>;
    fn colors(&mut self) -> Result<[u32; 5], String>;
    fn pause(&mut self, duration: Duration) {
        std::thread::sleep(duration);
    }
}

struct AndroidPaletteIo {
    environment: Environment,
}

fn command(args: &[&str]) -> Result<String, String> {
    let output =
        super::run_process_with_timeout("/system/bin/cmd", args, Duration::from_millis(1500))
            .map_err(
                |_| "palette_service_unavailable: Android command timed out or could not start",
            )?;
    if !output.status.success() {
        return Err("palette_service_unavailable: Android denied the palette command".into());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

impl AndroidPaletteIo {
    fn open() -> Result<Self, String> {
        let user = command(&["activity", "get-current-user"])?
            .parse::<i32>()
            .ok()
            .filter(|user| *user >= 0)
            .ok_or("palette_service_unavailable: cannot resolve the foreground Android user")?;
        let output = super::run_process_with_timeout(
            "/system/bin/getprop",
            &["ro.build.version.sdk"],
            Duration::from_millis(500),
        )
        .map_err(|_| "palette_service_unavailable: cannot read the Android version")?;
        let sdk = String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse::<i32>()
            .map_err(|_| "palette_service_unavailable: invalid Android version")?;
        if sdk < 31 {
            return Err("palette_unsupported: Android 12 or newer is required".into());
        }
        Ok(Self {
            environment: Environment {
                user,
                sdk,
                // Overlay identifiers belong to the ROM's SystemUI
                // implementation. AOSP commonly uses :accent/:neutral while
                // derivatives are free to use different names. The portable
                // capability check is the framework palette resource read in
                // `colors()`, followed by verified setting/resource readback.
                supported: true,
            },
        })
    }
}

impl PaletteIo for AndroidPaletteIo {
    fn environment(&self) -> Environment {
        self.environment
    }

    fn read_setting(&mut self) -> Result<Option<String>, String> {
        let value = command(&[
            "settings",
            "--user",
            &self.environment.user.to_string(),
            "get",
            "secure",
            SETTING,
        ])?;
        Ok((value != "null").then_some(value))
    }

    fn write_setting(&mut self, value: &str) -> Result<(), String> {
        let user = self.environment.user.to_string();
        let args = ["settings", "--user", &user, "put", "secure", SETTING, value];
        // Direct argv: JSON is never interpreted by a shell.
        command(&args).map(|_| ())
    }

    fn colors(&mut self) -> Result<[u32; 5], String> {
        let user = self.environment.user.to_string();
        read_color_families(|resource| {
            let raw = command(&["overlay", "lookup", "--user", &user, "android", resource])?;
            parse_lookup_rgb(&raw).ok_or_else(|| {
                "palette_unsupported: native palette resources are unavailable".into()
            })
        })
    }
}

fn read_color_families(
    read: impl Fn(&str) -> Result<u32, String> + Sync,
) -> Result<[u32; 5], String> {
    // Each lookup is an independent, read-only Binder command. Run the five
    // families together instead of paying five sequential process round trips
    // per sample. The transaction still requires two matching complete samples
    // before accepting a palette; a partially changing overlay is not success.
    std::thread::scope(|scope| {
        let mut workers = Vec::with_capacity(RESOURCES.len());
        for resource in RESOURCES {
            let read = &read;
            workers.push(
                std::thread::Builder::new()
                    .name("palette-read".into())
                    .spawn_scoped(scope, move || read(resource))
                    .map_err(|_| "palette_service_unavailable: cannot start color read")?,
            );
        }
        let mut result = [0; 5];
        for (index, worker) in workers.into_iter().enumerate() {
            result[index] = worker
                .join()
                .map_err(|_| "palette_service_unavailable: color read failed")??;
        }
        Ok(result)
    })
}

fn read_resources<const N: usize>(
    resources: [&str; N],
    read: impl Fn(&str) -> Result<u32, String> + Sync,
) -> Result<[u32; N], String> {
    std::thread::scope(|scope| {
        let mut workers = Vec::with_capacity(N);
        for resource in resources {
            let read = &read;
            workers.push(
                std::thread::Builder::new()
                    .name("palette-role-read".into())
                    .spawn_scoped(scope, move || read(resource))
                    .map_err(|_| "palette_service_unavailable: cannot start role read")?,
            );
        }
        let mut result = [0; N];
        for (index, worker) in workers.into_iter().enumerate() {
            result[index] = worker
                .join()
                .map_err(|_| "palette_service_unavailable: role read failed")??;
        }
        Ok(result)
    })
}

fn read_contrast_raw(environment: Environment) -> Result<Option<String>, String> {
    let value = command(&[
        "settings",
        "--user",
        &environment.user.to_string(),
        "get",
        "secure",
        CONTRAST,
    ])?;
    Ok((value != "null").then_some(value))
}

fn parse_contrast(raw: Option<&str>) -> Result<i32, String> {
    let value = match raw {
        None => 0.0,
        Some(raw) => raw
            .parse::<f64>()
            .map_err(|_| "palette_invalid_settings: invalid contrast level")?,
    };
    if !value.is_finite() || !(-1.0..=1.0).contains(&value) {
        return Err("palette_invalid_settings: contrast level is outside Android's range".into());
    }
    Ok((value * 1000.0).round() as i32)
}

fn read_contrast_roles(environment: Environment) -> Result<[u32; 4], String> {
    let user = environment.user.to_string();
    read_resources(CONTRAST_RESOURCES, |resource| {
        let raw = command(&["overlay", "lookup", "--user", &user, "android", resource])
            .map_err(|_| "palette_unsupported: native contrast resources are unavailable")?;
        parse_lookup_rgb(&raw)
            .ok_or_else(|| "palette_unsupported: native contrast resources are unavailable".into())
    })
}

fn describe_contrast(environment: Environment) -> Result<ContrastState, String> {
    if environment.sdk < 34 {
        return Ok(ContrastState {
            supported: false,
            level: 0,
            colors: [0; 4],
        });
    }
    let level = parse_contrast(read_contrast_raw(environment)?.as_deref())?;
    match read_contrast_roles(environment) {
        Ok(colors) => Ok(ContrastState {
            supported: true,
            level,
            colors,
        }),
        Err(error) if error.contains("palette_unsupported") => Ok(ContrastState {
            supported: false,
            level,
            colors: [0; 4],
        }),
        Err(error) => Err(error),
    }
}

fn write_contrast(environment: Environment, level: i32) -> Result<(), String> {
    command(&[
        "settings",
        "--user",
        &environment.user.to_string(),
        "put",
        "secure",
        CONTRAST,
        &format!("{:.3}", level as f64 / 1000.0),
    ])
    .map(|_| ())
}

fn restore_contrast(environment: Environment, original: Option<&str>) -> Result<(), String> {
    let user = environment.user.to_string();
    match original {
        Some(value) => command(&[
            "settings", "--user", &user, "put", "secure", CONTRAST, value,
        ]),
        None => command(&["settings", "--user", &user, "delete", "secure", CONTRAST]),
    }
    .map(|_| ())
}

fn apply_contrast_to(environment: Environment, level: i32) -> Result<ContrastState, String> {
    if environment.sdk < 34 {
        return Err("palette_unsupported: native contrast requires Android 14 or newer".into());
    }
    if !(-1000..=1000).contains(&level) {
        return Err("palette_invalid_choice: contrast must be between -1000 and 1000".into());
    }
    let original = read_contrast_raw(environment)?;
    let before_level = parse_contrast(original.as_deref())?;
    let before = read_contrast_roles(environment)?;
    if before_level == level {
        return Ok(ContrastState {
            supported: true,
            level,
            colors: before,
        });
    }
    write_contrast(environment, level)?;
    let result = (|| {
        if parse_contrast(read_contrast_raw(environment)?.as_deref())? != level {
            return Err("palette_readback: Android did not retain the contrast level".into());
        }
        let mut previous = None;
        for wait in [80, 120, 180, 260, 360, 500] {
            std::thread::sleep(Duration::from_millis(wait));
            let actual = read_contrast_roles(environment)?;
            if previous == Some(actual) && actual != before {
                return Ok(ContrastState {
                    supported: true,
                    level,
                    colors: actual,
                });
            }
            previous = Some(actual);
        }
        Err(
            "palette_readback: this ROM retained contrast but did not regenerate native roles"
                .into(),
        )
    })();
    if result.is_err() {
        restore_contrast(environment, original.as_deref())
            .map_err(|_| "palette_restore_failed: contrast could not be restored")?;
    }
    result
}

fn parse_rgb(raw: &str) -> Option<u32> {
    let raw = raw.trim().strip_prefix('#').unwrap_or(raw.trim());
    let raw = raw.strip_prefix("0x").unwrap_or(raw);
    if !matches!(raw.len(), 6 | 8) || !raw.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let value = u32::from_str_radix(raw, 16).ok()?;
    if raw.len() == 8 && value >> 24 != 0xff {
        return None;
    }
    Some(value & 0x00ff_ffff)
}

fn parse_lookup_rgb(raw: &str) -> Option<u32> {
    // `cmd overlay lookup` normally returns a single resolved color. Some
    // AOSP/OEM builds show an unresolved value followed by `->` and the final
    // value, so always validate the last resolved token rather than depending
    // on one shell-output presentation.
    raw.lines().rev().find_map(|line| {
        let resolved = line.rsplit_once("->").map_or(line, |(_, value)| value);
        parse_rgb(resolved.trim())
    })
}

fn decode(raw: Option<&str>) -> Result<Map<String, Value>, String> {
    let Some(raw) = raw else {
        return Ok(Map::new());
    };
    if raw.len() > 16_384 {
        return Err("palette_invalid_settings: existing theme setting is too large".into());
    }
    match serde_json::from_str(raw) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err("palette_invalid_settings: existing theme JSON was left untouched".into()),
    }
}

fn encode(map: &Map<String, Value>) -> String {
    // Never delete the setting to represent an empty palette. AOSP retains
    // its previous in-memory theme style on null, whereas {} resets it.
    Value::Object(map.clone()).to_string()
}

fn validate(selection: Selection, sdk: i32) -> Result<(), String> {
    if let Selection::Custom { seed, style } = selection {
        if seed > 0x00ff_ffff || style >= STYLES.len() {
            return Err("palette_invalid_choice: invalid seed color or palette style".into());
        }
        if (sdk < 33 && style != 0) || (sdk < 34 && style == 6) {
            return Err(
                "palette_unsupported: this palette style requires a newer Android version".into(),
            );
        }
    }
    Ok(())
}

fn next_setting(
    original: &Map<String, Value>,
    selection: Selection,
    sdk: i32,
    timestamp: u64,
) -> Map<String, Value> {
    let mut next = original.clone();
    for key in COLOR_KEYS {
        next.remove(key);
    }
    if let Selection::Custom { seed, style } = selection {
        next.insert(PALETTE.into(), Value::String(format!("{seed:06X}")));
        next.insert(SOURCE.into(), Value::String("preset".into()));
        if sdk < 33 {
            // Android 12's SystemUI contract requires both legacy fields and
            // supports only the default Tonal Spot strategy.
            next.insert(ACCENT.into(), Value::String(format!("{seed:06X}")));
        } else {
            next.insert(STYLE.into(), Value::String(STYLES[style].into()));
        }
    } else {
        // AOSP tracks wallpaper palettes by source. Keeping this explicit lets
        // SystemUI follow subsequent home-wallpaper changes instead of leaving
        // a fixed preset behind.
        next.insert(SOURCE.into(), Value::String("home_wallpaper".into()));
        if sdk >= 33 {
            next.insert(STYLE.into(), Value::String("TONAL_SPOT".into()));
        }
    }
    next.insert(TIMESTAMP.into(), Value::from(timestamp));
    next
}

fn same_color_fields(a: &Map<String, Value>, b: &Map<String, Value>) -> bool {
    COLOR_KEYS
        .iter()
        .filter(|key| **key != TIMESTAMP)
        .all(|key| a.get(*key) == b.get(*key))
}

fn selection_matches(setting: &Map<String, Value>, selection: Selection, sdk: i32) -> bool {
    match selection {
        Selection::Wallpaper => matches!(
            setting.get(SOURCE).and_then(Value::as_str),
            Some("home_wallpaper" | "lock_wallpaper")
        ),
        Selection::Custom { seed, style } => {
            setting
                .get(PALETTE)
                .and_then(Value::as_str)
                .and_then(parse_rgb)
                == Some(seed)
                && setting.get(SOURCE).and_then(Value::as_str) == Some("preset")
                && (sdk < 33 || setting.get(STYLE).and_then(Value::as_str) == Some(STYLES[style]))
        }
    }
}

fn describe(
    environment: Environment,
    setting: &Map<String, Value>,
    colors: [u32; 5],
    outcome: i32,
) -> PaletteState {
    let seed = setting
        .get(PALETTE)
        .and_then(Value::as_str)
        .and_then(parse_rgb)
        .map(|value| value as i32)
        .unwrap_or(-1);
    let source = setting.get(SOURCE).and_then(Value::as_str);
    let preset = source == Some("preset");
    let wallpaper = matches!(source, Some("home_wallpaper" | "lock_wallpaper"));
    let style = setting
        .get(STYLE)
        .and_then(Value::as_str)
        .map(|name| {
            STYLES
                .iter()
                .position(|style| *style == name)
                .map(|i| i as i32)
                .unwrap_or(-1)
        })
        .unwrap_or(0);
    PaletteState {
        environment,
        mode: if wallpaper {
            0
        } else if seed >= 0 {
            1
        } else if preset {
            2
        } else {
            0
        },
        seed,
        style,
        colors,
        outcome,
    }
}

fn read_from(io: &mut impl PaletteIo) -> Result<PaletteState, String> {
    let setting = decode(io.read_setting()?.as_deref())?;
    let colors = settled_before(io)?;
    let current = decode(io.read_setting()?.as_deref())?;
    if !same_color_fields(&setting, &current) {
        return Err("palette_conflict: the system theme changed while reading".into());
    }
    Ok(describe(io.environment(), &current, colors, 0))
}

fn settled_before(io: &mut impl PaletteIo) -> Result<[u32; 5], String> {
    let first = io.colors()?;
    io.pause(Duration::from_millis(120));
    let second = io.colors()?;
    if first != second {
        return Err("palette_conflict: Android is updating its colors; refresh shortly".into());
    }
    Ok(second)
}

fn rollback(
    io: &mut impl PaletteIo,
    original: &Map<String, Value>,
    attempted: &Map<String, Value>,
) -> Result<(), String> {
    let mut current = decode(io.read_setting()?.as_deref())?;
    if !same_color_fields(&current, attempted) {
        // Another theme picker owns the latest change. Never overwrite it.
        return Ok(());
    }
    for key in COLOR_KEYS {
        current.remove(key);
        if let Some(value) = original.get(key) {
            current.insert(key.into(), value.clone());
        }
    }
    io.write_setting(&encode(&current))
}

fn apply_to(io: &mut impl PaletteIo, selection: Selection) -> Result<PaletteState, String> {
    let environment = io.environment();
    validate(selection, environment.sdk)?;
    if !environment.supported {
        return Err(
            "palette_unsupported: this ROM does not expose Android's native Material You engine"
                .into(),
        );
    }
    let original = decode(io.read_setting()?.as_deref())?;
    let before = settled_before(io)?;
    if selection_matches(&original, selection, environment.sdk) {
        return Ok(describe(environment, &original, before, 0));
    }
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let next = next_setting(&original, selection, environment.sdk, timestamp);
    if same_color_fields(&original, &next) {
        return Ok(describe(environment, &original, before, 0));
    }
    if decode(io.read_setting()?.as_deref())? != original {
        return Err("palette_conflict: the system theme changed; refresh and try again".into());
    }

    let result = (|| {
        io.write_setting(&encode(&next))?;
        let saved = decode(io.read_setting()?.as_deref())?;
        if !same_color_fields(&saved, &next) {
            return Err("palette_readback: Android did not retain the requested palette".into());
        }
        let mut actual = before;
        let mut previous = None;
        let mut settled = false;
        // SystemUI fabricates and commits several overlays asynchronously.
        // OEM builds can take longer than AOSP, so use a bounded progressive
        // window while still requiring two identical complete snapshots.
        for wait in [80, 120, 180, 260, 360, 500, 700, 900] {
            io.pause(Duration::from_millis(wait));
            actual = io.colors()?;
            settled = previous == Some(actual);
            previous = Some(actual);
            if settled && (actual != before || matches!(selection, Selection::Wallpaper)) {
                break;
            }
        }
        if !settled {
            return Err("palette_readback: native color resources have not settled".into());
        }
        let current = decode(io.read_setting()?.as_deref())?;
        if !same_color_fields(&current, &next) {
            return Err("palette_conflict: another theme picker changed the palette".into());
        }
        if matches!(selection, Selection::Custom { .. }) && actual == before {
            return Err(
                "palette_readback: Android retained the request but did not regenerate its native palette"
                    .into(),
            );
        }
        // A wallpaper palette can legitimately resolve to the same tones as
        // the previous selection. Its explicit source still restores future
        // wallpaper-following behavior.
        Ok(describe(
            environment,
            &current,
            actual,
            if actual != before { 1 } else { 2 },
        ))
    })();

    if result.is_err() && rollback(io, &original, &next).is_err() {
        return Err("palette_restore_failed: check the current theme before retrying".into());
    }
    result
}

pub(super) fn read() -> Result<String, String> {
    let _guard = TRANSACTION
        .try_lock()
        .map_err(|_| "palette_busy: a palette operation is in progress")?;
    read_from(&mut AndroidPaletteIo::open()?).map(|state| state.encode())
}

pub(super) fn apply_wallpaper() -> Result<String, String> {
    let _guard = TRANSACTION
        .try_lock()
        .map_err(|_| "palette_busy: a palette operation is in progress")?;
    apply_to(&mut AndroidPaletteIo::open()?, Selection::Wallpaper).map(|state| state.encode())
}

pub(super) fn apply_custom(args: &str) -> Result<String, String> {
    let parts = args.split_whitespace().collect::<Vec<_>>();
    if parts.len() != 2 {
        return Err("palette_invalid_choice: expected seed and style".into());
    }
    let seed = parts[0]
        .parse::<u32>()
        .map_err(|_| "palette_invalid_choice: invalid seed")?;
    let style = parts[1]
        .parse::<usize>()
        .map_err(|_| "palette_invalid_choice: invalid style")?;
    // Reject malformed requests before consulting any Android service.
    validate(Selection::Custom { seed, style }, 37)?;
    let _guard = TRANSACTION
        .try_lock()
        .map_err(|_| "palette_busy: a palette operation is in progress")?;
    apply_to(
        &mut AndroidPaletteIo::open()?,
        Selection::Custom { seed, style },
    )
    .map(|state| state.encode())
}

pub(super) fn read_contrast() -> Result<String, String> {
    let _guard = TRANSACTION
        .try_lock()
        .map_err(|_| "palette_busy: a palette operation is in progress")?;
    describe_contrast(AndroidPaletteIo::open()?.environment).map(|state| state.encode())
}

pub(super) fn apply_contrast(args: &str) -> Result<String, String> {
    let level = args
        .trim()
        .parse::<i32>()
        .map_err(|_| "palette_invalid_choice: invalid contrast level")?;
    if !(-1000..=1000).contains(&level) {
        return Err("palette_invalid_choice: contrast must be between -1000 and 1000".into());
    }
    let _guard = TRANSACTION
        .try_lock()
        .map_err(|_| "palette_busy: a palette operation is in progress")?;
    apply_contrast_to(AndroidPaletteIo::open()?.environment, level).map(|state| state.encode())
}

#[cfg(test)]
mod tests {
    #[test]
    fn contrast_settings_use_androids_scaled_range() {
        assert_eq!(super::parse_contrast(None).unwrap(), 0);
        assert_eq!(super::parse_contrast(Some("-1")).unwrap(), -1000);
        assert_eq!(super::parse_contrast(Some("0.375")).unwrap(), 375);
        assert_eq!(super::parse_contrast(Some("1.0")).unwrap(), 1000);
    }

    #[test]
    fn invalid_contrast_settings_are_rejected() {
        for value in ["-1.001", "1.001", "NaN", "inf", "garbage"] {
            assert!(super::parse_contrast(Some(value)).is_err(), "{value}");
        }
    }

    #[test]
    fn color_families_are_read_concurrently_in_resource_order() {
        let threads = std::sync::Mutex::new(std::collections::HashSet::new());
        let colors = super::read_color_families(|resource| {
            threads.lock().unwrap().insert(std::thread::current().id());
            let index = super::RESOURCES
                .iter()
                .position(|value| *value == resource)
                .unwrap();
            Ok(0x112200 + index as u32)
        })
        .unwrap();
        assert_eq!(colors, [0x112200, 0x112201, 0x112202, 0x112203, 0x112204]);
        assert_eq!(threads.into_inner().unwrap().len(), 5);
    }

    #[test]
    fn one_failed_color_family_fails_the_complete_sample() {
        let result = super::read_color_families(|resource| {
            if resource == super::RESOURCES[2] {
                Err("palette_service_unavailable: rejected".to_string())
            } else {
                Ok(0x112233)
            }
        });
        assert_eq!(result.unwrap_err(), "palette_service_unavailable: rejected");
    }

    use super::*;

    struct FakeIo {
        setting: Option<String>,
        writes: usize,
        fail_colors_after_write: bool,
        native_colors_available: bool,
        supported: bool,
        changed: bool,
        concurrent_palette: Option<String>,
        after_write_colors: Vec<[u32; 5]>,
    }

    impl FakeIo {
        fn new(raw: Option<&str>) -> Self {
            Self {
                setting: raw.map(str::to_string),
                writes: 0,
                fail_colors_after_write: false,
                native_colors_available: true,
                supported: true,
                changed: true,
                concurrent_palette: None,
                after_write_colors: Vec::new(),
            }
        }
    }

    impl PaletteIo for FakeIo {
        fn environment(&self) -> Environment {
            Environment {
                user: 10,
                sdk: 37,
                supported: self.supported,
            }
        }
        fn read_setting(&mut self) -> Result<Option<String>, String> {
            Ok(self.setting.clone())
        }
        fn write_setting(&mut self, value: &str) -> Result<(), String> {
            self.writes += 1;
            self.setting = Some(value.to_string());
            Ok(())
        }
        fn colors(&mut self) -> Result<[u32; 5], String> {
            if !self.native_colors_available {
                return Err("palette_unsupported: native palette resources are unavailable".into());
            }
            if self.writes > 0
                && let Some(other) = self.concurrent_palette.take()
            {
                self.setting = Some(other);
            }
            if self.writes > 0 && self.fail_colors_after_write {
                return Err("palette_service_unavailable".into());
            }
            if self.writes > 0 && !self.after_write_colors.is_empty() {
                return Ok(self.after_write_colors.remove(0));
            }
            Ok([if self.writes > 0 && self.changed {
                0x008577
            } else {
                0x6974ad
            }; 5])
        }
        fn pause(&mut self, _duration: Duration) {}
    }

    fn custom() -> Selection {
        Selection::Custom {
            seed: 0x008577,
            style: 1,
        }
    }

    #[test]
    fn custom_preserves_unrelated_theme_fields_and_types() {
        let raw = r#"{"android.theme.customization.font":"font.package","icon_shape":"round","vendor":{"enabled":true},"array":[1,2]}"#;
        let original = decode(Some(raw)).unwrap();
        let next = next_setting(&original, custom(), 37, 42);
        for (key, value) in &original {
            assert_eq!(next.get(key), Some(value));
        }
        assert_eq!(next.get(PALETTE).unwrap(), "008577");
        assert_eq!(next.get(SOURCE).unwrap(), "preset");
        assert_eq!(next.get(STYLE).unwrap(), "VIBRANT");
    }

    #[test]
    fn wallpaper_removes_only_color_fields() {
        let original = decode(Some(r#"{"font":"kept"}"#)).unwrap();
        let custom = next_setting(&original, custom(), 37, 42);
        let wallpaper = next_setting(&custom, Selection::Wallpaper, 37, 43);
        assert_eq!(wallpaper.get("font"), original.get("font"));
        assert_eq!(wallpaper.get(STYLE).unwrap(), "TONAL_SPOT");
        for key in [PALETTE, ACCENT, "android.theme.customization.dynamic_color"] {
            assert!(!wallpaper.contains_key(key));
        }
        assert_eq!(wallpaper.get(SOURCE).unwrap(), "home_wallpaper");
        assert_eq!(encode(&Map::new()), "{}");
    }

    #[test]
    fn malformed_existing_json_is_not_replaced() {
        for raw in ["[]", "null", "{bad}", "\"theme\"", ""] {
            let mut io = FakeIo::new(Some(raw));
            assert!(apply_to(&mut io, custom()).is_err());
            assert_eq!(io.writes, 0);
            assert_eq!(io.setting.as_deref(), Some(raw));
        }
    }

    #[test]
    fn rejects_invalid_inputs_and_unsupported_styles() {
        assert!(
            validate(
                Selection::Custom {
                    seed: 0x1000000,
                    style: 0
                },
                37
            )
            .is_err()
        );
        assert!(
            validate(
                Selection::Custom {
                    seed: 0x123456,
                    style: 7
                },
                37
            )
            .is_err()
        );
        assert!(validate(custom(), 31).is_err());
        assert!(
            validate(
                Selection::Custom {
                    seed: 0x123456,
                    style: 6
                },
                33
            )
            .is_err()
        );
        assert!(
            validate(
                Selection::Custom {
                    seed: 0x123456,
                    style: 6
                },
                34
            )
            .is_ok()
        );
        for raw in ["-1 0", "1 2 extra", "1", "16777216 0", "1 100"] {
            assert!(
                apply_custom(raw)
                    .unwrap_err()
                    .starts_with("palette_invalid_choice")
            );
        }
    }

    #[test]
    fn verifies_native_output_and_bound_user() {
        let mut io = FakeIo::new(None);
        let applied = apply_to(&mut io, custom()).unwrap();
        assert_eq!(io.writes, 1);
        assert_eq!(applied.outcome, 1);
        assert_eq!(applied.environment.user, 10);
        assert_eq!(applied.seed, 0x008577);
        assert_eq!(applied.colors, [0x008577; 5]);
    }

    #[test]
    fn identical_choice_does_not_write_again() {
        let initial = encode(&next_setting(&Map::new(), custom(), 37, 42));
        let mut io = FakeIo::new(Some(&initial));
        assert_eq!(apply_to(&mut io, custom()).unwrap().outcome, 0);
        assert_eq!(io.writes, 0);
    }

    #[test]
    fn android_12_uses_legacy_pair_without_style() {
        let next = next_setting(
            &Map::new(),
            Selection::Custom {
                seed: 0x123456,
                style: 0,
            },
            31,
            42,
        );
        assert_eq!(next.get(PALETTE).unwrap(), "123456");
        assert_eq!(next.get(ACCENT).unwrap(), "123456");
        assert_eq!(next.get(SOURCE).unwrap(), "preset");
        assert!(!next.contains_key(STYLE));
    }

    #[test]
    fn android_13_uses_palette_and_style_without_legacy_accent() {
        let next = next_setting(&Map::new(), custom(), 33, 42);
        assert_eq!(next.get(STYLE).unwrap(), "VIBRANT");
        assert!(!next.contains_key(ACCENT));
    }

    #[test]
    fn matching_choice_ignores_deprecated_vendor_extras() {
        let mut initial = next_setting(&Map::new(), custom(), 37, 42);
        initial.insert(ACCENT.into(), Value::String("008577".into()));
        initial.insert(
            "android.theme.customization.dynamic_color".into(),
            Value::String("1".into()),
        );
        let mut io = FakeIo::new(Some(&encode(&initial)));
        assert_eq!(apply_to(&mut io, custom()).unwrap().outcome, 0);
        assert_eq!(io.writes, 0);
    }

    #[test]
    fn unchanged_custom_resources_are_rejected_and_rolled_back() {
        let mut io = FakeIo::new(None);
        io.changed = false;
        assert!(
            apply_to(&mut io, custom())
                .unwrap_err()
                .starts_with("palette_readback")
        );
        assert_eq!(io.writes, 2);
        assert_eq!(io.setting.as_deref(), Some("{}"));
    }

    #[test]
    fn failed_readback_restores_previous_setting() {
        let mut io = FakeIo::new(Some(r#"{"font":"kept"}"#));
        io.fail_colors_after_write = true;
        assert!(apply_to(&mut io, custom()).is_err());
        assert_eq!(
            decode(io.setting.as_deref()).unwrap(),
            decode(Some(r#"{"font":"kept"}"#)).unwrap()
        );
        assert_eq!(io.writes, 2);
    }

    #[test]
    fn rollback_preserves_concurrent_non_color_updates() {
        let original = Map::new();
        let attempted = next_setting(&original, custom(), 37, 42);
        let mut current = attempted.clone();
        current.insert("font".into(), Value::String("new.font".into()));
        let mut io = FakeIo::new(Some(&encode(&current)));
        rollback(&mut io, &original, &attempted).unwrap();
        assert_eq!(
            decode(io.setting.as_deref()).unwrap().get("font").unwrap(),
            "new.font"
        );
        assert!(!decode(io.setting.as_deref()).unwrap().contains_key(PALETTE));
    }

    #[test]
    fn rollback_does_not_overwrite_another_palette_picker() {
        let original = Map::new();
        let attempted = next_setting(&original, custom(), 37, 42);
        let other = next_setting(
            &original,
            Selection::Custom {
                seed: 0xabcdef,
                style: 2,
            },
            37,
            43,
        );
        let mut io = FakeIo::new(Some(&encode(&other)));
        rollback(&mut io, &original, &attempted).unwrap();
        assert_eq!(io.writes, 0);
        assert_eq!(decode(io.setting.as_deref()).unwrap(), other);
    }

    #[test]
    fn detects_a_picker_change_during_resource_readback() {
        let other = next_setting(
            &Map::new(),
            Selection::Custom {
                seed: 0xabcdef,
                style: 2,
            },
            37,
            43,
        );
        let mut io = FakeIo::new(None);
        io.concurrent_palette = Some(encode(&other));
        assert!(
            apply_to(&mut io, custom())
                .err()
                .unwrap()
                .starts_with("palette_conflict")
        );
        assert_eq!(io.writes, 1);
        assert_eq!(decode(io.setting.as_deref()).unwrap(), other);
    }

    #[test]
    fn wallpaper_picker_seed_is_not_misreported_as_a_fixed_custom_color() {
        let environment = Environment {
            user: 0,
            sdk: 37,
            supported: true,
        };
        for source in ["home_wallpaper", "lock_wallpaper"] {
            let mut setting = next_setting(&Map::new(), custom(), 37, 42);
            setting.insert(SOURCE.into(), Value::String(source.into()));
            assert_eq!(describe(environment, &setting, [0; 5], 0).mode, 0);
        }
    }

    #[test]
    fn waits_for_two_matching_reads_after_an_overlay_transition() {
        let mut io = FakeIo::new(None);
        io.after_write_colors = vec![[1, 2, 3, 4, 5], [6; 5], [6; 5]];
        let applied = apply_to(&mut io, custom()).unwrap();
        assert_eq!(applied.colors, [6; 5]);
        assert_eq!(applied.outcome, 1);
    }

    #[test]
    fn unstable_readback_rolls_back_without_reporting_success() {
        let mut io = FakeIo::new(None);
        io.after_write_colors = (1..=8).map(|value| [value; 5]).collect();
        assert!(
            apply_to(&mut io, custom())
                .unwrap_err()
                .starts_with("palette_readback")
        );
        assert_eq!(io.writes, 2);
        assert_eq!(io.setting.as_deref(), Some("{}"));
    }

    #[test]
    fn wallpaper_reset_replaces_a_previous_style_and_is_idempotent() {
        let initial = next_setting(
            &Map::new(),
            Selection::Custom {
                seed: 0x7655ca,
                style: 6,
            },
            37,
            42,
        );
        let mut io = FakeIo::new(Some(&encode(&initial)));
        let restored = apply_to(&mut io, Selection::Wallpaper).unwrap();
        assert_eq!(restored.mode, 0);
        assert_eq!(restored.style, 0);
        assert_eq!(restored.seed, -1);
        assert_eq!(
            decode(io.setting.as_deref()).unwrap().get(STYLE).unwrap(),
            "TONAL_SPOT"
        );
        assert_eq!(apply_to(&mut io, Selection::Wallpaper).unwrap().outcome, 0);
        assert_eq!(io.writes, 1);
    }

    #[test]
    fn unsupported_rom_is_not_modified() {
        let mut io = FakeIo::new(None);
        io.supported = false;
        assert!(apply_to(&mut io, custom()).is_err());
        assert_eq!(io.writes, 0);
    }

    #[test]
    fn missing_native_palette_resources_are_not_modified() {
        let mut io = FakeIo::new(None);
        io.native_colors_available = false;
        assert!(
            apply_to(&mut io, custom())
                .unwrap_err()
                .starts_with("palette_unsupported")
        );
        assert_eq!(io.writes, 0);
    }

    #[test]
    fn parses_only_opaque_rgb_colors() {
        assert_eq!(parse_rgb("#ff6974ad"), Some(0x6974ad));
        assert_eq!(parse_rgb("0xff006b5f"), Some(0x006b5f));
        assert_eq!(parse_rgb("008577"), Some(0x008577));
        for raw in [
            "#00857700",
            "red",
            "package.name",
            "#123",
            "garbage",
            "#gg0000",
        ] {
            assert_eq!(parse_rgb(raw), None);
        }
    }

    #[test]
    fn parses_aosp_and_vendor_overlay_lookup_output() {
        assert_eq!(parse_lookup_rgb("#ff6974ad"), Some(0x6974ad));
        assert_eq!(
            parse_lookup_rgb("@android:color/material_dynamic_primary90 -> #ff006b5f"),
            Some(0x006b5f)
        );
        assert_eq!(
            parse_lookup_rgb("resolution trace\n0xff123456"),
            Some(0x123456)
        );
        assert_eq!(parse_lookup_rgb("resource unavailable"), None);
    }
}
