use std::collections::HashMap;
use std::ffi::c_void;
use std::io::{Read, Write};
use std::os::fd::FromRawFd;
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicI32, AtomicI64, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock, mpsc};
use std::time::Duration;

const AF_UNIX: i32 = 1;
const SOCK_STREAM: i32 = 1;
const SOCK_CLOEXEC: i32 = 0x80000;
const SOCKET_NAME: &str = "rodin_essentiald_v13";
const EXTENDED_VALUE_COUNT: usize = 81;

#[repr(C)]
struct SockAddrUn {
    sun_family: u16,
    sun_path: [i8; 108],
}

unsafe extern "C" {
    fn socket(domain: i32, ty: i32, protocol: i32) -> i32;
    fn connect(fd: i32, addr: *const c_void, len: u32) -> i32;
    fn close(fd: i32) -> i32;
}

#[cfg(target_os = "android")]
#[link(name = "log")]
unsafe extern "C" {
    fn __android_log_write(
        prio: i32,
        tag: *const core::ffi::c_char,
        text: *const core::ffi::c_char,
    ) -> i32;
}

fn app_log(message: &'static [u8]) {
    #[cfg(target_os = "android")]
    unsafe {
        let tag = b"RodinEssential\0";
        let _ = __android_log_write(4, tag.as_ptr().cast(), message.as_ptr().cast());
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = message;
    }
}

struct Cache {
    ready: AtomicI32,
    action_state: AtomicI32,
    charging_write_state: AtomicI32,
    charging_mode: AtomicI32,
    battery_capacity: AtomicI32,
    battery_temp: AtomicI32,
    battery_voltage_uv: AtomicI64,
    battery_current_ua: AtomicI64,
    battery_status: AtomicI32,
    battery_health: AtomicI32,
    usb_online: AtomicI32,
    usb_type: AtomicI32,
    cpu_online_mask: AtomicU32,
    cpu_freq_khz: [AtomicI64; 8],
    cpu_gov0: AtomicI32,
    cpu_gov4: AtomicI32,
    cpu_gov7: AtomicI32,
    cpu_available_mhz: [Mutex<Vec<i32>>; 3],
    gpu_gov: AtomicI32,
    io_scheduler: AtomicI32,
    touch_hal: AtomicI32,
    display_hal: AtomicI32,
    touch_state: AtomicI32,
    display_color: AtomicI32,
    display_temp: AtomicI32,
    sunlight: AtomicI32,
    silky: AtomicI32,
    video: AtomicI32,
    dolby: AtomicI32,
    performance: AtomicI32,
    extended: [AtomicI32; EXTENDED_VALUE_COUNT],
    perapp_profiles: Mutex<HashMap<String, i32>>,
    perapp_last_package: Mutex<String>,
}

impl Cache {
    fn new() -> Self {
        Self {
            ready: AtomicI32::new(0),
            action_state: AtomicI32::new(0),
            charging_write_state: AtomicI32::new(0),
            charging_mode: AtomicI32::new(-1),
            battery_capacity: AtomicI32::new(-1),
            battery_temp: AtomicI32::new(-1),
            battery_voltage_uv: AtomicI64::new(-1),
            battery_current_ua: AtomicI64::new(i64::MIN),
            battery_status: AtomicI32::new(-1),
            battery_health: AtomicI32::new(-1),
            usb_online: AtomicI32::new(-1),
            usb_type: AtomicI32::new(-1),
            cpu_online_mask: AtomicU32::new(0),
            cpu_freq_khz: std::array::from_fn(|_| AtomicI64::new(-1)),
            cpu_gov0: AtomicI32::new(-1),
            cpu_gov4: AtomicI32::new(-1),
            cpu_gov7: AtomicI32::new(-1),
            cpu_available_mhz: std::array::from_fn(|_| Mutex::new(Vec::new())),
            gpu_gov: AtomicI32::new(-1),
            io_scheduler: AtomicI32::new(-1),
            touch_hal: AtomicI32::new(0),
            display_hal: AtomicI32::new(0),
            touch_state: AtomicI32::new(-1),
            display_color: AtomicI32::new(-1),
            display_temp: AtomicI32::new(-1),
            sunlight: AtomicI32::new(-1),
            silky: AtomicI32::new(-1),
            video: AtomicI32::new(-1),
            dolby: AtomicI32::new(-1),
            performance: AtomicI32::new(-1),
            extended: std::array::from_fn(|_| AtomicI32::new(-1)),
            perapp_profiles: Mutex::new(HashMap::new()),
            perapp_last_package: Mutex::new(String::new()),
        }
    }
}

enum Command {
    Refresh,
    Charging(i32),
    Touch(i32),
    DisplayColor(i32),
    DisplayTemp(i32),
    Sunlight(i32),
    Silky(i32),
    Video(i32),
    Dolby(i32),
    Performance(i32),
    CpuGovernor(i32, i32),
    GpuGovernor(i32),
    IoScheduler(i32),
    Extended(i32, i32, i32),
    PerAppPackage(String, i32),
    OpenLink(i32),
}

struct Runtime {
    cache: Arc<Cache>,
    tx: mpsc::Sender<Command>,
}

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn abstract_addr(name: &str) -> Option<(SockAddrUn, u32)> {
    let bytes = name.as_bytes();
    if bytes.len() + 1 >= 108 {
        return None;
    }
    let mut addr = SockAddrUn {
        sun_family: AF_UNIX as u16,
        sun_path: [0; 108],
    };
    for (i, b) in bytes.iter().enumerate() {
        addr.sun_path[i + 1] = *b as i8;
    }
    Some((addr, (2 + 1 + bytes.len()) as u32))
}

static LAST_DAEMON_SPAWN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn ensure_daemon_running() {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let last = LAST_DAEMON_SPAWN.load(std::sync::atomic::Ordering::Acquire);
    if now.saturating_sub(last) >= 3 {
        LAST_DAEMON_SPAWN.store(now, std::sync::atomic::Ordering::Release);
        app_log(b"RODIN_DAEMON_UNAVAILABLE init_service_required\0");
    }
}

fn connect_daemon() -> Result<UnixStream, String> {
    let (addr, len) = abstract_addr(SOCKET_NAME).ok_or("invalid socket name")?;
    let fd = unsafe { socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(format!("socket: {}", std::io::Error::last_os_error()));
    }
    if unsafe { connect(fd, &addr as *const _ as *const c_void, len) } != 0 {
        let e = std::io::Error::last_os_error();
        unsafe { close(fd) };
        ensure_daemon_running();
        return Err(format!("connect: {e}"));
    }
    let stream = unsafe { UnixStream::from_raw_fd(fd) };
    // Super Touch's vendor first-frame transaction may wait up to two seconds
    // for the panel pipeline. Keep the UI asynchronous, but allow that verified
    // HAL transaction to finish instead of reporting a false timeout.
    let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(3)));
    Ok(stream)
}

fn request(command: &str) -> Result<String, String> {
    let mut stream = connect_daemon()?;
    stream
        .write_all(command.as_bytes())
        .map_err(|e| format!("write: {e}"))?;
    stream.flush().map_err(|e| format!("flush: {e}"))?;
    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .map_err(|e| format!("read: {e}"))?;
    let response = response.trim();
    if let Some(body) = response.strip_prefix("OK ") {
        Ok(body.to_string())
    } else {
        Err(response.to_string())
    }
}

fn parse_i32(value: Option<&String>) -> i32 {
    value.and_then(|v| v.parse::<i32>().ok()).unwrap_or(-1)
}
fn parse_i64(value: Option<&String>) -> i64 {
    value.and_then(|v| v.parse::<i64>().ok()).unwrap_or(-1)
}

fn code_status(value: &str) -> i32 {
    match value.to_ascii_lowercase().as_str() {
        "charging" => 1,
        "discharging" => 2,
        "not charging" => 3,
        "full" => 4,
        _ => 0,
    }
}

fn code_health(value: &str) -> i32 {
    match value.to_ascii_lowercase().as_str() {
        "good" => 1,
        "overheat" => 2,
        "dead" => 3,
        "over voltage" => 4,
        "cold" => 5,
        _ => 0,
    }
}

fn code_usb_type(value: &str) -> i32 {
    let v = value.to_ascii_uppercase();
    if v.contains("PD") {
        4
    } else if v.contains("DCP") {
        3
    } else if v.contains("CDP") {
        2
    } else if v.contains("SDP") {
        1
    } else if v == "NA" || v.is_empty() {
        -1
    } else {
        0
    }
}

fn cpu_mask(value: &str) -> u32 {
    let mut mask = 0u32;
    for part in value.split(',') {
        let part = part.trim();
        if let Some((a, b)) = part.split_once('-') {
            if let (Ok(start), Ok(end)) = (a.parse::<u32>(), b.parse::<u32>()) {
                for cpu in start..=end.min(31) {
                    mask |= 1u32 << cpu;
                }
            }
        } else if let Ok(cpu) = part.parse::<u32>()
            && cpu < 32
        {
            mask |= 1u32 << cpu;
        }
    }
    mask
}

fn cpu_gov_code(value: &str) -> i32 {
    match value {
        "sugov_ext" => 0,
        "conservative" => 1,
        "powersave" => 2,
        "performance" => 3,
        "schedutil" => 4,
        _ => -1,
    }
}

fn cpu_policy_slot(policy: i32) -> Option<usize> {
    match policy {
        0 => Some(0),
        4 => Some(1),
        7 => Some(2),
        _ => None,
    }
}

fn gpu_gov_code(value: &str) -> i32 {
    match value {
        "dummy" => 0,
        "powersave" => 1,
        "performance" => 2,
        "simple_ondemand" => 3,
        _ => -1,
    }
}
fn io_code(value: &str) -> i32 {
    match value {
        "none" => 0,
        "mq-deadline" => 1,
        "kyber" => 2,
        "bfq" => 3,
        _ => -1,
    }
}

fn refresh(cache: &Cache) -> Result<(), String> {
    let body = request("GET snapshot")?;
    let mut map = std::collections::HashMap::<String, String>::new();
    for field in body.split(';') {
        if let Some((k, v)) = field.split_once('=') {
            map.insert(k.to_string(), v.to_string());
        }
    }
    if map.get("protocol").map(String::as_str) != Some("13.3") {
        return Err("protocol mismatch".into());
    }

    cache
        .charging_mode
        .store(parse_i32(map.get("charging")), Ordering::Release);
    cache
        .battery_capacity
        .store(parse_i32(map.get("cap")), Ordering::Release);
    cache
        .battery_temp
        .store(parse_i32(map.get("temp")), Ordering::Release);
    cache
        .battery_voltage_uv
        .store(parse_i64(map.get("voltage")), Ordering::Release);
    cache.battery_current_ua.store(
        map.get("current")
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(i64::MIN),
        Ordering::Release,
    );
    cache.battery_status.store(
        map.get("status").map(|v| code_status(v)).unwrap_or(0),
        Ordering::Release,
    );
    cache.battery_health.store(
        map.get("health").map(|v| code_health(v)).unwrap_or(0),
        Ordering::Release,
    );
    cache
        .usb_online
        .store(parse_i32(map.get("usb_online")), Ordering::Release);
    cache.usb_type.store(
        map.get("usb_type").map(|v| code_usb_type(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache.cpu_online_mask.store(
        map.get("cpu_online").map(|v| cpu_mask(v)).unwrap_or(0),
        Ordering::Release,
    );
    for cpu in 0..8 {
        let key = format!("cpu{cpu}");
        cache.cpu_freq_khz[cpu].store(parse_i64(map.get(&key)), Ordering::Release);
    }
    cache.cpu_gov0.store(
        map.get("gov0").map(|v| cpu_gov_code(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache.cpu_gov4.store(
        map.get("gov4").map(|v| cpu_gov_code(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache.cpu_gov7.store(
        map.get("gov7").map(|v| cpu_gov_code(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache.gpu_gov.store(
        map.get("gpu_gov").map(|v| gpu_gov_code(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache.io_scheduler.store(
        map.get("io").map(|v| io_code(v)).unwrap_or(-1),
        Ordering::Release,
    );
    cache
        .touch_hal
        .store(parse_i32(map.get("touch_hal")), Ordering::Release);
    cache
        .display_hal
        .store(parse_i32(map.get("display_hal")), Ordering::Release);
    cache
        .touch_state
        .store(parse_i32(map.get("touch")), Ordering::Release);
    cache
        .display_color
        .store(parse_i32(map.get("display_color")), Ordering::Release);
    cache
        .display_temp
        .store(parse_i32(map.get("display_temp")), Ordering::Release);
    cache
        .sunlight
        .store(parse_i32(map.get("sunlight")), Ordering::Release);
    cache
        .silky
        .store(parse_i32(map.get("silky")), Ordering::Release);
    cache
        .video
        .store(parse_i32(map.get("video")), Ordering::Release);
    cache
        .dolby
        .store(parse_i32(map.get("dolby")), Ordering::Release);
    cache
        .performance
        .store(parse_i32(map.get("perf")), Ordering::Release);
    let extended_fields: &[(&str, usize)] = &[
        ("phase", 0),
        ("dt2w", 1),
        ("expert_gamut", 2),
        ("expert_1", 3),
        ("expert_2", 4),
        ("expert_3", 5),
        ("expert_4", 6),
        ("expert_5", 7),
        ("expert_6", 8),
        ("expert_7", 9),
        ("expert_8", 10),
        ("perf_supported", 11),
        ("perf_verified", 12),
        ("perf_verify_ok", 13),
        ("cpu_drift0", 14),
        ("cpu_drift4", 15),
        ("cpu_drift7", 16),
        ("gpu_drift", 17),
        ("io_drift", 18),
        ("perapp_enabled", 19),
        ("perapp_active", 20),
        ("perapp_count", 21),
        ("display_width", 22),
        ("display_height", 23),
        ("display_hz_x10", 24),
        ("display_max_hz_x10", 25),
        ("persistence_loaded", 26),
        ("sunlight_saved", 27),
        ("display_ack", 28),
        ("touch_ack", 29),
        ("perapp_apply_ack", 30),
        ("perapp_pruned", 31),
        ("runtime_keepalive_ack", 32),
        ("runtime_keepalive_count", 33),
        ("cpu_manual", 34),
        ("cpu_write_ack", 35),
        ("cpu_saved_mask", 36),
        ("core_ctl_nodes", 37),
        ("display_density", 38),
        ("zram_size", 39),
        ("zram_orig", 40),
        ("zram_compr", 41),
        ("zram_used", 42),
        ("zram_swappiness", 43),
        ("gpu_load", 45),
        ("gpu_cur_freq", 46),
        ("gpu_min_freq", 47),
        ("gpu_max_freq", 48),
        ("gpu_ged_boost", 50),
        ("gpu_thermal_state", 51),
        ("gpu_uncap_active", 52),
        ("cpu_min0", 53),
        ("cpu_max0", 54),
        ("cpu_min4", 55),
        ("cpu_max4", 56),
        ("cpu_min7", 57),
        ("cpu_max7", 58),
        ("gpu_power_policy", 59),
        ("touch_sustained_rate", 60),
        ("touch_instant_rate", 61),
        ("touch_panel", 62),
        ("touch_control_path", 63),
        ("touch_measured_rate_x10", 64),
        ("touch_resampler_ready", 65),
        ("touch_measurement_active", 66),
        ("touch_source_rate_x10", 67),
        ("cpu_live_min0", 68),
        ("cpu_live_max0", 69),
        ("cpu_live_min4", 70),
        ("cpu_live_max4", 71),
        ("cpu_live_min7", 72),
        ("cpu_live_max7", 73),
        ("cpu_freq_ack", 74),
        ("cpu_freq_drift0", 75),
        ("cpu_freq_drift4", 76),
        ("cpu_freq_drift7", 77),
        ("display_native_density", 78),
        ("touch_resampler_path", 79),
        ("touch_resampler_error", 80),
    ];

    for &(key, index) in extended_fields {
        cache.extended[index].store(parse_i32(map.get(key)), Ordering::Release);
    }

    let alg_code = match map.get("zram_alg").map(String::as_str) {
        Some("zstd") => 1,
        Some("lzo-rle") => 2,
        Some("lzo") => 3,
        _ => 0,
    };
    cache.extended[44].store(alg_code, Ordering::Release);

    let gov_code = match map.get("gpu_gov").map(String::as_str) {
        Some("performance") => 1,
        Some("powersave") => 2,
        Some("userspace") => 3,
        Some("dummy") => 4,
        _ => 0,
    };
    cache.extended[49].store(gov_code, Ordering::Release);

    for (slot, key) in [(0, "cpu_avail0"), (1, "cpu_avail4"), (2, "cpu_avail7")] {
        let Some(raw) = map.get(key) else {
            continue;
        };
        let mut frequencies = raw
            .split(',')
            .filter_map(|value| value.parse::<i32>().ok())
            .filter(|value| *value > 0)
            .collect::<Vec<_>>();
        frequencies.sort_unstable();
        frequencies.dedup();
        if let Ok(mut cached) = cache.cpu_available_mhz[slot].lock() {
            *cached = frequencies;
        }
    }

    if let Ok(mut profiles) = cache.perapp_profiles.lock() {
        profiles.clear();

        if let Some(raw) = map.get("perapp_map") {
            for item in raw.split(',') {
                let Some((package, profile)) = item.rsplit_once(':') else {
                    continue;
                };

                if let Ok(profile) = profile.parse::<i32>()
                    && matches!(profile, 0..=3)
                {
                    profiles.insert(package.to_string(), profile);
                }
            }
        }
    }

    if let Ok(mut package) = cache.perapp_last_package.lock() {
        *package = map.get("perapp_last_pkg").cloned().unwrap_or_default();
    }

    cache.ready.store(1, Ordering::Release);
    Ok(())
}

fn cpu_governor_name(code: i32) -> Option<&'static str> {
    match code {
        0 => Some("sugov_ext"),
        1 => Some("conservative"),
        2 => Some("powersave"),
        3 => Some("performance"),
        4 => Some("schedutil"),
        _ => None,
    }
}
fn gpu_governor_name(code: i32) -> Option<&'static str> {
    match code {
        0 => Some("dummy"),
        1 => Some("powersave"),
        2 => Some("performance"),
        3 => Some("simple_ondemand"),
        _ => None,
    }
}
fn io_name(code: i32) -> Option<&'static str> {
    match code {
        0 => Some("none"),
        1 => Some("mq-deadline"),
        2 => Some("kyber"),
        3 => Some("bfq"),
        _ => None,
    }
}

fn perform(command: Command) -> Result<(), String> {
    match command {
        Command::Refresh => Ok(()),
        Command::Charging(v) if matches!(v, 0 | 8) => {
            request(&format!("SET charging {v}")).map(|_| ())
        }
        Command::Touch(v) if (0..=7).contains(&v) => request(&format!("SET touch {v}")).map(|_| ()),
        Command::DisplayColor(v) if (0..=2).contains(&v) => {
            request(&format!("SET display.color {v}")).map(|_| ())
        }
        Command::DisplayTemp(v) if (1..=3).contains(&v) => {
            request(&format!("SET display.temp {v}")).map(|_| ())
        }
        Command::Sunlight(v) if matches!(v, 0 | 1) => {
            request(&format!("SET display.sunlight {v}")).map(|_| ())
        }
        Command::Silky(v) if matches!(v, 0 | 1) => {
            request(&format!("SET display.silky {v}")).map(|_| ())
        }
        Command::Video(v) if matches!(v, 0 | 1) => {
            request(&format!("SET display.video {v}")).map(|_| ())
        }
        Command::Dolby(v) if matches!(v, 0 | 1) => {
            request(&format!("SET display.dolby {v}")).map(|_| ())
        }
        Command::Performance(v) if (0..=3).contains(&v) => {
            request(&format!("SET perf {v}")).map(|_| ())
        }
        Command::CpuGovernor(policy, code) if matches!(policy, 0 | 4 | 7) => {
            let name = cpu_governor_name(code).ok_or("invalid cpu governor code")?;
            request(&format!("SET cpu.gov {policy} {name}")).map(|_| ())
        }
        Command::GpuGovernor(code) => {
            let name = gpu_governor_name(code).ok_or("invalid gpu governor code")?;
            request(&format!("SET gpu.gov {name}")).map(|_| ())
        }
        Command::IoScheduler(code) => {
            let name = io_name(code).ok_or("invalid io scheduler code")?;
            request(&format!("SET io.scheduler {name}")).map(|_| ())
        }
        Command::Extended(op, a, b) => {
            let command = match op {
                1 if matches!(a, 0 | 1) => format!("SET touch.dt2w {a}"),
                2 if matches!(a, 1..=3) => {
                    format!("SET display.expert.gamut {a}")
                }
                3 => format!("SET display.expert.channel {a} {b}"),
                4 => "SET display.expert.reset".to_string(),
                5 if matches!(a, 0 | 1) => format!("SET perapp.enabled {a}"),
                6 if matches!(a, -1..=3) => {
                    format!("SET perapp.assign {a}")
                }
                7 if matches!(a, 0 | 1) => {
                    format!("SET cpu.manual {a}")
                }
                8 if (1..=7).contains(&a) && matches!(b, 0 | 1) => {
                    format!("SET cpu.core {a} {b}")
                }
                9 => {
                    let width = a;
                    let height = (b >> 16) & 0xFFFF;
                    let density = b & 0xFFFF;
                    let req_str = if width <= 0 || height <= 0 || (width == 1220 && height == 2712)
                    {
                        "SET display.res 0 0 0".to_string()
                    } else {
                        format!("SET display.res {width} {height} {density}")
                    };
                    return request(&req_str).map(|_| ());
                }
                10 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[39].store(a, Ordering::Release);
                    }
                    let cmd_str = format!("SET zram.size {a}");
                    return request(&cmd_str).map(|_| ());
                }
                11 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[44].store(a, Ordering::Release);
                    }
                    let alg = match a {
                        1 => "zstd",
                        2 => "lzo-rle",
                        3 => "lzo",
                        _ => "lz4",
                    };
                    let cmd_str = format!("SET zram.algorithm {alg}");
                    return request(&cmd_str).map(|_| ());
                }
                12 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[43].store(a, Ordering::Release);
                    }
                    let cmd_str = format!("SET zram.swappiness {a}");
                    return request(&cmd_str).map(|_| ());
                }
                13 => {
                    return request("ACTION zram.compact").map(|_| ());
                }
                14 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[52].store(a, Ordering::Release);
                        if a == 1 {
                            r.cache.extended[48].store(1300, Ordering::Release);
                            r.cache.extended[51].store(0, Ordering::Release);
                        }
                    }
                    let cmd_str = format!("SET gpu.uncap {a}");
                    return request(&cmd_str).map(|_| ());
                }
                15 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[47].store(a, Ordering::Release);
                    }
                    let cmd_str = format!("SET gpu.min_freq {a}");
                    return request(&cmd_str).map(|_| ());
                }
                16 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[48].store(a, Ordering::Release);
                    }
                    let cmd_str = format!("SET gpu.max_freq {a}");
                    return request(&cmd_str).map(|_| ());
                }
                17 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[49].store(a, Ordering::Release);
                    }
                    let gov = match a {
                        1 => "performance",
                        2 => "powersave",
                        3 => "userspace",
                        4 => "dummy",
                        _ => "simple_ondemand",
                    };
                    let cmd_str = format!("SET gpu.governor {gov}");
                    return request(&cmd_str).map(|_| ());
                }
                18 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[50].store(a, Ordering::Release);
                    }
                    let cmd_str = format!("SET gpu.ged_boost {a}");
                    return request(&cmd_str).map(|_| ());
                }
                19 => {
                    if let Some(r) = runtime() {
                        match a {
                            0 => r.cache.extended[53].store(b, Ordering::Release),
                            4 => r.cache.extended[55].store(b, Ordering::Release),
                            7 => r.cache.extended[57].store(b, Ordering::Release),
                            _ => {}
                        }
                    }
                    let cmd_str = format!("SET cpu.min_freq {a} {b}");
                    return request(&cmd_str).map(|_| ());
                }
                20 => {
                    if let Some(r) = runtime() {
                        match a {
                            0 => r.cache.extended[54].store(b, Ordering::Release),
                            4 => r.cache.extended[56].store(b, Ordering::Release),
                            7 => r.cache.extended[58].store(b, Ordering::Release),
                            _ => {}
                        }
                    }
                    let cmd_str = format!("SET cpu.max_freq {a} {b}");
                    return request(&cmd_str).map(|_| ());
                }
                21 => {
                    let min = (b >> 16) & 0xFFFF;
                    let max = b & 0xFFFF;
                    if let Some(r) = runtime() {
                        match a {
                            0 => {
                                r.cache.extended[53].store(min, Ordering::Release);
                                r.cache.extended[54].store(max, Ordering::Release);
                            }
                            4 => {
                                r.cache.extended[55].store(min, Ordering::Release);
                                r.cache.extended[56].store(max, Ordering::Release);
                            }
                            7 => {
                                r.cache.extended[57].store(min, Ordering::Release);
                                r.cache.extended[58].store(max, Ordering::Release);
                            }
                            _ => {}
                        }
                    }
                    let cmd_str = format!("SET cpu.freq_range {a} {min} {max}");
                    return request(&cmd_str).map(|_| ());
                }
                22 => {
                    if let Some(r) = runtime() {
                        r.cache.extended[59].store(a, Ordering::Release);
                    }
                    let pol = if a == 1 { "always_on" } else { "coarse_demand" };
                    let cmd_str = format!("SET gpu.power_policy {pol}");
                    return request(&cmd_str).map(|_| ());
                }
                23 if matches!(a, 0 | 4 | 7) => {
                    if let Some(r) = runtime() {
                        match a {
                            0 => {
                                r.cache.extended[53].store(-1, Ordering::Release);
                                r.cache.extended[54].store(-1, Ordering::Release);
                            }
                            4 => {
                                r.cache.extended[55].store(-1, Ordering::Release);
                                r.cache.extended[56].store(-1, Ordering::Release);
                            }
                            7 => {
                                r.cache.extended[57].store(-1, Ordering::Release);
                                r.cache.extended[58].store(-1, Ordering::Release);
                            }
                            _ => {}
                        }
                    }
                    let cmd_str = format!("SET cpu.freq_reset {a}");
                    return request(&cmd_str).map(|_| ());
                }
                _ => return Err("invalid extended command".into()),
            };

            request(&command).map(|_| ())
        }
        Command::PerAppPackage(package, profile) if matches!(profile, -1..=3) => {
            if package.len() < 3
                || package.len() > 255
                || !package.contains('.')
                || !package
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
            {
                return Err("invalid package name".into());
            }

            request(&format!("SET perapp.package {profile} {package}")).map(|_| ())
        }
        Command::OpenLink(code) if matches!(code, 0 | 1) => {
            request(&format!("OPEN support {code}")).map(|_| ())
        }
        _ => Err("invalid backend command".into()),
    }
}

fn rodin_command_name(command: &Command) -> &'static str {
    match command {
        Command::Refresh => "refresh",
        Command::Charging(_) => "charging",
        Command::Touch(_) => "touch",
        Command::DisplayColor(_) => "display.color",
        Command::DisplayTemp(_) => "display.temp",
        Command::Sunlight(_) => "display.sunlight",
        Command::Silky(_) => "display.silky",
        Command::Video(_) => "display.video",
        Command::Dolby(_) => "display.dolby",
        Command::Performance(_) => "performance",
        Command::CpuGovernor(_, _) => "cpu.governor",
        Command::GpuGovernor(_) => "gpu.governor",
        Command::IoScheduler(_) => "ufs.scheduler",
        Command::Extended(_, _, _) => "extended.feature",
        Command::PerAppPackage(_, _) => "perapp.package",
        Command::OpenLink(_) => "support.link",
    }
}

fn rodin_action_log(message: String) {
    #[cfg(target_os = "android")]
    if let Ok(c) = std::ffi::CString::new(message) {
        unsafe {
            __android_log_write(4, c"RodinEssential".as_ptr(), c.as_ptr());
        }
    }
    #[cfg(not(target_os = "android"))]
    let _ = message;
}

fn worker(cache: Arc<Cache>, rx: mpsc::Receiver<Command>) {
    let mut logged_pass = false;
    let mut logged_fail = false;
    let mut last_idle_refresh = std::time::Instant::now()
        .checked_sub(Duration::from_millis(500))
        .unwrap_or_else(std::time::Instant::now);

    loop {
        match rx.recv_timeout(Duration::from_millis(500)) {
            Ok(command) => {
                if matches!(&command, Command::Refresh) {
                    match refresh(&cache) {
                        Ok(()) => {
                            if !logged_pass {
                                app_log(b"RODIN_BACKEND_APP=PASS protocol=13.3\0");
                                logged_pass = true;
                            }
                            logged_fail = false;
                        }
                        Err(error) => {
                            cache.ready.store(0, Ordering::Release);
                            rodin_action_log(format!("RODIN_REFRESH_FAIL error={error}"));
                            if !logged_fail {
                                app_log(b"RODIN_BACKEND_APP=FAIL socket_or_selinux\0");
                                logged_fail = true;
                            }
                        }
                    }
                    last_idle_refresh = std::time::Instant::now();
                    continue;
                }

                let name = rodin_command_name(&command);
                let charging_action = matches!(&command, Command::Charging(_));

                cache.action_state.store(1, Ordering::Release);
                if charging_action {
                    cache.charging_write_state.store(1, Ordering::Release);
                }

                let started = std::time::Instant::now();

                match perform(command) {
                    Ok(()) => {
                        let elapsed = started.elapsed().as_millis();
                        cache.action_state.store(2, Ordering::Release);
                        if charging_action {
                            cache.charging_write_state.store(2, Ordering::Release);
                        }

                        match refresh(&cache) {
                            Ok(()) => {
                                rodin_action_log(format!(
                                    "RODIN_ACTION_PASS action={name} elapsed_ms={elapsed}"
                                ));
                                logged_fail = false;
                            }
                            Err(error) => {
                                cache.ready.store(0, Ordering::Release);
                                rodin_action_log(format!(
                                    "RODIN_ACTION_REFRESH_FAIL action={name} elapsed_ms={elapsed} error={error}"
                                ));
                            }
                        }
                    }
                    Err(error) => {
                        let elapsed = started.elapsed().as_millis();
                        cache.action_state.store(-1, Ordering::Release);
                        if charging_action {
                            cache.charging_write_state.store(-1, Ordering::Release);
                        }

                        let _ = refresh(&cache);

                        rodin_action_log(format!(
                            "RODIN_ACTION_FAIL action={name} elapsed_ms={elapsed} error={error}"
                        ));
                    }
                }

                last_idle_refresh = std::time::Instant::now();
            }

            Err(mpsc::RecvTimeoutError::Timeout) => {}

            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return;
            }
        }

        if last_idle_refresh.elapsed() >= Duration::from_millis(500) {
            match refresh(&cache) {
                Ok(()) => {
                    if !logged_pass {
                        app_log(b"RODIN_BACKEND_APP=PASS protocol=13.3\0");
                        logged_pass = true;
                    }
                    logged_fail = false;
                }
                Err(_) => {
                    cache.ready.store(0, Ordering::Release);
                    if !logged_fail {
                        app_log(b"RODIN_BACKEND_APP=FAIL socket_or_selinux\0");
                        logged_fail = true;
                    }
                }
            }

            last_idle_refresh = std::time::Instant::now();
        }
    }
}

fn runtime() -> Option<&'static Runtime> {
    RUNTIME.get()
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_start() -> i32 {
    if RUNTIME.get().is_some() {
        return 1;
    }
    let cache = Arc::new(Cache::new());
    let (tx, rx) = mpsc::channel();
    let worker_cache = Arc::clone(&cache);
    std::thread::spawn(move || worker(worker_cache, rx));
    let _ = RUNTIME.set(Runtime { cache, tx });
    1
}

fn send(command: Command) -> i32 {
    runtime()
        .and_then(|rt| rt.tx.send(command).ok())
        .map(|_| 1)
        .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_refresh() -> i32 {
    send(Command::Refresh)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_ready() -> i32 {
    runtime()
        .map(|r| r.cache.ready.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_action_state() -> i32 {
    runtime()
        .map(|r| r.cache.action_state.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_charging_write_state() -> i32 {
    runtime()
        .map(|r| r.cache.charging_write_state.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_charging_mode() -> i32 {
    runtime()
        .map(|r| r.cache.charging_mode.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_charging_mode(v: i32) -> i32 {
    send(Command::Charging(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_capacity() -> i32 {
    runtime()
        .map(|r| r.cache.battery_capacity.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_temp_tenths_c() -> i32 {
    runtime()
        .map(|r| r.cache.battery_temp.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_voltage_uv() -> i64 {
    runtime()
        .map(|r| r.cache.battery_voltage_uv.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_current_ua() -> i64 {
    runtime()
        .map(|r| r.cache.battery_current_ua.load(Ordering::Acquire))
        .unwrap_or(i64::MIN)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_status() -> i32 {
    runtime()
        .map(|r| r.cache.battery_status.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_battery_health() -> i32 {
    runtime()
        .map(|r| r.cache.battery_health.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_usb_online() -> i32 {
    runtime()
        .map(|r| r.cache.usb_online.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_usb_type() -> i32 {
    runtime()
        .map(|r| r.cache.usb_type.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_cpu_online_mask() -> u32 {
    runtime()
        .map(|r| r.cache.cpu_online_mask.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_cpu_freq_khz(index: u32) -> i64 {
    if index >= 8 {
        -1
    } else {
        runtime()
            .map(|r| r.cache.cpu_freq_khz[index as usize].load(Ordering::Acquire))
            .unwrap_or(-1)
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_cpu_governor(policy: i32) -> i32 {
    runtime()
        .map(|r| match policy {
            0 => r.cache.cpu_gov0.load(Ordering::Acquire),
            4 => r.cache.cpu_gov4.load(Ordering::Acquire),
            7 => r.cache.cpu_gov7.load(Ordering::Acquire),
            _ => -1,
        })
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_cpu_governor(policy: i32, code: i32) -> i32 {
    send(Command::CpuGovernor(policy, code))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_cpu_available_count(policy: i32) -> i32 {
    let Some(slot) = cpu_policy_slot(policy) else {
        return 0;
    };

    runtime()
        .and_then(|runtime| runtime.cache.cpu_available_mhz[slot].lock().ok())
        .map(|frequencies| frequencies.len().min(i32::MAX as usize) as i32)
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_cpu_available_freq(policy: i32, index: i32) -> i32 {
    let Some(slot) = cpu_policy_slot(policy) else {
        return -1;
    };
    if index < 0 {
        return -1;
    }

    runtime()
        .and_then(|runtime| runtime.cache.cpu_available_mhz[slot].lock().ok())
        .and_then(|frequencies| frequencies.get(index as usize).copied())
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_gpu_governor() -> i32 {
    runtime()
        .map(|r| r.cache.gpu_gov.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_gpu_governor(code: i32) -> i32 {
    send(Command::GpuGovernor(code))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_ufs_scheduler() -> i32 {
    runtime()
        .map(|r| r.cache.io_scheduler.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_ufs_scheduler(code: i32) -> i32 {
    send(Command::IoScheduler(code))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_touch_hal() -> i32 {
    runtime()
        .map(|r| r.cache.touch_hal.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_display_hal() -> i32 {
    runtime()
        .map(|r| r.cache.display_hal.load(Ordering::Acquire))
        .unwrap_or(0)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_touch_state() -> i32 {
    runtime()
        .map(|r| r.cache.touch_state.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_touch_state(v: i32) -> i32 {
    send(Command::Touch(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_display_color() -> i32 {
    runtime()
        .map(|r| r.cache.display_color.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_display_color(v: i32) -> i32 {
    send(Command::DisplayColor(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_display_temp() -> i32 {
    runtime()
        .map(|r| r.cache.display_temp.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_display_temp(v: i32) -> i32 {
    send(Command::DisplayTemp(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_sunlight() -> i32 {
    runtime()
        .map(|r| r.cache.sunlight.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_sunlight(v: i32) -> i32 {
    send(Command::Sunlight(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_silky() -> i32 {
    runtime()
        .map(|r| r.cache.silky.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_silky(v: i32) -> i32 {
    send(Command::Silky(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_video() -> i32 {
    runtime()
        .map(|r| r.cache.video.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_video(v: i32) -> i32 {
    send(Command::Video(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_dolby() -> i32 {
    runtime()
        .map(|r| r.cache.dolby.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_dolby(v: i32) -> i32 {
    send(Command::Dolby(v))
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_get_performance_profile() -> i32 {
    runtime()
        .map(|r| r.cache.performance.load(Ordering::Acquire))
        .unwrap_or(-1)
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_set_performance_profile(v: i32) -> i32 {
    if let Some(r) = runtime() {
        r.cache.performance.store(v, Ordering::Release);
        match v {
            3 => {
                r.cache.extended[47].store(1300, Ordering::Release); // min_freq
                r.cache.extended[48].store(1300, Ordering::Release); // max_freq
                r.cache.extended[49].store(1, Ordering::Release); // gov = performance
                r.cache.extended[50].store(1, Ordering::Release); // ged_boost = 1
                r.cache.extended[52].store(1, Ordering::Release); // uncap = 1
                r.cache.extended[59].store(1, Ordering::Release); // power_policy = always_on
            }
            1 => {
                r.cache.extended[47].store(260, Ordering::Release); // min_freq
                r.cache.extended[48].store(1300, Ordering::Release); // max_freq
                r.cache.extended[49].store(0, Ordering::Release); // gov = simple_ondemand
                r.cache.extended[50].store(1, Ordering::Release); // ged_boost = 1
                r.cache.extended[52].store(0, Ordering::Release); // uncap = 0
                r.cache.extended[59].store(1, Ordering::Release); // power_policy = always_on
            }
            2 => {
                r.cache.extended[47].store(260, Ordering::Release); // min_freq
                r.cache.extended[48].store(598, Ordering::Release); // max_freq
                r.cache.extended[49].store(2, Ordering::Release); // gov = powersave
                r.cache.extended[50].store(0, Ordering::Release); // ged_boost = 0
                r.cache.extended[52].store(0, Ordering::Release); // uncap = 0
                r.cache.extended[59].store(0, Ordering::Release); // power_policy = coarse_demand
            }
            _ => {
                r.cache.extended[47].store(260, Ordering::Release); // min_freq
                r.cache.extended[48].store(1300, Ordering::Release); // max_freq
                r.cache.extended[49].store(4, Ordering::Release); // gov = OEM dummy
                r.cache.extended[50].store(0, Ordering::Release); // GED boost = off
                r.cache.extended[52].store(0, Ordering::Release); // uncap = 0
                r.cache.extended[59].store(0, Ordering::Release); // power_policy = coarse_demand
            }
        }
    }
    send(Command::Performance(v))
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_open_support_link(v: i32) -> i32 {
    if crate::rodin_host_open_url_jni(v) {
        1
    } else {
        send(Command::OpenLink(v))
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_extended_get(index: i32) -> i32 {
    if index < 0 || index as usize >= EXTENDED_VALUE_COUNT {
        return -1;
    }

    runtime()
        .map(|r| r.cache.extended[index as usize].load(Ordering::Acquire))
        .unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_backend_extended_set(op: i32, a: i32, b: i32) -> i32 {
    send(Command::Extended(op, a, b))
}

pub fn per_app_profile_for_package(package: &str) -> i32 {
    runtime()
        .and_then(|runtime| runtime.cache.perapp_profiles.lock().ok())
        .and_then(|profiles| profiles.get(package).copied())
        .unwrap_or(-1)
}

pub fn set_per_app_package_profile(package: &str, profile: i32) -> i32 {
    if !matches!(profile, -1..=3) {
        return 0;
    }

    send(Command::PerAppPackage(package.to_string(), profile))
}

pub fn last_per_app_package() -> String {
    runtime()
        .and_then(|runtime| runtime.cache.perapp_last_package.lock().ok())
        .map(|package| package.clone())
        .unwrap_or_default()
}
