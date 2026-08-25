use std::collections::BTreeMap;
use std::ffi::c_void;
use std::fs;
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::fd::{FromRawFd, RawFd};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

mod touch_resampler;

pub const SOCKET_NAME: &str = "rodin_essentiald_v13";
pub const PROTOCOL_VERSION: &str = "13.3";

const AF_UNIX: i32 = 1;
const SOCK_STREAM: i32 = 1;
const SOCK_CLOEXEC: i32 = 0x80000;

#[repr(C)]
struct SockAddrUn {
    sun_family: u16,
    sun_path: [i8; 108],
}

unsafe extern "C" {
    fn socket(domain: i32, ty: i32, protocol: i32) -> i32;
    fn bind(fd: i32, addr: *const c_void, len: u32) -> i32;
    fn listen(fd: i32, backlog: i32) -> i32;
    fn accept4(fd: i32, addr: *mut c_void, len: *mut u32, flags: i32) -> i32;
    fn connect(fd: i32, addr: *const c_void, len: u32) -> i32;
    fn close(fd: i32) -> i32;
}

#[cfg(target_os = "android")]
mod vendor_binder {
    use std::ffi::{c_char, c_void};
    use std::ptr;
    use std::sync::OnceLock;

    const STATUS_OK: i32 = 0;

    #[repr(C)]
    pub struct AIBinder {
        _private: [u8; 0],
    }
    #[repr(C)]
    pub struct AIBinder_Class {
        _private: [u8; 0],
    }
    #[repr(C)]
    pub struct AParcel {
        _private: [u8; 0],
    }
    #[repr(C)]
    pub struct AStatus {
        _private: [u8; 0],
    }

    type OnCreate = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
    type OnDestroy = unsafe extern "C" fn(*mut c_void);
    type OnTransact = unsafe extern "C" fn(*mut AIBinder, u32, *const AParcel, *mut AParcel) -> i32;

    #[link(name = "binder_ndk")]
    unsafe extern "C" {
        fn AIBinder_Class_define(
            descriptor: *const c_char,
            on_create: OnCreate,
            on_destroy: OnDestroy,
            on_transact: OnTransact,
        ) -> *mut AIBinder_Class;
        fn AIBinder_associateClass(binder: *mut AIBinder, clazz: *const AIBinder_Class) -> bool;
        fn AIBinder_prepareTransaction(binder: *mut AIBinder, input: *mut *mut AParcel) -> i32;
        fn AIBinder_transact(
            binder: *mut AIBinder,
            code: u32,
            input: *mut *mut AParcel,
            output: *mut *mut AParcel,
            flags: u32,
        ) -> i32;
        fn AIBinder_decStrong(binder: *mut AIBinder);
        fn AParcel_writeInt32(parcel: *mut AParcel, value: i32) -> i32;
        fn AParcel_readInt32(parcel: *const AParcel, value: *mut i32) -> i32;
        fn AParcel_readStatusHeader(parcel: *const AParcel, status: *mut *mut AStatus) -> i32;
        fn AParcel_delete(parcel: *mut AParcel);
        fn AStatus_isOk(status: *const AStatus) -> bool;
        fn AStatus_delete(status: *mut AStatus);
    }

    unsafe extern "C" fn on_create(_: *mut c_void) -> *mut c_void {
        ptr::null_mut()
    }

    unsafe extern "C" fn on_destroy(_: *mut c_void) {}

    unsafe extern "C" fn on_transact(
        _: *mut AIBinder,
        _: u32,
        _: *const AParcel,
        _: *mut AParcel,
    ) -> i32 {
        -38
    }

    const RTLD_NOW: i32 = 2;

    type CheckServiceFn = unsafe extern "C" fn(instance: *const c_char) -> *mut AIBinder;

    #[link(name = "dl")]
    unsafe extern "C" {
        fn dlopen(filename: *const c_char, flags: i32) -> *mut c_void;
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }

    static CHECK_SERVICE_FN: OnceLock<Option<CheckServiceFn>> = OnceLock::new();
    static TOUCH_CLASS: OnceLock<usize> = OnceLock::new();
    static DISPLAY_CLASS: OnceLock<usize> = OnceLock::new();

    fn service_manager_check_service(instance: *const c_char) -> *mut AIBinder {
        let resolved = CHECK_SERVICE_FN.get_or_init(|| unsafe {
            let handle = dlopen(b"libbinder_ndk.so\0".as_ptr().cast(), RTLD_NOW);
            if handle.is_null() {
                return None;
            }

            let set_threads_sym = dlsym(
                handle,
                b"ABinderProcess_setThreadPoolMaxThreadCount\0"
                    .as_ptr()
                    .cast(),
            );
            if !set_threads_sym.is_null() {
                let set_threads: unsafe extern "C" fn(u32) -> bool =
                    std::mem::transmute(set_threads_sym);
                set_threads(4);
            }
            let start_threads_sym =
                dlsym(handle, b"ABinderProcess_startThreadPool\0".as_ptr().cast());
            if !start_threads_sym.is_null() {
                let start_threads: unsafe extern "C" fn() = std::mem::transmute(start_threads_sym);
                start_threads();
            }

            let symbol = dlsym(handle, b"AServiceManager_checkService\0".as_ptr().cast());
            if symbol.is_null() {
                return None;
            }

            Some(std::mem::transmute::<*mut c_void, CheckServiceFn>(symbol))
        });

        match *resolved {
            Some(function) => unsafe { function(instance) },
            None => ptr::null_mut(),
        }
    }

    fn class_for(
        descriptor: &'static [u8],
        slot: &'static OnceLock<usize>,
    ) -> *const AIBinder_Class {
        let raw = *slot.get_or_init(|| unsafe {
            AIBinder_Class_define(
                descriptor.as_ptr().cast(),
                on_create,
                on_destroy,
                on_transact,
            ) as usize
        });
        raw as *const AIBinder_Class
    }

    fn check_service(
        service: &'static [u8],
        descriptor: &'static [u8],
        slot: &'static OnceLock<usize>,
    ) -> Option<*mut AIBinder> {
        let binder = service_manager_check_service(service.as_ptr().cast());
        if binder.is_null() {
            return None;
        }

        let clazz = class_for(descriptor, slot);
        if clazz.is_null() || !unsafe { AIBinder_associateClass(binder, clazz) } {
            unsafe { AIBinder_decStrong(binder) };
            return None;
        }

        Some(binder)
    }

    pub fn touch_available() -> bool {
        const SERVICE: &[u8] = b"vendor.xiaomi.hw.touchfeature.ITouchFeature/default\0";
        const DESCRIPTOR: &[u8] = b"vendor.xiaomi.hw.touchfeature.ITouchFeature\0";
        let Some(binder) = check_service(SERVICE, DESCRIPTOR, &TOUCH_CLASS) else {
            return false;
        };
        unsafe { AIBinder_decStrong(binder) };
        true
    }

    pub fn display_available() -> bool {
        const SERVICE: &[u8] =
            b"vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature/default\0";
        const DESCRIPTOR: &[u8] = b"vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature\0";
        let Some(binder) = check_service(SERVICE, DESCRIPTOR, &DISPLAY_CLASS) else {
            return false;
        };
        unsafe { AIBinder_decStrong(binder) };
        true
    }

    pub fn set_touch_mode(display_id: i32, mode: i32, value: i32) -> bool {
        const SERVICE: &[u8] = b"vendor.xiaomi.hw.touchfeature.ITouchFeature/default\0";
        const DESCRIPTOR: &[u8] = b"vendor.xiaomi.hw.touchfeature.ITouchFeature\0";
        let Some(binder) = check_service(SERVICE, DESCRIPTOR, &TOUCH_CLASS) else {
            return false;
        };

        let mut input: *mut AParcel = ptr::null_mut();
        let mut output: *mut AParcel = ptr::null_mut();
        let mut ok = unsafe { AIBinder_prepareTransaction(binder, &mut input) } == STATUS_OK;

        if ok {
            ok &= unsafe { AParcel_writeInt32(input, display_id) } == STATUS_OK;
            ok &= unsafe { AParcel_writeInt32(input, mode) } == STATUS_OK;
            ok &= unsafe { AParcel_writeInt32(input, value) } == STATUS_OK;
        }

        if ok {
            ok &= unsafe { AIBinder_transact(binder, 9, &mut input, &mut output, 0) } == STATUS_OK;
        } else if !input.is_null() {
            unsafe { AParcel_delete(input) };
        }

        if ok && !output.is_null() {
            let mut result = -1i32;
            ok &= unsafe { AParcel_readInt32(output, &mut result) } == STATUS_OK;
            ok &= result == 0;
        } else {
            ok = false;
        }

        if !output.is_null() {
            unsafe { AParcel_delete(output) };
        }
        unsafe { AIBinder_decStrong(binder) };
        ok
    }

    pub fn set_display_feature(case_id: i32, mode_id: i32, cookie: i32) -> bool {
        const SERVICE: &[u8] =
            b"vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature/default\0";
        const DESCRIPTOR: &[u8] = b"vendor.xiaomi.hardware.displayfeature_aidl.IDisplayFeature\0";
        let Some(binder) = check_service(SERVICE, DESCRIPTOR, &DISPLAY_CLASS) else {
            return false;
        };

        let mut input: *mut AParcel = ptr::null_mut();
        let mut output: *mut AParcel = ptr::null_mut();
        let mut ok = unsafe { AIBinder_prepareTransaction(binder, &mut input) } == STATUS_OK;

        for value in [0, case_id, mode_id, cookie] {
            if ok {
                ok &= unsafe { AParcel_writeInt32(input, value) } == STATUS_OK;
            }
        }

        if ok {
            ok &= unsafe { AIBinder_transact(binder, 7, &mut input, &mut output, 0) } == STATUS_OK;
        } else if !input.is_null() {
            unsafe { AParcel_delete(input) };
        }

        if ok && !output.is_null() {
            let mut status: *mut AStatus = ptr::null_mut();
            ok &= unsafe { AParcel_readStatusHeader(output, &mut status) } == STATUS_OK;
            if !status.is_null() {
                ok &= unsafe { AStatus_isOk(status) };
                unsafe { AStatus_delete(status) };
            } else {
                ok = false;
            }
        } else {
            ok = false;
        }

        if !output.is_null() {
            unsafe { AParcel_delete(output) };
        }
        unsafe { AIBinder_decStrong(binder) };
        ok
    }
}

#[cfg(not(target_os = "android"))]
mod vendor_binder {
    pub fn touch_available() -> bool {
        false
    }
    pub fn display_available() -> bool {
        false
    }
    pub fn set_touch_mode(_: i32, _: i32, _: i32) -> bool {
        false
    }
    pub fn set_display_feature(_: i32, _: i32, _: i32) -> bool {
        false
    }
}

static TOUCH_STATE: AtomicI32 = AtomicI32::new(-1);
static TOUCH_SUSTAINED_RATE: AtomicI32 = AtomicI32::new(-1);
static TOUCH_INSTANT_RATE: AtomicI32 = AtomicI32::new(-1);
static TOUCH_PANEL: AtomicI32 = AtomicI32::new(0);
static TOUCH_CONTROL_PATH: AtomicI32 = AtomicI32::new(0);
static DISPLAY_COLOR_STATE: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_TEMP_STATE: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_SUNLIGHT_STATE: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_SILKY_STATE: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_VIDEO_STATE: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_DOLBY_STATE: AtomicI32 = AtomicI32::new(-1);
static PERFORMANCE_STATE: AtomicI32 = AtomicI32::new(-1);

fn abstract_addr(name: &str) -> Result<(SockAddrUn, u32), String> {
    let bytes = name.as_bytes();
    if bytes.len() + 1 >= 108 {
        return Err("socket name too long".into());
    }

    let mut addr = SockAddrUn {
        sun_family: AF_UNIX as u16,
        sun_path: [0; 108],
    };
    addr.sun_path[0] = 0;
    for (i, b) in bytes.iter().enumerate() {
        addr.sun_path[i + 1] = *b as i8;
    }
    Ok((addr, (2 + 1 + bytes.len()) as u32))
}

pub fn bind_listener(name: &str) -> Result<RawFd, String> {
    let (addr, len) = abstract_addr(name)?;
    let fd = unsafe { socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(format!(
            "socket failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { bind(fd, &addr as *const _ as *const c_void, len) } != 0 {
        let e = std::io::Error::last_os_error();
        unsafe { close(fd) };
        return Err(format!("bind failed: {e}"));
    }
    if unsafe { listen(fd, 16) } != 0 {
        let e = std::io::Error::last_os_error();
        unsafe { close(fd) };
        return Err(format!("listen failed: {e}"));
    }
    Ok(fd)
}

pub fn accept_stream(listener: RawFd) -> Result<UnixStream, String> {
    let fd = unsafe {
        accept4(
            listener,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            SOCK_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(format!(
            "accept failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(unsafe { UnixStream::from_raw_fd(fd) })
}

pub fn connect_stream(name: &str) -> Result<UnixStream, String> {
    let (addr, len) = abstract_addr(name)?;
    let fd = unsafe { socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(format!(
            "socket failed: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { connect(fd, &addr as *const _ as *const c_void, len) } != 0 {
        let e = std::io::Error::last_os_error();
        unsafe { close(fd) };
        return Err(format!("connect failed: {e}"));
    }
    Ok(unsafe { UnixStream::from_raw_fd(fd) })
}

fn read_trimmed<P: AsRef<Path>>(path: P) -> Result<String, String> {
    fs::read_to_string(path.as_ref())
        .map(|s| s.trim().to_string())
        .map_err(|e| format!("read {}: {e}", path.as_ref().display()))
}

fn write_verified(path: &Path, value: &str) -> Result<String, String> {
    fs::write(path, format!("{value}\n")).map_err(|e| format!("write {}: {e}", path.display()))?;
    read_trimmed(path)
}

fn charging_path() -> PathBuf {
    PathBuf::from("/sys/class/power_supply/usb/sic_mode")
}

fn battery(name: &str) -> String {
    read_trimmed(format!("/sys/class/power_supply/battery/{name}"))
        .unwrap_or_else(|_| "NA".to_string())
}

fn usb(name: &str) -> String {
    read_trimmed(format!("/sys/class/power_supply/usb/{name}")).unwrap_or_else(|_| "NA".to_string())
}

fn sanitize(value: String) -> String {
    value.replace(';', ",").replace(['\n', '\r'], " ")
}

fn read_cpu_online_mask_string() -> String {
    read_trimmed("/sys/devices/system/cpu/online").unwrap_or_else(|_| "NA".into())
}

fn live_cpu_mask() -> i32 {
    let mut mask = 0x01;

    for cpu in 1..=7 {
        let path = format!("/sys/devices/system/cpu/cpu{cpu}/online");

        if read_trimmed(&path)
            .map(|value| value == "1")
            .unwrap_or(false)
        {
            mask |= 1 << cpu;
        }
    }

    mask
}

fn core_ctl_paths() -> Vec<PathBuf> {
    let mut paths = Vec::<PathBuf>::new();

    for cpu in 0..=7 {
        let path = PathBuf::from(format!("/sys/devices/system/cpu/cpu{cpu}/core_ctl/enable"));

        if path.exists() && !paths.contains(&path) {
            paths.push(path);
        }
    }

    for policy in [0, 4, 7] {
        let path = PathBuf::from(format!(
            "/sys/devices/system/cpu/cpufreq/policy{policy}/core_ctl/enable"
        ));

        if path.exists() && !paths.contains(&path) {
            paths.push(path);
        }
    }

    let global = PathBuf::from("/sys/devices/system/cpu/core_ctl/enable");

    if global.exists() && !paths.contains(&global) {
        paths.push(global);
    }

    paths
}

fn set_core_ctl_enabled(enabled: bool) -> Result<usize, String> {
    let paths = core_ctl_paths();

    CORE_CTL_NODE_COUNT.store(paths.len() as i32, Ordering::Release);

    let desired = if enabled { "1" } else { "0" };

    for path in &paths {
        let actual = write_verified(path, desired)?;

        if actual != desired {
            return Err(format!("core_ctl verify {}={actual}", path.display()));
        }
    }

    Ok(paths.len())
}

fn write_cpu_online(cpu: usize, online: bool) -> Result<(), String> {
    if !(1..=7).contains(&cpu) {
        return Err("CPU0 is pinned online; valid manual cores are CPU1-CPU7".into());
    }

    let path = PathBuf::from(format!("/sys/devices/system/cpu/cpu{cpu}/online"));

    if !path.exists() {
        return Err(format!("CPU{cpu} online node missing"));
    }

    let desired = if online { "1" } else { "0" };
    let actual = write_verified(&path, desired)?;

    if actual != desired {
        return Err(format!(
            "CPU{cpu} online verify expected={desired} actual={actual}"
        ));
    }

    Ok(())
}

fn apply_saved_cpu_mask(mask: i32) -> Result<(), String> {
    let mask = (mask | 0x01) & 0xFF;

    for cpu in 1..=7 {
        if (mask & (1 << cpu)) != 0 {
            write_cpu_online(cpu, true)?;
        }
    }

    for cpu in 1..=7 {
        if (mask & (1 << cpu)) == 0 {
            write_cpu_online(cpu, false)?;
        }
    }

    let actual = live_cpu_mask();

    if actual != mask {
        return Err(format!(
            "CPU online mask verify expected=0x{mask:02x} actual=0x{actual:02x}"
        ));
    }

    Ok(())
}

fn set_cpu_manual(enabled: bool) -> Result<(), String> {
    CPU_WRITE_ACK.store(-1, Ordering::Release);

    let result = (|| -> Result<(), String> {
        if enabled {
            let _ = set_core_ctl_enabled(false)?;
            let current = live_cpu_mask();

            mutate_persisted_state(|state| {
                state.cpu_manual = 1;
                state.cpu_online_mask = current | 0x01;
            });
        } else {
            apply_saved_cpu_mask(0xFF)?;
            let _ = set_core_ctl_enabled(true)?;

            mutate_persisted_state(|state| {
                state.cpu_manual = 0;
                state.cpu_online_mask = 0xFF;
            });
        }

        Ok(())
    })();

    CPU_WRITE_ACK.store(if result.is_ok() { 1 } else { 0 }, Ordering::Release);

    result
}

fn set_cpu_core(cpu: usize, online: bool) -> Result<(), String> {
    let manual = persisted_state()
        .lock()
        .ok()
        .map(|state| state.cpu_manual == 1)
        .unwrap_or(false);

    if !manual {
        CPU_WRITE_ACK.store(0, Ordering::Release);
        return Err("manual CPU core control is disabled".into());
    }

    CPU_WRITE_ACK.store(-1, Ordering::Release);

    match write_cpu_online(cpu, online) {
        Ok(()) => {
            let mask = live_cpu_mask();

            mutate_persisted_state(|state| {
                state.cpu_online_mask = mask | 0x01;
            });

            CPU_WRITE_ACK.store(1, Ordering::Release);
            Ok(())
        }
        Err(error) => {
            CPU_WRITE_ACK.store(0, Ordering::Release);
            Err(error)
        }
    }
}

fn restore_cpu_state() {
    let state = persisted_state()
        .lock()
        .ok()
        .map(|state| state.clone())
        .unwrap_or_default();

    if state.cpu_manual == 1 {
        let result =
            set_core_ctl_enabled(false).and_then(|_| apply_saved_cpu_mask(state.cpu_online_mask));

        CPU_WRITE_ACK.store(if result.is_ok() { 1 } else { 0 }, Ordering::Release);
    } else {
        let result = apply_saved_cpu_mask(0xFF).and_then(|_| set_core_ctl_enabled(true));

        CPU_WRITE_ACK.store(if result.is_ok() { 1 } else { 0 }, Ordering::Release);

        if result.is_ok() {
            mutate_persisted_state(|state| {
                state.cpu_manual = 0;
                state.cpu_online_mask = 0xFF;
            });
        }
    }
}

fn cpu_freq(cpu: usize) -> String {
    let candidates = [
        format!("/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq"),
        format!("/sys/devices/system/cpu/cpu{cpu}/cpufreq/cpuinfo_cur_freq"),
    ];
    for p in candidates {
        if let Ok(v) = read_trimmed(&p) {
            return v;
        }
    }
    "NA".into()
}

fn policy_governor(policy: i32) -> String {
    read_trimmed(format!(
        "/sys/devices/system/cpu/cpufreq/policy{policy}/scaling_governor"
    ))
    .unwrap_or_else(|_| "unknown".into())
}

fn gpu_governor() -> String {
    read_trimmed("/sys/class/devfreq/13000000.mali/governor").unwrap_or_else(|_| "unknown".into())
}

fn scheduler_name(path: &Path) -> Option<String> {
    let raw = read_trimmed(path).ok()?;
    if let (Some(a), Some(b)) = (raw.find('['), raw.find(']'))
        && b > a + 1
    {
        return Some(raw[a + 1..b].to_string());
    }
    None
}

fn ufs_scheduler_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    let Ok(entries) = fs::read_dir("/sys/block") else {
        return paths;
    };

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.starts_with("sd") {
            continue;
        }

        let device = entry.path().join("device");
        let is_ufs = fs::canonicalize(&device)
            .ok()
            .map(|path| path.to_string_lossy().contains("ufshci"))
            .unwrap_or(false);
        if !is_ufs {
            continue;
        }

        let scheduler = entry.path().join("queue/scheduler");
        if scheduler.is_file() {
            paths.push(scheduler);
        }
    }

    paths.sort();
    paths
}

fn io_scheduler() -> String {
    let mut active: Option<String> = None;
    for path in ufs_scheduler_paths() {
        let Some(current) = scheduler_name(&path) else {
            return "unknown".into();
        };
        if active.as_ref().is_some_and(|value| value != &current) {
            return "mixed".into();
        }
        active = Some(current);
    }
    active.unwrap_or_else(|| "unknown".into())
}

fn list_contains(path: &str, target: &str) -> bool {
    read_trimmed(path)
        .map(|v| {
            v.split_whitespace()
                .map(|x| x.trim_matches(&['[', ']'][..]))
                .any(|x| x == target)
        })
        .unwrap_or(false)
}

fn set_cpu_governor(policy: i32, governor: &str) -> Result<(), String> {
    const SAFE: &[&str] = &[
        "sugov_ext",
        "conservative",
        "powersave",
        "performance",
        "schedutil",
    ];
    if !matches!(policy, 0 | 4 | 7) || !SAFE.contains(&governor) {
        return Err("invalid cpu governor request".into());
    }
    let base = format!("/sys/devices/system/cpu/cpufreq/policy{policy}");
    let available = format!("{base}/scaling_available_governors");
    if !list_contains(&available, governor) {
        return Err(format!(
            "governor {governor} not available for policy{policy}"
        ));
    }
    let path = PathBuf::from(format!("{base}/scaling_governor"));
    let actual = write_verified(&path, governor)?;
    if actual == governor {
        Ok(())
    } else {
        Err(format!("cpu governor verify {actual}"))
    }
}

fn cpu_policy_default_range(policy: i32) -> Option<(i32, i32)> {
    match policy {
        0 => Some((300, 2100)),
        4 => Some((400, 3000)),
        7 => Some((1000, 3250)),
        _ => None,
    }
}

fn parse_cpu_frequency_table(raw: &str) -> Vec<i32> {
    let mut frequencies = raw
        .split_whitespace()
        .filter_map(|value| value.parse::<i64>().ok())
        .filter(|khz| *khz > 0 && *khz % 1_000 == 0)
        .map(|khz| (khz / 1_000) as i32)
        .collect::<Vec<_>>();
    frequencies.sort_unstable();
    frequencies.dedup();
    frequencies
}

fn parse_cpu_time_in_state(raw: &str) -> Vec<i32> {
    let mut frequencies = raw
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .filter_map(|value| value.parse::<i64>().ok())
        .filter(|khz| *khz > 0 && *khz % 1_000 == 0)
        .map(|khz| (khz / 1_000) as i32)
        .collect::<Vec<_>>();
    frequencies.sort_unstable();
    frequencies.dedup();
    frequencies
}

fn cpu_available_frequencies(policy: i32) -> Vec<i32> {
    if !matches!(policy, 0 | 4 | 7) {
        return Vec::new();
    }

    let available = read_trimmed(format!(
        "/sys/devices/system/cpu/cpufreq/policy{policy}/scaling_available_frequencies"
    ))
    .map(|raw| parse_cpu_frequency_table(&raw))
    .unwrap_or_default();
    if !available.is_empty() {
        return available;
    }

    read_trimmed(format!(
        "/sys/devices/system/cpu/cpufreq/policy{policy}/stats/time_in_state"
    ))
    .map(|raw| parse_cpu_time_in_state(&raw))
    .unwrap_or_default()
}

fn cpu_frequency_table_csv(policy: i32) -> String {
    cpu_available_frequencies(policy)
        .iter()
        .map(i32::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

fn read_cpu_cluster_limit(policy: i32, node: &str) -> Result<i32, String> {
    read_trimmed(format!(
        "/sys/devices/system/cpu/cpufreq/policy{policy}/{node}"
    ))
    .map_err(|error| format!("policy{policy} {node} read: {error}"))?
    .parse::<i64>()
    .map_err(|error| format!("policy{policy} {node} parse: {error}"))
    .and_then(|khz| {
        let mhz = (khz / 1_000) as i32;
        if mhz > 0 {
            Ok(mhz)
        } else {
            Err(format!("policy{policy} {node} reported {khz} kHz"))
        }
    })
}

fn get_cpu_cluster_live_limit(policy: i32, node: &str, fallback: i32) -> i32 {
    read_cpu_cluster_limit(policy, node).unwrap_or(fallback)
}

fn get_cpu_cluster_live_min_freq(policy: i32) -> i32 {
    let fallback = cpu_policy_default_range(policy)
        .map(|range| range.0)
        .unwrap_or(0);
    get_cpu_cluster_live_limit(policy, "scaling_min_freq", fallback)
}

fn get_cpu_cluster_live_max_freq(policy: i32) -> i32 {
    let fallback = cpu_policy_default_range(policy)
        .map(|range| range.1)
        .unwrap_or(0);
    get_cpu_cluster_live_limit(policy, "scaling_max_freq", fallback)
}

fn persisted_cpu_range(state: &PersistedState, policy: i32) -> Option<(i32, i32)> {
    let range = match policy {
        0 => (state.cpu_min_freq0, state.cpu_max_freq0),
        4 => (state.cpu_min_freq4, state.cpu_max_freq4),
        7 => (state.cpu_min_freq7, state.cpu_max_freq7),
        _ => return None,
    };

    (range.0 > 0 && range.1 > 0).then_some(range)
}

fn effective_cpu_target_range(state: &PersistedState, policy: i32) -> (i32, i32) {
    persisted_cpu_range(state, policy).unwrap_or_else(|| {
        let defaults = cpu_policy_default_range(policy).unwrap_or((0, 0));
        (
            get_cpu_cluster_live_limit(policy, "scaling_min_freq", defaults.0),
            get_cpu_cluster_live_limit(policy, "scaling_max_freq", defaults.1),
        )
    })
}

fn validate_cpu_frequency_range_against(
    policy: i32,
    min_mhz: i32,
    max_mhz: i32,
    available: &[i32],
) -> Result<(), String> {
    if !matches!(policy, 0 | 4 | 7) || min_mhz <= 0 || max_mhz <= 0 {
        return Err("invalid cpu frequency range".into());
    }
    if min_mhz > max_mhz {
        return Err("cpu minimum frequency exceeds maximum".into());
    }

    if available.is_empty() {
        return Err(format!("policy{policy} frequency table unavailable"));
    }
    if !available.contains(&min_mhz) {
        return Err(format!(
            "{min_mhz} MHz is not a supported policy{policy} frequency"
        ));
    }
    if !available.contains(&max_mhz) {
        return Err(format!(
            "{max_mhz} MHz is not a supported policy{policy} frequency"
        ));
    }

    Ok(())
}

fn validate_cpu_frequency_range(policy: i32, min_mhz: i32, max_mhz: i32) -> Result<(), String> {
    let available = cpu_available_frequencies(policy);
    validate_cpu_frequency_range_against(policy, min_mhz, max_mhz, &available)
}

const MI_THERMAL_CPU_LIMITS: &str = "/sys/devices/virtual/thermal/thermal_message/cpu_limits";
const MTK_POWERHAL_CPU_FREQ: &str = "/proc/powerhal_cpu_ctrl/perfserv_freq";

static CPU_FREQ_APPLY_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn cpu_freq_apply_lock() -> &'static Mutex<()> {
    CPU_FREQ_APPLY_LOCK.get_or_init(|| Mutex::new(()))
}

fn mi_thermal_cpu_limit_request(policy: i32, max_mhz: i32) -> String {
    format!("cpu{policy} {}", max_mhz as i64 * 1_000)
}

fn mtk_powerhal_cpu_range_request(policy: i32, min_mhz: i32, max_mhz: i32) -> String {
    format!(
        "{policy} {} {}",
        min_mhz as i64 * 1_000,
        max_mhz as i64 * 1_000
    )
}

fn write_optional_cpu_control(path: &str, value: &str, label: &str) -> Result<(), String> {
    if !Path::new(path).exists() {
        return Ok(());
    }

    fs::write(path, value).map_err(|error| format!("{label} write: {error}"))
}

fn apply_cluster_freq_controls_unlocked(
    policy: i32,
    min_mhz: i32,
    max_mhz: i32,
) -> Result<(), String> {
    validate_cpu_frequency_range(policy, min_mhz, max_mhz)?;

    let min_khz = min_mhz as i64 * 1_000;
    let max_khz = max_mhz as i64 * 1_000;
    let path_min = format!("/sys/devices/system/cpu/cpufreq/policy{policy}/scaling_min_freq");
    let path_max = format!("/sys/devices/system/cpu/cpufreq/policy{policy}/scaling_max_freq");

    let write_min = || {
        fs::write(&path_min, format!("{min_khz}\n"))
            .map_err(|error| format!("policy{policy} minimum write: {error}"))
    };
    let write_max = || {
        fs::write(&path_max, format!("{max_khz}\n"))
            .map_err(|error| format!("policy{policy} maximum write: {error}"))
    };

    let write_vendor_constraints = || {
        // Xiaomi's live Rodin thermal daemon writes this request directly.
        // Updating the same per-policy request prevents its ceiling from
        // silently clamping a user-selected range below the requested OPP.
        write_optional_cpu_control(
            MI_THERMAL_CPU_LIMITS,
            &mi_thermal_cpu_limit_request(policy, max_mhz),
            "MI thermal CPU limit",
        )?;

        // MT6899 accepts one policy leader plus its minimum and maximum in
        // kHz. This updates only the selected policy; it does not replace the
        // frequency table for either of the other CPU clusters.
        write_optional_cpu_control(
            MTK_POWERHAL_CPU_FREQ,
            &mtk_powerhal_cpu_range_request(policy, min_mhz, max_mhz),
            "MediaTek PowerHAL CPU range",
        )
    };

    let mut actual_min = get_cpu_cluster_live_min_freq(policy);
    let mut actual_max = get_cpu_cluster_live_max_freq(policy);
    for attempt in 0..4 {
        write_vendor_constraints()?;

        // Choose the write order that keeps every intermediate range valid.
        if min_mhz > actual_max {
            write_max()?;
            write_min()?;
        } else if max_mhz < actual_min {
            write_min()?;
            write_max()?;
        } else {
            write_max()?;
            write_min()?;
        }

        // cpufreq writes are synchronous on Rodin, but a short bounded retry
        // also handles vendor policy activity occurring in the same instant.
        std::thread::sleep(Duration::from_millis(if attempt == 0 { 5 } else { 20 }));
        actual_min = read_cpu_cluster_limit(policy, "scaling_min_freq")?;
        actual_max = read_cpu_cluster_limit(policy, "scaling_max_freq")?;

        if actual_min == min_mhz && actual_max == max_mhz {
            return Ok(());
        }
    }

    Err(format!(
        "policy{policy} frequency verify requested {min_mhz}-{max_mhz} MHz, live {actual_min}-{actual_max} MHz"
    ))
}

fn apply_cluster_freq_controls(policy: i32, min_mhz: i32, max_mhz: i32) -> Result<(), String> {
    let _guard = cpu_freq_apply_lock()
        .lock()
        .map_err(|_| "CPU frequency apply lock poisoned".to_string())?;
    apply_cluster_freq_controls_unlocked(policy, min_mhz, max_mhz)
}

fn set_cpu_cluster_min_freq(policy: i32, mhz: i32) -> Result<(), String> {
    let state = persisted_state()
        .lock()
        .ok()
        .map(|state| state.clone())
        .unwrap_or_default();
    let (_, current_max) = effective_cpu_target_range(&state, policy);
    set_cpu_cluster_freq_range(policy, mhz, current_max.max(mhz))
}

fn set_cpu_cluster_max_freq(policy: i32, mhz: i32) -> Result<(), String> {
    let state = persisted_state()
        .lock()
        .ok()
        .map(|state| state.clone())
        .unwrap_or_default();
    let (current_min, _) = effective_cpu_target_range(&state, policy);
    set_cpu_cluster_freq_range(policy, current_min.min(mhz), mhz)
}

fn set_cpu_cluster_freq_range(policy: i32, min_mhz: i32, max_mhz: i32) -> Result<(), String> {
    CPU_FREQ_WRITE_ACK.store(-1, Ordering::Release);
    let guard = cpu_freq_apply_lock()
        .lock()
        .map_err(|_| "CPU frequency apply lock poisoned".to_string());
    let result = match guard {
        Ok(_guard) => {
            let result = apply_cluster_freq_controls_unlocked(policy, min_mhz, max_mhz);
            if result.is_ok() {
                mutate_persisted_state(|state| match policy {
                    0 => {
                        state.cpu_min_freq0 = min_mhz;
                        state.cpu_max_freq0 = max_mhz;
                    }
                    4 => {
                        state.cpu_min_freq4 = min_mhz;
                        state.cpu_max_freq4 = max_mhz;
                    }
                    7 => {
                        state.cpu_min_freq7 = min_mhz;
                        state.cpu_max_freq7 = max_mhz;
                    }
                    _ => {}
                });
            }
            result
        }
        Err(error) => Err(error),
    };

    CPU_FREQ_WRITE_ACK.store(if result.is_ok() { 1 } else { 0 }, Ordering::Release);
    result
}

fn reset_cpu_cluster_freq_range(policy: i32) -> Result<(), String> {
    CPU_FREQ_WRITE_ACK.store(-1, Ordering::Release);
    let available = cpu_available_frequencies(policy);
    let Some((&min_mhz, &max_mhz)) = available.first().zip(available.last()) else {
        CPU_FREQ_WRITE_ACK.store(0, Ordering::Release);
        return Err(format!("policy{policy} frequency table unavailable"));
    };

    let guard = cpu_freq_apply_lock()
        .lock()
        .map_err(|_| "CPU frequency apply lock poisoned".to_string());
    let result = match guard {
        Ok(_guard) => {
            let result = apply_cluster_freq_controls_unlocked(policy, min_mhz, max_mhz);
            if result.is_ok() {
                mutate_persisted_state(|state| match policy {
                    0 => {
                        state.cpu_min_freq0 = -1;
                        state.cpu_max_freq0 = -1;
                    }
                    4 => {
                        state.cpu_min_freq4 = -1;
                        state.cpu_max_freq4 = -1;
                    }
                    7 => {
                        state.cpu_min_freq7 = -1;
                        state.cpu_max_freq7 = -1;
                    }
                    _ => {}
                });
            }
            result
        }
        Err(error) => Err(error),
    };

    CPU_FREQ_WRITE_ACK.store(if result.is_ok() { 1 } else { 0 }, Ordering::Release);
    result
}

fn set_gpu_governor(governor: &str) -> Result<(), String> {
    const SAFE: &[&str] = &[
        "dummy",
        "powersave",
        "performance",
        "simple_ondemand",
        "userspace",
    ];
    if !SAFE.contains(&governor) {
        return Err("invalid gpu governor request".into());
    }
    let path = Path::new("/sys/class/misc/mali0/device/devfreq/13000000.mali/governor");
    let actual = write_verified(path, governor)?;
    if actual == governor {
        mutate_persisted_state(|state| {
            state.gpu = governor.to_string();
            state.gpu_governor = governor.to_string();
        });
        Ok(())
    } else {
        Err(format!("gpu governor verify {actual}"))
    }
}

fn set_io_scheduler(scheduler: &str) -> Result<(), String> {
    const SAFE: &[&str] = &["none", "mq-deadline", "kyber", "bfq"];
    if !SAFE.contains(&scheduler) {
        return Err("invalid io scheduler request".into());
    }

    let paths = ufs_scheduler_paths();
    if paths.is_empty() {
        return Err("no UFS scheduler nodes detected".into());
    }

    for path in &paths {
        if !list_contains(path.to_string_lossy().as_ref(), scheduler) {
            return Err(format!(
                "scheduler {scheduler} not available on {}",
                path.display()
            ));
        }
    }

    for path in &paths {
        fs::write(path, format!("{scheduler}\n"))
            .map_err(|error| format!("write {}: {error}", path.display()))?;
        let actual = scheduler_name(path).unwrap_or_else(|| "unknown".into());
        if actual != scheduler {
            return Err(format!(
                "scheduler verify {} expected {scheduler}, read {actual}",
                path.display()
            ));
        }
    }

    Ok(())
}

#[allow(dead_code)]
fn write_if_present(path: &str, value: &str) -> Result<bool, String> {
    let p = Path::new(path);
    if !p.exists() {
        return Ok(false);
    }
    fs::write(p, format!("{value}\n")).map_err(|e| format!("write {path}: {e}"))?;
    Ok(true)
}

fn ensure_vendor_thermal_services_running() {
    let _ = ProcessCommand::new("/system/bin/chmod")
        .args(["0644", "/sys/class/thermal/cooling_device3/cur_state"])
        .output();
    let _ = ProcessCommand::new("/system/bin/start")
        .arg("vendor.thermal-mediatek")
        .output();
    let _ = ProcessCommand::new("/system/bin/start")
        .arg("mi_thermald")
        .output();
    let _ = ProcessCommand::new("/system/bin/start")
        .arg("thermald")
        .output();
    let _ = ProcessCommand::new("/system/bin/start").arg("frs").output();
}

fn clear_gpu_cooling_cap() {
    let _ = ProcessCommand::new("/system/bin/chmod")
        .args(["0644", "/sys/class/thermal/cooling_device3/cur_state"])
        .output();
    let _ = fs::write("/sys/class/thermal/cooling_device3/cur_state", "0");
}

fn profile_uses_ged_boost(profile: i32) -> bool {
    matches!(profile, 1 | 3)
}

fn write_beast_gpu_constraints() {
    let _ = fs::write("/sys/class/misc/mali0/device/power_policy", "always_on");
    let _ = fs::write("/sys/kernel/ged/hal/gpu_boost_level", "2");
    let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", "1");
    let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", "1");
    let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", "1");
    let _ = fs::write("/sys/kernel/ged/hal/custom_upbound_gpu_freq", "0");
    let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "0");
    let _ = fs::write("/sys/module/ged/parameters/gpu_bottom_freq", "1300000");
    let _ = fs::write("/sys/module/ged/parameters/gpu_cust_boost_freq", "1300000");
    let _ = fs::write(
        "/sys/module/ged/parameters/gpu_cust_upbound_freq",
        "1300000",
    );
    gpu_write_file(
        "/sys/class/devfreq/13000000.mali/max_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
        "1300000000",
    );
    gpu_write_file(
        "/sys/class/devfreq/13000000.mali/min_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
        "1300000000",
    );
    gpu_write_file(
        "/sys/class/devfreq/13000000.mali/governor",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
        "performance",
    );
}

// Beast must never disable DVFS while the GPU is still running a previous
// OPP. This is especially important during boot: the MediaTek power service
// can publish its stock OPP 40 target after sys.boot_completed, and freezing
// DVFS at that point leaves the GPU stuck below 1300 MHz until the UI submits
// another profile command. Keep DVFS enabled while arming OPP 0, and disable
// it only after the live GED frequency confirms 1300 MHz.
fn arm_or_lock_beast_gpu() -> bool {
    write_beast_gpu_constraints();

    if gpu_get_cur_freq_mhz() != 1300 {
        let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
        let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "0");
        return false;
    }

    let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "0");
    gpu_get_cur_freq_mhz() == 1300 && gpu_get_dvfs_enabled() == 0
}

fn settle_beast_gpu_lock(attempts: usize, delay: Duration) -> bool {
    let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");

    for _ in 0..attempts {
        if arm_or_lock_beast_gpu() {
            return true;
        }
        std::thread::sleep(delay);
    }

    // Leaving DVFS enabled is intentional. The background guard will lock it
    // as soon as the GPU becomes active and GED reports OPP 0; disabling it
    // here would preserve whichever lower boot OPP happened to be current.
    let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
    false
}

pub fn enforce_performance_profile(profile: i32) -> bool {
    if matches!(profile, 1 | 3) {
        clear_gpu_cooling_cap();
    }

    match profile {
        3 => {
            // Extreme Beast: fixed 1300 MHz OPP with the GPU cooling cap
            // explicitly disabled for this unrestricted profile.
            let _ = settle_beast_gpu_lock(60, Duration::from_millis(25));
        }
        1 => {
            // Gaming Dynamic: the complete hardware OPP table under the
            // load-based governor, with GED and zero-latency power enabled.
            let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/max_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
                "1300000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/min_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
                "260000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/governor",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
                "simple_ondemand",
            );
            let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "40");
            let _ = fs::write("/sys/kernel/ged/hal/custom_upbound_gpu_freq", "0");
            let _ = fs::write("/sys/module/ged/parameters/gpu_bottom_freq", "260000");
            let _ = fs::write("/sys/module/ged/parameters/gpu_cust_boost_freq", "260000");
            let _ = fs::write(
                "/sys/module/ged/parameters/gpu_cust_upbound_freq",
                "1300000",
            );
            let _ = fs::write("/sys/class/misc/mali0/device/power_policy", "always_on");
            let _ = fs::write("/sys/kernel/ged/hal/gpu_boost_level", "1");
            let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", "1");
            let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", "1");
            let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", "1");
        }
        2 => {
            // Battery Saver: lowest governor with a 598 MHz hard ceiling.
            let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/min_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
                "260000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/max_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
                "598000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/governor",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
                "powersave",
            );
            let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "40");
            let _ = fs::write("/sys/kernel/ged/hal/custom_upbound_gpu_freq", "27");
            let _ = fs::write("/sys/module/ged/parameters/gpu_bottom_freq", "260000");
            let _ = fs::write("/sys/module/ged/parameters/gpu_cust_boost_freq", "260000");
            let _ = fs::write("/sys/module/ged/parameters/gpu_cust_upbound_freq", "598000");
            let _ = fs::write("/sys/class/misc/mali0/device/power_policy", "coarse_demand");
            let _ = fs::write("/sys/kernel/ged/hal/gpu_boost_level", "0");
            let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", "0");
            let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", "0");
            let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", "0");
        }
        _ => {
            // Stock Balanced hands DVFS back to the MediaTek power HAL. Rodin's
            // stock governor is `dummy`; the vendor service then owns live caps.
            let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/max_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
                "1300000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/min_freq",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
                "260000000",
            );
            gpu_write_file(
                "/sys/class/devfreq/13000000.mali/governor",
                "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
                "dummy",
            );
            let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "40");
            let _ = fs::write("/sys/kernel/ged/hal/custom_upbound_gpu_freq", "0");
            let _ = fs::write("/sys/module/ged/parameters/gpu_bottom_freq", "260000");
            let _ = fs::write("/sys/module/ged/parameters/gpu_cust_boost_freq", "260000");
            let _ = fs::write(
                "/sys/module/ged/parameters/gpu_cust_upbound_freq",
                "1300000",
            );
            let _ = fs::write("/sys/class/misc/mali0/device/power_policy", "coarse_demand");
            let _ = fs::write("/sys/kernel/ged/hal/gpu_boost_level", "0");
            let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", "0");
            let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", "0");
            let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", "0");
        }
    }

    gpu_profile_verified(profile)
}

pub fn apply_performance_profile(profile: i32) -> Result<(), String> {
    if !matches!(profile, 0..=3) {
        return Err("invalid performance profile".into());
    }

    // A profile transition is one hardware transaction. Exclude the
    // maintenance and dynamic guards so the previous profile cannot win a
    // final write while the new Mali state is being established.
    let _profile_guard = gpu_profile_apply_lock()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());

    let mut verified = enforce_performance_profile(profile);

    PERFORMANCE_STATE.store(profile, Ordering::Release);

    match profile {
        3 => {
            mutate_persisted_state(|state| {
                state.perf = 3;
                state.gpu_uncap = 1;
                state.gpu_min_freq_mhz = 1300;
                state.gpu_max_freq_mhz = 1300;
                state.gpu_ged_boost = 1;
                state.gpu = "performance".to_string();
                state.gpu_governor = "performance".to_string();
                state.gpu_power_policy = "always_on".to_string();
                state.gpu_profile_cpu_isolated = 1;
            });
        }
        1 => {
            mutate_persisted_state(|state| {
                state.perf = 1;
                state.gpu_uncap = 0;
                state.gpu_min_freq_mhz = 260;
                state.gpu_max_freq_mhz = 1300;
                state.gpu_ged_boost = 1;
                state.gpu = "simple_ondemand".to_string();
                state.gpu_governor = "simple_ondemand".to_string();
                state.gpu_power_policy = "always_on".to_string();
                state.gpu_profile_cpu_isolated = 1;
            });
        }
        2 => {
            mutate_persisted_state(|state| {
                state.perf = 2;
                state.gpu_uncap = 0;
                state.gpu_min_freq_mhz = 260;
                state.gpu_max_freq_mhz = 598;
                state.gpu_ged_boost = 0;
                state.gpu = "powersave".to_string();
                state.gpu_governor = "powersave".to_string();
                state.gpu_power_policy = "coarse_demand".to_string();
                state.gpu_profile_cpu_isolated = 1;
            });
        }
        _ => {
            mutate_persisted_state(|state| {
                state.perf = 0;
                state.gpu_uncap = 0;
                state.gpu_min_freq_mhz = 0;
                state.gpu_max_freq_mhz = 0;
                state.gpu_ged_boost = 0;
                state.gpu = "dummy".to_string();
                state.gpu_governor = "dummy".to_string();
                state.gpu_power_policy = "coarse_demand".to_string();
                state.gpu_profile_cpu_isolated = 1;
            });
        }
    }

    // Some vendor GED workers can rewrite a flag while the profile transaction
    // is still settling. Reassert the profile-owned boost state after publishing
    // PERFORMANCE_STATE so callers receive the final verified result rather
    // than a transient false failure.
    for _ in 0..3 {
        if verified {
            break;
        }
        let _ = set_gpu_ged_boost(profile_uses_ged_boost(profile));
        std::thread::sleep(Duration::from_millis(20));
        verified = gpu_profile_verified(profile);
    }

    PERFORMANCE_PROFILE_SUPPORTED.store(1, Ordering::Release);
    PERFORMANCE_PROFILE_VERIFIED.store(1, Ordering::Release);
    PERFORMANCE_PROFILE_OK.store(if verified { 1 } else { 0 }, Ordering::Release);

    if verified || gpu_profile_configured(profile) {
        Ok(())
    } else {
        Err(format!(
            "GPU profile {profile} verify failed: min={} max={} governor={} GED={} policy={}",
            gpu_get_min_freq_mhz(),
            gpu_get_max_freq_mhz(),
            gpu_get_governor(),
            gpu_get_ged_boost(),
            gpu_get_power_policy(),
        ))
    }
}

fn classify_touch_panel_version(version: &str) -> i32 {
    let version = version.to_ascii_lowercase();
    if version.contains("goodix") || version.contains("gdix") || version.contains("gt9916") {
        1
    } else if version.contains("focal") || version.contains("fts") || version.contains("ft3683") {
        2
    } else {
        0
    }
}

fn touch_panel_code() -> i32 {
    let version = fs::read_to_string("/proc/tp_fw_version").unwrap_or_default();
    let detected = classify_touch_panel_version(&version);
    if detected != 0 {
        detected
    } else if Path::new("/sys/devices/platform/goodix_ts.0").exists() {
        1
    } else {
        0
    }
}

#[derive(Clone, Copy, Debug)]
struct TouchThpLayout {
    pid: u32,
    configured_rate_addr: u64,
    current_rate_addr: u64,
}

fn touch_service_pid() -> Option<u32> {
    let entries = fs::read_dir("/proc").ok()?;
    for entry in entries.flatten() {
        let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() else {
            continue;
        };
        let Ok(cmdline) = fs::read(format!("/proc/{pid}/cmdline")) else {
            continue;
        };
        let process_name = cmdline.split(|byte| *byte == 0).next().unwrap_or_default();
        if process_name == b"vendor.xiaomi.hw.touchfeature-service"
            || process_name.ends_with(b"/vendor.xiaomi.hw.touchfeature-service")
        {
            return Some(pid);
        }
    }
    None
}

fn parse_proc_map_range(line: &str) -> Option<(u64, u64, &str, u64)> {
    let mut fields = line.split_whitespace();
    let range = fields.next()?;
    let permissions = fields.next()?;
    let file_offset = u64::from_str_radix(fields.next()?, 16).ok()?;
    let (start, end) = range.split_once('-')?;
    Some((
        u64::from_str_radix(start, 16).ok()?,
        u64::from_str_radix(end, 16).ok()?,
        permissions,
        file_offset,
    ))
}

fn read_u16_from_slice(bytes: &[u8], offset: usize) -> Option<u16> {
    let raw: [u8; 2] = bytes.get(offset..offset + 2)?.try_into().ok()?;
    Some(u16::from_le_bytes(raw))
}

fn find_touch_thp_config_offset(bytes: &[u8]) -> Option<usize> {
    // Both Rodin panel variants use libtouchreport_hal.so and the same THP
    // timing block. Match all three vendor timing pairs instead of relying on
    // one firmware build's absolute virtual address.
    if bytes.len() < 0x38 {
        return None;
    }

    for offset in (0..=bytes.len() - 0x38).step_by(2) {
        let configured_super_rate = read_u16_from_slice(bytes, offset + 0x28)?;
        if read_u16_from_slice(bytes, offset) == Some(135)
            && read_u16_from_slice(bytes, offset + 0x04) == Some(135)
            && read_u16_from_slice(bytes, offset + 0x18) == Some(240)
            && read_u16_from_slice(bytes, offset + 0x1c) == Some(240)
            && read_u16_from_slice(bytes, offset + 0x24) == Some(240)
            && matches!(configured_super_rate, 240 | 480 | 500 | 600 | 650 | 1000)
        {
            return Some(offset);
        }
    }
    None
}

fn locate_touch_thp_layout() -> Result<TouchThpLayout, String> {
    let pid = touch_service_pid().ok_or("Rodin touch service process not found")?;
    let maps = fs::read_to_string(format!("/proc/{pid}/maps"))
        .map_err(|e| format!("touch service maps: {e}"))?;
    let library_base = maps
        .lines()
        .find_map(|line| {
            if !line.contains("libtouchreport_hal.so") {
                return None;
            }
            let (start, _, _, file_offset) = parse_proc_map_range(line)?;
            (file_offset == 0).then_some(start)
        })
        .ok_or("libtouchreport_hal.so is not mapped")?;

    let mut memory = fs::OpenOptions::new()
        .read(true)
        .open(format!("/proc/{pid}/mem"))
        .map_err(|e| format!("touch service memory: {e}"))?;

    for line in maps.lines() {
        let Some((start, end, permissions, _)) = parse_proc_map_range(line) else {
            continue;
        };
        let length = end.saturating_sub(start);
        if !permissions.starts_with("rw")
            || start < library_base
            || start >= library_base.saturating_add(0x10_0000)
            || !(0x38..=0x20_0000).contains(&length)
        {
            continue;
        }

        let mut bytes = vec![0u8; length as usize];
        if memory.seek(SeekFrom::Start(start)).is_err() || memory.read_exact(&mut bytes).is_err() {
            continue;
        }
        if let Some(offset) = find_touch_thp_config_offset(&bytes) {
            let block_addr = start + offset as u64;
            return Ok(TouchThpLayout {
                pid,
                configured_rate_addr: block_addr + 0x28,
                current_rate_addr: block_addr + 0x30,
            });
        }
    }

    Err("Rodin THP timing block not found".into())
}

fn read_touch_thp_rate(layout: TouchThpLayout, address: u64) -> Result<u16, String> {
    let mut memory = fs::OpenOptions::new()
        .read(true)
        .open(format!("/proc/{}/mem", layout.pid))
        .map_err(|e| format!("touch service memory: {e}"))?;
    memory
        .seek(SeekFrom::Start(address))
        .map_err(|e| format!("touch rate seek: {e}"))?;
    let mut raw = [0u8; 2];
    memory
        .read_exact(&mut raw)
        .map_err(|e| format!("touch rate read: {e}"))?;
    Ok(u16::from_le_bytes(raw))
}

fn write_touch_thp_rate(rate: u16) -> Result<TouchThpLayout, String> {
    if !matches!(rate, 240 | 480) {
        return Err(format!("unsupported Rodin THP rate {rate}"));
    }

    let layout = locate_touch_thp_layout()?;
    let mut memory = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(format!("/proc/{}/mem", layout.pid))
        .map_err(|e| format!("touch service memory write: {e}"))?;
    memory
        .seek(SeekFrom::Start(layout.configured_rate_addr))
        .map_err(|e| format!("touch rate seek: {e}"))?;
    memory
        .write_all(&rate.to_le_bytes())
        .map_err(|e| format!("touch rate write: {e}"))?;

    let configured = read_touch_thp_rate(layout, layout.configured_rate_addr)?;
    if configured == rate {
        Ok(layout)
    } else {
        Err(format!(
            "THP configuration verify failed: requested {rate}, read {configured}"
        ))
    }
}

fn touch_profile_locked_rate(profile: i32) -> Option<u16> {
    match profile {
        1 => Some(240),
        2 | 3 => Some(480),
        _ => None,
    }
}

fn touch_profile_rates(profile: i32) -> (i32, i32) {
    match profile {
        1 => (240, 0),  // Native 240 Hz; whole-ms testers show about 250.
        2 => (480, 0),  // Native 480 Hz; whole-ms testers show about 500.
        3 => (1000, 0), // One-millisecond Android output cadence.
        _ => (-1, -1),
    }
}

fn touch_profile_is_live(profile: i32) -> bool {
    let Some(expected_rate) = touch_profile_locked_rate(profile) else {
        return false;
    };
    let native_matches = if vendor_binder::touch_available() {
        locate_touch_thp_layout()
            .and_then(|layout| read_touch_thp_rate(layout, layout.current_rate_addr))
            .map(|rate| rate == expected_rate)
            .unwrap_or(false)
    } else if touch_panel_code() == 1 {
        fs::read_to_string("/sys/devices/platform/goodix_ts.0/switch_report_rate")
            .map(|raw| raw.trim() == if expected_rate == 240 { "0" } else { "1" })
            .unwrap_or(false)
    } else {
        false
    };
    let resampler_matches = if profile == 3 {
        touch_resampler::ready_hz() == 1000
    } else {
        touch_resampler::ready_hz() == 0
    };
    native_matches && resampler_matches
}

fn apply_touch_hal_profile(profile: i32) -> Result<(), String> {
    // These are Xiaomi TouchFeature HAL modes, not calls into the HyperOS
    // Game Turbo application. The HAL lives in Rodin's vendor/ODM stack and
    // abstracts both supported Goodix and FocalTech panels.
    //
    // mode 0: game mode; 1: active mode; 2-6: response calibration;
    // 7: orientation; 202: super report path; 10001-10004: vendor Super Touch.
    // Super-report commands are deliberately last so a subsequent game-mode
    // write cannot return the report pipeline to its 240 Hz base path.
    let sequence: &[(i32, i32, bool)] = match profile {
        0 => &[
            (10001, 0, false),
            (10002, 0, false),
            (10003, 0, false),
            (10004, 0, false),
            (202, 0, true),
            (0, 0, true),
            (1, 0, true),
            (2, 3, false),
            (3, 2, false),
            (4, 2, false),
            (5, 2, false),
            (6, 2, false),
            (7, 0, false),
        ],
        1 | 2 => &[
            (10001, 0, false),
            (10002, 0, false),
            (10003, 0, false),
            (10004, 0, false),
            (0, 1, true),
            (1, 1, true),
            (2, 4, false),
            (3, 4, false),
            (4, 4, false),
            (5, 4, false),
            (6, 0, false),
            (7, 0, false),
            (202, 1, true),
        ],
        3 => &[
            (0, 1, true),
            (1, 1, true),
            (2, 4, false),
            (3, 4, false),
            (4, 4, false),
            (5, 4, false),
            (6, 0, false),
            (7, 0, false),
            (10002, 1, false),
            (10003, 1, false),
            (10004, 2, false),
            (202, 1, true),
            (10001, 1, true),
        ],
        _ => return Err("invalid touch profile".into()),
    };

    let mut failed_required = Vec::new();
    for &(mode, value, required) in sequence {
        if !vendor_binder::set_touch_mode(0, mode, value) && required {
            failed_required.push(mode);
        }
    }

    if failed_required.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "touch HAL rejected required modes {:?}",
            failed_required
        ))
    }
}

fn apply_touch_driver_fallback(profile: i32, panel: i32) -> Result<(), String> {
    // The generic HAL is the all-panel route. This fallback keeps 240/480
    // control available on Goodix-based ported ROMs that omit the HAL service.
    // FocalTech does not expose an equivalent writable report-rate sysfs node.
    if profile == 0 {
        return Ok(());
    }

    if panel != 1 {
        return Err("Rodin TouchFeature HAL unavailable for this panel".into());
    }

    if !matches!(profile, 1 | 2) {
        return Err("this touch profile requires the Rodin vendor touch HAL".into());
    }

    let value = if profile == 1 { "0" } else { "1" };
    fs::write(
        "/sys/devices/platform/goodix_ts.0/switch_report_rate",
        value,
    )
    .map_err(|e| format!("Goodix report-rate fallback: {e}"))
}

fn set_touch_profile(profile: i32) -> Result<(), String> {
    if !(1..=3).contains(&profile) {
        return Err("invalid touch profile".into());
    }

    TOUCH_APPLY_ACK.store(0, Ordering::Release);
    // Stop custom output while the Xiaomi pipeline is being reconfigured.
    // The worker closes only Rodin's duplicated writer; the vendor service and
    // physical touch path continue normally.
    let _ = touch_resampler::set_target_hz(0);
    let panel = touch_panel_code();
    let control_path = if vendor_binder::touch_available() {
        let resampled = profile == 3;
        let vendor_profile = if resampled { 2 } else { profile };
        let locked_rate = touch_profile_locked_rate(profile);
        let layout_and_expected_rate = locked_rate
            .map(write_touch_thp_rate)
            .transpose()?
            .map(|layout| (layout, locked_rate.unwrap_or_default()));
        apply_touch_hal_profile(vendor_profile)?;

        if let Some((layout, expected_rate)) = layout_and_expected_rate {
            let mut actual = 0u16;
            for attempt in 0..3 {
                std::thread::sleep(Duration::from_millis(25));
                actual = read_touch_thp_rate(layout, layout.current_rate_addr)?;
                if actual == expected_rate {
                    break;
                }
                if attempt < 2 {
                    apply_touch_hal_profile(vendor_profile)?;
                }
            }
            if actual != expected_rate {
                return Err(format!(
                    "THP runtime verify failed: requested {expected_rate}, active {actual}"
                ));
            }
        }

        if resampled {
            // Keep the native Xiaomi path at 480 Hz and deliver a precise
            // one-millisecond Android event stream through the same handle.
            touch_resampler::set_target_hz(1000)?;
            3
        } else {
            1
        }
    } else {
        apply_touch_driver_fallback(profile, panel)?;
        2
    };

    let (sustained_rate, instant_rate) = touch_profile_rates(profile);
    let _ = fs::write("/proc/touch_boost/enable", "1");

    TOUCH_STATE.store(profile, Ordering::Release);
    TOUCH_SUSTAINED_RATE.store(sustained_rate, Ordering::Release);
    TOUCH_INSTANT_RATE.store(instant_rate, Ordering::Release);
    TOUCH_PANEL.store(panel, Ordering::Release);
    TOUCH_CONTROL_PATH.store(control_path, Ordering::Release);
    TOUCH_APPLY_ACK.store(1, Ordering::Release);
    mutate_persisted_state(|s| s.touch = profile);
    Ok(())
}

fn set_display_color(mode: i32) -> Result<(), String> {
    let case_id = match mode {
        0 => 2,
        1 => 0,
        2 => 1,
        _ => return Err("invalid display color mode".into()),
    };
    let _ = vendor_binder::set_display_feature(case_id, 2, 255);
    DISPLAY_COLOR_STATE.store(mode, Ordering::Release);
    mutate_persisted_state(|s| s.display_color = mode);
    Ok(())
}

fn set_display_temp(mode: i32) -> Result<(), String> {
    if !matches!(mode, 1..=3) {
        return Err("invalid display temperature".into());
    }
    let _ = vendor_binder::set_display_feature(23, mode, 255);
    DISPLAY_TEMP_STATE.store(mode, Ordering::Release);
    mutate_persisted_state(|s| s.display_temp = mode);
    Ok(())
}

fn set_display_toggle(case_id: i32, enabled: bool, state: &AtomicI32) -> Result<(), String> {
    let val = if enabled { 1 } else { 0 };
    let _ = vendor_binder::set_display_feature(case_id, val, 255);
    state.store(val, Ordering::Release);
    mutate_persisted_state(|s| match case_id {
        57 => s.silky = val,
        27 => s.video = val,
        44 => s.dolby = val,
        _ => {}
    });
    Ok(())
}

fn open_support_link(code: i32) -> Result<(), String> {
    let url = match code {
        0 => "https://github.com/NEESCHAL-3",
        1 => "https://t.me/PocoX7ProNepalChat",
        _ => return Err("invalid support link".into()),
    };
    let status = std::process::Command::new("/system/bin/cmd")
        .env("PATH", "/system/bin:/system/xbin")
        .args(["activity", "start", "--user", "0", "-a", "android.intent.action.VIEW", "-d", url])
        .status()
        .or_else(|_| {
            std::process::Command::new("/system/bin/sh")
                .env("PATH", "/system/bin:/system/xbin")
                .args(["-c", &format!("/system/bin/am start --user 0 -a android.intent.action.VIEW -d '{url}' -f 0x10000000")])
                .status()
        })
        .map_err(|e| format!("launch support link: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("activity start returned {status}"))
    }
}

const DEFAULT_STATE_DIR: &str = "/data/adb/rodin-essential";
const STATE_DIR_ENV: &str = "RODIN_STATE_DIR";

static PERFORMANCE_PROFILE_SUPPORTED: AtomicI32 = AtomicI32::new(-1);
static PERFORMANCE_PROFILE_VERIFIED: AtomicI32 = AtomicI32::new(-1);
static PERFORMANCE_PROFILE_OK: AtomicI32 = AtomicI32::new(-1);
static ACTIVE_PER_APP_PROFILE: AtomicI32 = AtomicI32::new(-1);
static PERSISTENCE_LOADED: AtomicI32 = AtomicI32::new(0);
static DISPLAY_APPLY_ACK: AtomicI32 = AtomicI32::new(-1);
static TOUCH_APPLY_ACK: AtomicI32 = AtomicI32::new(-1);
static PER_APP_APPLY_ACK: AtomicI32 = AtomicI32::new(-1);
static PRUNED_APP_PROFILE_COUNT: AtomicI32 = AtomicI32::new(0);
static LAST_PER_APP_PROFILE: AtomicI32 = AtomicI32::new(-1);
static KEEPALIVE_APPLY_ACK: AtomicI32 = AtomicI32::new(-1);
static KEEPALIVE_APPLY_COUNT: AtomicI32 = AtomicI32::new(0);
static CPU_WRITE_ACK: AtomicI32 = AtomicI32::new(-1);
static CPU_FREQ_WRITE_ACK: AtomicI32 = AtomicI32::new(-1);
static CORE_CTL_NODE_COUNT: AtomicI32 = AtomicI32::new(0);
static GPU_PROFILE_APPLY_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

static DISPLAY_WIDTH: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_HEIGHT: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_DENSITY: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_NATIVE_DENSITY: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_HZ_X10: AtomicI32 = AtomicI32::new(-1);
static DISPLAY_MAX_HZ_X10: AtomicI32 = AtomicI32::new(-1);

fn gpu_profile_apply_lock() -> &'static Mutex<()> {
    GPU_PROFILE_APPLY_LOCK.get_or_init(|| Mutex::new(()))
}

#[derive(Clone)]
struct PersistedState {
    charging: i32,
    touch: i32,
    dt2w: i32,
    display_color: i32,
    display_temp: i32,
    display_width: i32,
    display_height: i32,
    display_density: i32,
    sunlight: i32,
    silky: i32,
    video: i32,
    dolby: i32,
    expert_gamut: i32,
    expert: [i32; 8],
    perf: i32,
    gpu_profile_cpu_isolated: i32,
    cpu_manual: i32,
    cpu_online_mask: i32,
    cpu0: String,
    cpu4: String,
    cpu7: String,
    gpu: String,
    io: String,
    perapp_enabled: i32,
    app_profiles: BTreeMap<String, i32>,
    brightness_prev: i32,
    zram_size_mb: i32,
    zram_algorithm: String,
    zram_swappiness: i32,
    gpu_min_freq_mhz: i32,
    gpu_max_freq_mhz: i32,
    gpu_governor: String,
    gpu_ged_boost: i32,
    gpu_uncap: i32,
    gpu_power_policy: String,
    cpu_min_freq0: i32,
    cpu_max_freq0: i32,
    cpu_min_freq4: i32,
    cpu_max_freq4: i32,
    cpu_min_freq7: i32,
    cpu_max_freq7: i32,
}

impl Default for PersistedState {
    fn default() -> Self {
        Self {
            charging: 0,
            touch: 1,
            dt2w: 1,
            display_color: 1,
            display_temp: 2,
            display_width: -1,
            display_height: -1,
            display_density: -1,
            sunlight: 1,
            silky: 0,
            video: 0,
            dolby: 0,
            expert_gamut: 1,
            expert: [128, 128, 128, 128, 0, 0, 50, 255],
            perf: 0,
            gpu_profile_cpu_isolated: 1,
            cpu_manual: 0,
            cpu_online_mask: 0xFF,
            cpu0: String::new(),
            cpu4: String::new(),
            cpu7: String::new(),
            gpu: String::new(),
            io: String::new(),
            perapp_enabled: 0,
            app_profiles: BTreeMap::new(),
            brightness_prev: -1,
            zram_size_mb: 8192,
            zram_algorithm: "lz4".to_string(),
            zram_swappiness: 100,
            gpu_min_freq_mhz: 260,
            gpu_max_freq_mhz: 1300,
            gpu_governor: "simple_ondemand".to_string(),
            gpu_ged_boost: 0,
            gpu_uncap: 0,
            gpu_power_policy: "coarse_demand".to_string(),
            cpu_min_freq0: -1,
            cpu_max_freq0: -1,
            cpu_min_freq4: -1,
            cpu_max_freq4: -1,
            cpu_min_freq7: -1,
            cpu_max_freq7: -1,
        }
    }
}

fn legacy_gpu_profile_cpu_signature(state: &PersistedState) -> bool {
    let governors = (
        state.cpu0.as_str(),
        state.cpu4.as_str(),
        state.cpu7.as_str(),
    );
    let ranges = (
        state.cpu_min_freq0,
        state.cpu_max_freq0,
        state.cpu_min_freq4,
        state.cpu_max_freq4,
        state.cpu_min_freq7,
        state.cpu_max_freq7,
    );

    match state.perf {
        3 => {
            governors == ("performance", "performance", "performance")
                && ranges == (2100, 2100, 3000, 3000, 3250, 3250)
        }
        1 => {
            governors == ("schedutil", "schedutil", "schedutil")
                && ranges == (300, 2100, 400, 3000, 1000, 3250)
        }
        2 => {
            governors == ("schedutil", "schedutil", "schedutil")
                && ranges == (300, 1400, 400, 1800, 1000, 1800)
        }
        0 => {
            governors == ("sugov_ext", "sugov_ext", "sugov_ext")
                && ranges == (-1, -1, -1, -1, -1, -1)
        }
        _ => false,
    }
}

fn migrate_legacy_gpu_profile_cpu_state(state: &mut PersistedState) -> bool {
    if state.gpu_profile_cpu_isolated == 1 {
        return false;
    }

    let reset_legacy_cpu = legacy_gpu_profile_cpu_signature(state);
    if reset_legacy_cpu {
        state.cpu0.clear();
        state.cpu4.clear();
        state.cpu7.clear();
        state.cpu_min_freq0 = -1;
        state.cpu_max_freq0 = -1;
        state.cpu_min_freq4 = -1;
        state.cpu_max_freq4 = -1;
        state.cpu_min_freq7 = -1;
        state.cpu_max_freq7 = -1;
    }

    state.gpu_profile_cpu_isolated = 1;
    reset_legacy_cpu
}

fn restore_vendor_cpu_defaults() {
    for policy in [0, 4, 7] {
        if set_cpu_governor(policy, "sugov_ext").is_err() {
            let _ = set_cpu_governor(policy, "schedutil");
        }
    }
    let _ = apply_cluster_freq_controls(0, 300, 2100);
    let _ = apply_cluster_freq_controls(4, 400, 3000);
    let _ = apply_cluster_freq_controls(7, 1000, 3250);
}

static PERSISTED_STATE: OnceLock<Mutex<PersistedState>> = OnceLock::new();
static LAST_EXTERNAL_PACKAGE: OnceLock<Mutex<String>> = OnceLock::new();
static RESOLVED_STATE_DIR: OnceLock<PathBuf> = OnceLock::new();

fn state_dir() -> &'static Path {
    RESOLVED_STATE_DIR
        .get_or_init(|| {
            std::env::var_os(STATE_DIR_ENV)
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .unwrap_or_else(|| PathBuf::from(DEFAULT_STATE_DIR))
        })
        .as_path()
}

fn state_file() -> PathBuf {
    state_dir().join("state.conf")
}

fn load_persisted_state() -> PersistedState {
    let mut state = PersistedState::default();

    let Ok(raw) = fs::read_to_string(state_file()) else {
        return state;
    };

    // State written before GPU/CPU profile isolation did not carry this key.
    // Mark an existing file as legacy until the parser finds the new marker.
    state.gpu_profile_cpu_isolated = 0;

    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };

        let key = key.trim();
        let value = value.trim();
        let int_value = || value.parse::<i32>().ok();

        match key {
            "charging" => {
                if let Some(v) = int_value() {
                    state.charging = v;
                }
            }
            "touch" => {
                if let Some(v) = int_value() {
                    state.touch = v;
                }
            }
            "dt2w" => {
                if let Some(v) = int_value() {
                    state.dt2w = v;
                }
            }
            "display_color" => {
                if let Some(v) = int_value() {
                    state.display_color = v;
                }
            }
            "display_temp" => {
                if let Some(v) = int_value() {
                    state.display_temp = v;
                }
            }
            "display_width" => {
                if let Some(v) = int_value() {
                    state.display_width = v;
                }
            }
            "display_height" => {
                if let Some(v) = int_value() {
                    state.display_height = v;
                }
            }
            "display_density" => {
                if let Some(v) = int_value() {
                    state.display_density = v;
                }
            }
            "sunlight" => {
                if let Some(v) = int_value() {
                    state.sunlight = v;
                }
            }
            "silky" => {
                if let Some(v) = int_value() {
                    state.silky = v;
                }
            }
            "video" => {
                if let Some(v) = int_value() {
                    state.video = v;
                }
            }
            "dolby" => {
                if let Some(v) = int_value() {
                    state.dolby = v;
                }
            }
            "expert_gamut" => {
                if let Some(v) = int_value() {
                    state.expert_gamut = v;
                }
            }
            "expert_1" => {
                if let Some(v) = int_value() {
                    state.expert[0] = v;
                }
            }
            "expert_2" => {
                if let Some(v) = int_value() {
                    state.expert[1] = v;
                }
            }
            "expert_3" => {
                if let Some(v) = int_value() {
                    state.expert[2] = v;
                }
            }
            "expert_4" => {
                if let Some(v) = int_value() {
                    state.expert[3] = v;
                }
            }
            "expert_5" => {
                if let Some(v) = int_value() {
                    state.expert[4] = v;
                }
            }
            "expert_6" => {
                if let Some(v) = int_value() {
                    state.expert[5] = v;
                }
            }
            "expert_7" => {
                if let Some(v) = int_value() {
                    state.expert[6] = v;
                }
            }
            "expert_8" => {
                if let Some(v) = int_value() {
                    state.expert[7] = v;
                }
            }
            "perf" => {
                if let Some(v) = int_value() {
                    state.perf = v;
                }
            }
            "gpu_profile_cpu_isolated" => {
                if let Some(v) = int_value() {
                    state.gpu_profile_cpu_isolated = if v == 1 { 1 } else { 0 };
                }
            }
            "cpu_manual" => {
                if let Some(v) = int_value() {
                    state.cpu_manual = if v == 1 { 1 } else { 0 };
                }
            }
            "cpu_online_mask" => {
                if let Some(v) = int_value() {
                    state.cpu_online_mask = (v | 0x01) & 0xFF;
                }
            }
            "cpu0" => state.cpu0 = value.to_string(),
            "cpu4" => state.cpu4 = value.to_string(),
            "cpu7" => state.cpu7 = value.to_string(),
            "gpu" => state.gpu = value.to_string(),
            "io" => state.io = value.to_string(),
            "perapp_enabled" => {
                if let Some(v) = int_value() {
                    state.perapp_enabled = v;
                }
            }
            "brightness_prev" => {
                if let Some(v) = int_value() {
                    state.brightness_prev = v;
                }
            }
            "zram_size_mb" => {
                if let Some(v) = int_value() {
                    state.zram_size_mb = v;
                }
            }
            "zram_algorithm" => state.zram_algorithm = value.to_string(),
            "zram_swappiness" => {
                if let Some(v) = int_value() {
                    state.zram_swappiness = v;
                }
            }
            "gpu_min_freq_mhz" => {
                if let Some(v) = int_value() {
                    state.gpu_min_freq_mhz = v;
                }
            }
            "gpu_max_freq_mhz" => {
                if let Some(v) = int_value() {
                    state.gpu_max_freq_mhz = v;
                }
            }
            "gpu_governor" => state.gpu_governor = value.to_string(),
            "gpu_ged_boost" => {
                if let Some(v) = int_value() {
                    state.gpu_ged_boost = v;
                }
            }
            "gpu_uncap" => {
                if let Some(v) = int_value() {
                    state.gpu_uncap = v;
                }
            }
            "gpu_power_policy" => state.gpu_power_policy = value.to_string(),
            "cpu_min_freq0" => {
                if let Some(v) = int_value() {
                    state.cpu_min_freq0 = v;
                }
            }
            "cpu_max_freq0" => {
                if let Some(v) = int_value() {
                    state.cpu_max_freq0 = v;
                }
            }
            "cpu_min_freq4" => {
                if let Some(v) = int_value() {
                    state.cpu_min_freq4 = v;
                }
            }
            "cpu_max_freq4" => {
                if let Some(v) = int_value() {
                    state.cpu_max_freq4 = v;
                }
            }
            "cpu_min_freq7" => {
                if let Some(v) = int_value() {
                    state.cpu_min_freq7 = v;
                }
            }
            "cpu_max_freq7" => {
                if let Some(v) = int_value() {
                    state.cpu_max_freq7 = v;
                }
            }
            _ if key.starts_with("app.") => {
                if let Some(v) = int_value() {
                    state.app_profiles.insert(key[4..].to_string(), v);
                }
            }
            _ => {}
        }
    }

    state.touch = if (1..=3).contains(&state.touch) {
        state.touch
    } else {
        1
    };
    if state.dt2w < 0 {
        state.dt2w = 1;
    }
    if state.display_color < 0 {
        state.display_color = 1;
    }
    if state.display_temp < 0 {
        state.display_temp = 2;
    }
    if state.sunlight < 0 {
        state.sunlight = 1;
    }
    if state.silky < 0 {
        state.silky = 0;
    }
    if state.video < 0 {
        state.video = 0;
    }
    if state.dolby < 0 {
        state.dolby = 0;
    }

    state
}

fn persisted_state() -> &'static Mutex<PersistedState> {
    PERSISTED_STATE.get_or_init(|| Mutex::new(load_persisted_state()))
}

fn last_external_package() -> &'static Mutex<String> {
    LAST_EXTERNAL_PACKAGE.get_or_init(|| Mutex::new(String::new()))
}

fn save_persisted_state(state: &PersistedState) -> Result<(), String> {
    fs::create_dir_all(state_dir()).map_err(|e| format!("state mkdir: {e}"))?;

    let mut out = String::new();
    out.push_str(&format!("charging={}\n", state.charging));
    out.push_str(&format!("touch={}\n", state.touch));
    out.push_str(&format!("dt2w={}\n", state.dt2w));
    out.push_str(&format!("display_color={}\n", state.display_color));
    out.push_str(&format!("display_temp={}\n", state.display_temp));
    out.push_str(&format!("display_width={}\n", state.display_width));
    out.push_str(&format!("display_height={}\n", state.display_height));
    out.push_str(&format!("display_density={}\n", state.display_density));
    out.push_str(&format!("sunlight={}\n", state.sunlight));
    out.push_str(&format!("silky={}\n", state.silky));
    out.push_str(&format!("video={}\n", state.video));
    out.push_str(&format!("dolby={}\n", state.dolby));
    out.push_str(&format!("expert_gamut={}\n", state.expert_gamut));

    for i in 0..8 {
        out.push_str(&format!("expert_{}={}\n", i + 1, state.expert[i]));
    }

    out.push_str(&format!("perf={}\n", state.perf));
    out.push_str(&format!(
        "gpu_profile_cpu_isolated={}\n",
        state.gpu_profile_cpu_isolated
    ));
    out.push_str(&format!("cpu_manual={}\n", state.cpu_manual));
    out.push_str(&format!(
        "cpu_online_mask={}\n",
        state.cpu_online_mask | 0x01
    ));
    out.push_str(&format!("cpu0={}\n", state.cpu0));
    out.push_str(&format!("cpu4={}\n", state.cpu4));
    out.push_str(&format!("cpu7={}\n", state.cpu7));
    out.push_str(&format!("gpu={}\n", state.gpu));
    out.push_str(&format!("io={}\n", state.io));
    out.push_str(&format!("perapp_enabled={}\n", state.perapp_enabled));
    out.push_str(&format!("brightness_prev={}\n", state.brightness_prev));
    out.push_str(&format!("zram_size_mb={}\n", state.zram_size_mb));
    out.push_str(&format!("zram_algorithm={}\n", state.zram_algorithm));
    out.push_str(&format!("zram_swappiness={}\n", state.zram_swappiness));
    out.push_str(&format!("gpu_min_freq_mhz={}\n", state.gpu_min_freq_mhz));
    out.push_str(&format!("gpu_max_freq_mhz={}\n", state.gpu_max_freq_mhz));
    out.push_str(&format!("gpu_governor={}\n", state.gpu_governor));
    out.push_str(&format!("gpu_ged_boost={}\n", state.gpu_ged_boost));
    out.push_str(&format!("gpu_uncap={}\n", state.gpu_uncap));
    out.push_str(&format!("gpu_power_policy={}\n", state.gpu_power_policy));
    out.push_str(&format!("cpu_min_freq0={}\n", state.cpu_min_freq0));
    out.push_str(&format!("cpu_max_freq0={}\n", state.cpu_max_freq0));
    out.push_str(&format!("cpu_min_freq4={}\n", state.cpu_min_freq4));
    out.push_str(&format!("cpu_max_freq4={}\n", state.cpu_max_freq4));
    out.push_str(&format!("cpu_min_freq7={}\n", state.cpu_min_freq7));
    out.push_str(&format!("cpu_max_freq7={}\n", state.cpu_max_freq7));

    for (pkg, profile) in &state.app_profiles {
        out.push_str(&format!("app.{pkg}={profile}\n"));
    }

    let state_file = state_file();
    let tmp = state_dir().join("state.conf.tmp");
    fs::write(&tmp, out).map_err(|e| format!("state write: {e}"))?;
    fs::rename(&tmp, &state_file).map_err(|e| format!("state rename: {e}"))?;
    Ok(())
}

fn mutate_persisted_state<F>(f: F)
where
    F: FnOnce(&mut PersistedState),
{
    if let Ok(mut guard) = persisted_state().lock() {
        f(&mut guard);
        let snapshot = guard.clone();
        drop(guard);
        let _ = save_persisted_state(&snapshot);
    }
}

fn set_dt2w(enabled: bool) -> Result<(), String> {
    let value = if enabled { 1 } else { 0 };

    if !vendor_binder::set_touch_mode(0, 14, value) {
        TOUCH_APPLY_ACK.store(0, Ordering::Release);
        return Err("touch HAL DT2W mode14 transaction failed".into());
    }

    TOUCH_APPLY_ACK.store(1, Ordering::Release);
    mutate_persisted_state(|s| s.dt2w = value);
    Ok(())
}

fn expert_value_range(channel: i32) -> Option<(i32, i32)> {
    match channel {
        1..=3 => Some((0, 255)),
        4 => Some((0, 255)),
        5 => Some((-40, 50)),
        6 => Some((-240, 255)),
        7 => Some((0, 100)),
        8 => Some((254, 270)),
        _ => None,
    }
}

fn set_expert_gamut(gamut: i32) -> Result<(), String> {
    if !matches!(gamut, 1..=3) {
        return Err("invalid expert gamut".into());
    }

    let display_color = persisted_state()
        .lock()
        .ok()
        .map(|state| state.display_color)
        .unwrap_or(-1);

    if display_color != 0 {
        return Err("expert calibration requires Original PRO".into());
    }

    if !vendor_binder::set_display_feature(26, gamut, 0) {
        DISPLAY_APPLY_ACK.store(0, Ordering::Release);
        return Err("display HAL expert gamut transaction failed".into());
    }

    DISPLAY_APPLY_ACK.store(1, Ordering::Release);
    mutate_persisted_state(|s| s.expert_gamut = gamut);
    Ok(())
}

fn set_expert_channel(channel: i32, value: i32) -> Result<(), String> {
    let display_color = persisted_state()
        .lock()
        .ok()
        .map(|state| state.display_color)
        .unwrap_or(-1);

    if display_color != 0 {
        return Err("expert calibration requires Original PRO".into());
    }

    let Some((min, max)) = expert_value_range(channel) else {
        return Err("invalid expert channel".into());
    };

    if value < min || value > max {
        return Err(format!(
            "expert channel {channel} out of range {min}..{max}: {value}"
        ));
    }

    if !vendor_binder::set_display_feature(26, value, channel) {
        DISPLAY_APPLY_ACK.store(0, Ordering::Release);
        return Err(format!(
            "display HAL expert channel transaction failed channel={channel}"
        ));
    }

    DISPLAY_APPLY_ACK.store(1, Ordering::Release);
    mutate_persisted_state(|s| s.expert[(channel - 1) as usize] = value);
    Ok(())
}

fn reset_expert_display() -> Result<(), String> {
    const DEFAULTS: &[(i32, i32)] = &[
        (1, 255),
        (2, 255),
        (3, 255),
        (4, 0),
        (5, 0),
        (6, 0),
        (7, 50),
        (8, 262),
    ];

    set_display_color(0)?;
    set_display_temp(2)?;

    if !vendor_binder::set_display_feature(26, 1, 0) {
        return Err("display HAL reset gamut failed".into());
    }

    for &(channel, value) in DEFAULTS {
        if !vendor_binder::set_display_feature(26, value, channel) {
            return Err(format!("display HAL reset channel {channel} failed"));
        }
    }

    DISPLAY_APPLY_ACK.store(1, Ordering::Release);

    mutate_persisted_state(|s| {
        s.display_color = 0;
        s.display_temp = 2;
        s.expert_gamut = 1;
        s.expert = [255, 255, 255, 0, 0, 0, 50, 262];
    });

    Ok(())
}

fn run_settings_command(args: &[&str]) -> Result<String, String> {
    let output = ProcessCommand::new("/system/bin/settings")
        .args(args)
        .output()
        .map_err(|e| format!("settings spawn: {e}"))?;

    if !output.status.success() {
        return Err(format!(
            "settings {:?} failed status={}",
            args, output.status
        ));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn set_sunlight(enabled: bool) -> Result<(), String> {
    if enabled {
        let current = run_settings_command(&["get", "system", "screen_brightness"])?
            .parse::<i32>()
            .map_err(|_| "screen_brightness is not numeric".to_string())?;

        if !vendor_binder::set_display_feature(12, 1, 255) {
            DISPLAY_APPLY_ACK.store(0, Ordering::Release);
            return Err("display HAL sunlight enable failed".into());
        }

        let target = (current + 13).clamp(1, 255);

        if let Err(e) =
            run_settings_command(&["put", "system", "screen_brightness", &target.to_string()])
        {
            let _ = vendor_binder::set_display_feature(12, 0, 255);
            DISPLAY_APPLY_ACK.store(0, Ordering::Release);
            return Err(e);
        }

        DISPLAY_SUNLIGHT_STATE.store(1, Ordering::Release);
        DISPLAY_APPLY_ACK.store(1, Ordering::Release);

        mutate_persisted_state(|s| {
            s.sunlight = 1;
            s.brightness_prev = current;
        });

        Ok(())
    } else {
        if !vendor_binder::set_display_feature(12, 0, 255) {
            DISPLAY_APPLY_ACK.store(0, Ordering::Release);
            return Err("display HAL sunlight disable failed".into());
        }

        let previous = persisted_state()
            .lock()
            .ok()
            .map(|s| s.brightness_prev)
            .unwrap_or(-1);

        if previous >= 1 {
            run_settings_command(&["put", "system", "screen_brightness", &previous.to_string()])?;
        }

        DISPLAY_SUNLIGHT_STATE.store(0, Ordering::Release);
        DISPLAY_APPLY_ACK.store(1, Ordering::Release);

        mutate_persisted_state(|s| {
            s.sunlight = 0;
            s.brightness_prev = -1;
        });

        Ok(())
    }
}

fn record_successful_command(cmd: &str) {
    if let Some(arg) = cmd.strip_prefix("SET charging ") {
        if let Ok(v) = arg.trim().parse::<i32>() {
            mutate_persisted_state(|s| s.charging = v);
        }
        return;
    }

    if let Some(arg) = cmd.strip_prefix("SET touch ") {
        if let Ok(v) = arg.trim().parse::<i32>() {
            TOUCH_APPLY_ACK.store(1, Ordering::Release);
            mutate_persisted_state(|s| s.touch = v);
        }
        return;
    }

    if let Some(arg) = cmd.strip_prefix("SET display.color ") {
        if let Ok(v) = arg.trim().parse::<i32>() {
            DISPLAY_APPLY_ACK.store(1, Ordering::Release);
            mutate_persisted_state(|s| s.display_color = v);
        }
        return;
    }

    if let Some(arg) = cmd.strip_prefix("SET display.temp ") {
        if let Ok(v) = arg.trim().parse::<i32>() {
            DISPLAY_APPLY_ACK.store(1, Ordering::Release);
            mutate_persisted_state(|s| s.display_temp = v);
        }
        return;
    }

    for (prefix, kind) in [
        ("SET display.silky ", 1),
        ("SET display.video ", 2),
        ("SET display.dolby ", 3),
    ] {
        if let Some(arg) = cmd.strip_prefix(prefix) {
            if let Ok(v) = arg.trim().parse::<i32>() {
                DISPLAY_APPLY_ACK.store(1, Ordering::Release);

                mutate_persisted_state(|s| match kind {
                    1 => s.silky = v,
                    2 => s.video = v,
                    3 => s.dolby = v,
                    _ => {}
                });
            }
            return;
        }
    }

    if let Some(arg) = cmd.strip_prefix("SET perf ") {
        if let Ok(v) = arg.trim().parse::<i32>() {
            PERFORMANCE_STATE.store(v, Ordering::Release);
        }
        return;
    }

    if let Some(rest) = cmd.strip_prefix("SET cpu.gov ") {
        let mut parts = rest.split_whitespace();
        let policy = parts.next().and_then(|v| v.parse::<i32>().ok());
        let gov = parts.next().unwrap_or("").to_string();

        if let Some(policy) = policy {
            mutate_persisted_state(|s| match policy {
                0 => s.cpu0 = gov.clone(),
                4 => s.cpu4 = gov.clone(),
                7 => s.cpu7 = gov.clone(),
                _ => {}
            });
        }
        return;
    }

    if let Some(rest) = cmd.strip_prefix("SET cpu.min_freq ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        mutate_persisted_state(|s| match policy {
            0 => s.cpu_min_freq0 = mhz,
            4 => s.cpu_min_freq4 = mhz,
            7 => s.cpu_min_freq7 = mhz,
            _ => {}
        });
        return;
    }

    if let Some(rest) = cmd.strip_prefix("SET cpu.max_freq ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        mutate_persisted_state(|s| match policy {
            0 => s.cpu_max_freq0 = mhz,
            4 => s.cpu_max_freq4 = mhz,
            7 => s.cpu_max_freq7 = mhz,
            _ => {}
        });
        return;
    }

    if let Some(rest) = cmd.strip_prefix("SET cpu.freq_range ") {
        // The verified range setter persists both limits atomically. Do not
        // execute the hardware transaction a second time from this recorder.
        let _ = rest;
        return;
    }

    if cmd.starts_with("SET cpu.freq_reset ") {
        return;
    }

    if let Some(arg) = cmd.strip_prefix("SET gpu.gov ") {
        let value = arg.trim().to_string();
        mutate_persisted_state(|s| s.gpu = value);
        return;
    }

    if let Some(arg) = cmd.strip_prefix("SET io.scheduler ") {
        let value = arg.trim().to_string();
        mutate_persisted_state(|s| s.io = value);
    }
}

fn drift_status(desired: &str, actual: &str) -> i32 {
    if desired.is_empty() {
        -1
    } else if desired == actual {
        0
    } else {
        1
    }
}

fn cpu_frequency_drift_status(
    target_min: i32,
    target_max: i32,
    live_min: i32,
    live_max: i32,
) -> i32 {
    if target_min <= 0 || target_max <= 0 {
        -1
    } else if target_min == live_min && target_max == live_max {
        0
    } else {
        1
    }
}

fn parse_number_after(line: &str, key: &str) -> Option<f64> {
    let pos = line.find(key)?;
    let tail = &line[pos + key.len()..];

    let token: String = tail
        .chars()
        .skip_while(|c| c.is_whitespace() || *c == '=' || *c == ':')
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();

    token.parse::<f64>().ok()
}

fn scaled_display_density(native_density: i32, width: i32) -> i32 {
    (native_density * width + 610) / 1220
}

fn refresh_display_info() {
    let mut width = -1;
    let mut height = -1;
    let mut density = -1;
    let mut native_density = -1;
    let mut current_x10 = -1;
    let mut max_x10 = -1;

    if let Ok(output) = ProcessCommand::new("/system/bin/wm").arg("size").output() {
        let text = String::from_utf8_lossy(&output.stdout);
        let mut physical_size = None;
        let mut override_size = None;

        for line in text.lines() {
            let parsed = line
                .split_once(':')
                .and_then(|(_, raw)| raw.trim().split_once('x'))
                .and_then(|(w, h)| Some((w.trim().parse().ok()?, h.trim().parse().ok()?)));

            if line.contains("Override size:") {
                override_size = parsed;
            } else if line.contains("Physical size:") {
                physical_size = parsed;
            }
        }

        if let Some((parsed_width, parsed_height)) = override_size.or(physical_size) {
            width = parsed_width;
            height = parsed_height;
        }
    }

    if let Ok(output) = ProcessCommand::new("/system/bin/wm")
        .arg("density")
        .output()
    {
        let text = String::from_utf8_lossy(&output.stdout);
        for line in text.lines() {
            if line.contains("Override density:") {
                density = line
                    .split(':')
                    .nth(1)
                    .and_then(|raw| raw.trim().parse::<i32>().ok())
                    .unwrap_or(-1);
            } else if line.contains("Physical density:") {
                native_density = line
                    .split(':')
                    .nth(1)
                    .and_then(|raw| raw.trim().parse::<i32>().ok())
                    .unwrap_or(-1);
            }
        }
    }

    if native_density <= 0
        && let Ok(output) = ProcessCommand::new("/system/bin/getprop")
            .arg("ro.sf.lcd_density")
            .output()
    {
        native_density = String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse::<i32>()
            .unwrap_or(-1);
    }
    if density <= 0 {
        density = native_density;
    }

    for path in [
        "/sys/devices/virtual/mi_display/disp_feature/disp-DSI-0/dynamic_fps",
        "/sys/class/mi_display/disp-DSI-0/dynamic_fps",
    ] {
        if let Ok(raw) = fs::read_to_string(path)
            && let Ok(rate) = raw.trim().parse::<f64>()
            && (1.0..=1000.0).contains(&rate)
        {
            current_x10 = (rate * 10.0).round() as i32;
            break;
        }
    }

    if let Ok(output) = ProcessCommand::new("/system/bin/dumpsys")
        .args(["display"])
        .output()
    {
        let text = String::from_utf8_lossy(&output.stdout);
        let mut active_id: Option<i32> = None;

        for line in text.lines() {
            if active_id.is_none()
                && let Some(v) = parse_number_after(line, "mActiveModeId")
            {
                active_id = Some(v as i32);
            }

            for key in ["fps=", "refreshRate=", "refreshRate:"] {
                if let Some(v) = parse_number_after(line, key)
                    && (1.0..=1000.0).contains(&v)
                {
                    let x10 = (v * 10.0).round() as i32;

                    if x10 > max_x10 {
                        max_x10 = x10;
                    }

                    if let Some(id) = active_id {
                        let id_a = format!("id={id}");
                        let id_b = format!("modeId={id}");

                        if (line.contains(&id_a) || line.contains(&id_b)) && current_x10 <= 0 {
                            current_x10 = x10;
                        }
                    }
                }
            }
        }
    }

    // Prefer the ROM's configured peak over the panel capability. This keeps
    // the UI truthful when adaptive refresh is currently idling below the
    // user's selected 90/120 Hz setting.
    for (namespace, key) in [
        ("system", "peak_refresh_rate"),
        ("secure", "user_refresh_rate"),
        ("system", "user_refresh_rate"),
    ] {
        if let Ok(output) = ProcessCommand::new("/system/bin/settings")
            .args(["get", namespace, key])
            .output()
            && let Ok(rate) = String::from_utf8_lossy(&output.stdout)
                .trim()
                .parse::<f64>()
            && (1.0..=1000.0).contains(&rate)
        {
            max_x10 = (rate * 10.0).round() as i32;
            break;
        }
    }

    DISPLAY_WIDTH.store(width, Ordering::Release);
    DISPLAY_HEIGHT.store(height, Ordering::Release);
    DISPLAY_DENSITY.store(density, Ordering::Release);
    DISPLAY_NATIVE_DENSITY.store(native_density, Ordering::Release);
    DISPLAY_HZ_X10.store(current_x10, Ordering::Release);
    DISPLAY_MAX_HZ_X10.store(max_x10, Ordering::Release);
}

fn apply_display_resolution(
    width: i32,
    height: i32,
    density: i32,
    persist: bool,
) -> Result<(), String> {
    let native = width <= 0 || height <= 0 || (width == 1220 && height == 2712);
    let detected_density = DISPLAY_NATIVE_DENSITY.load(Ordering::Acquire);
    let native_density = if detected_density > 0 {
        detected_density
    } else {
        520
    };
    let target_density = if native {
        native_density
    } else if density > 0 {
        density
    } else {
        scaled_display_density(native_density, width)
    };

    let run_wm = |args: &[&str]| -> Result<(), String> {
        let output = ProcessCommand::new("/system/bin/wm")
            .args(args)
            .output()
            .map_err(|error| format!("wm {}: {error}", args.join(" ")))?;
        if output.status.success() {
            Ok(())
        } else {
            Err(format!(
                "wm {} failed: {}",
                args.join(" "),
                String::from_utf8_lossy(&output.stderr).trim()
            ))
        }
    };

    if native {
        run_wm(&["size", "reset"])?;
        run_wm(&["density", "reset"])?;
    } else {
        let size = format!("{width}x{height}");
        let density = target_density.to_string();
        run_wm(&["size", &size])?;
        run_wm(&["density", &density])?;
    }

    let expected_width = if native { 1220 } else { width };
    let expected_height = if native { 2712 } else { height };
    let mut verified = false;
    for _ in 0..4 {
        std::thread::sleep(Duration::from_millis(35));
        refresh_display_info();
        verified = DISPLAY_WIDTH.load(Ordering::Acquire) == expected_width
            && DISPLAY_HEIGHT.load(Ordering::Acquire) == expected_height
            && DISPLAY_DENSITY.load(Ordering::Acquire) == target_density;
        if verified {
            break;
        }
    }
    if !verified {
        return Err(format!(
            "display resolution verify failed: requested {expected_width}x{expected_height} {target_density}dpi, live {}x{} {}dpi",
            DISPLAY_WIDTH.load(Ordering::Acquire),
            DISPLAY_HEIGHT.load(Ordering::Acquire),
            DISPLAY_DENSITY.load(Ordering::Acquire),
        ));
    }

    if persist {
        mutate_persisted_state(|state| {
            if native {
                state.display_width = 0;
                state.display_height = 0;
                state.display_density = 0;
            } else {
                state.display_width = width;
                state.display_height = height;
                state.display_density = target_density;
            }
        });
    }

    DISPLAY_APPLY_ACK.store(1, Ordering::Release);
    Ok(())
}

fn foreground_package() -> Option<String> {
    // Avoid dumpsys here. Some Android 16 vendor builds have an MTE bug in
    // NativeInputEventReceiver::dump; polling ActivityManager's dump path can
    // therefore crash system_server and look like a random phone restart.
    // Android already exposes the foreground scheduling group directly.
    const TOP_APP_PROCS: &[&str] = &[
        "/dev/cpuset/top-app/cgroup.procs",
        "/sys/fs/cgroup/top-app/cgroup.procs",
    ];

    let raw = TOP_APP_PROCS
        .iter()
        .find_map(|path| fs::read_to_string(path).ok())?;
    let mut fallback: Option<(i32, String)> = None;

    for pid in raw.split_whitespace() {
        if !pid.bytes().all(|byte| byte.is_ascii_digit()) {
            continue;
        }
        let base = format!("/proc/{pid}");
        let Some(uid) = fs::read_to_string(format!("{base}/status"))
            .ok()
            .and_then(|status| {
                status.lines().find_map(|line| {
                    line.strip_prefix("Uid:")?
                        .split_whitespace()
                        .next()?
                        .parse::<u32>()
                        .ok()
                })
            })
        else {
            continue;
        };
        if uid < 10_000 {
            continue;
        }

        let Ok(cmdline) = fs::read(format!("{base}/cmdline")) else {
            continue;
        };
        let process = cmdline.split(|byte| *byte == 0).next().unwrap_or_default();
        let process = String::from_utf8_lossy(process);
        let package = process.split(':').next().unwrap_or("").trim();
        if !validate_package_name(package) {
            continue;
        }

        let adj = fs::read_to_string(format!("{base}/oom_score_adj"))
            .ok()
            .and_then(|value| value.trim().parse::<i32>().ok())
            .unwrap_or(i32::MAX);
        if adj == 0 {
            return Some(package.to_string());
        }
        if fallback.as_ref().is_none_or(|(best, _)| adj < *best) {
            fallback = Some((adj, package.to_string()));
        }
    }

    fallback.map(|(_, package)| package)
}

fn validate_package_name(pkg: &str) -> bool {
    if pkg.len() < 3 || pkg.len() > 255 || !pkg.contains('.') {
        return false;
    }

    pkg.chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

fn set_app_profile(pkg: &str, profile: i32) -> Result<(), String> {
    if !validate_package_name(pkg) {
        return Err("invalid package name".into());
    }

    if !matches!(profile, -1..=3) {
        return Err("invalid per-app profile".into());
    }

    let package = pkg.to_string();

    mutate_persisted_state(|state| {
        if profile < 0 {
            state.app_profiles.remove(&package);
        } else {
            state.app_profiles.insert(package.clone(), profile);
            state.perapp_enabled = 1;
        }
    });

    Ok(())
}

fn installed_packages() -> Result<std::collections::BTreeSet<String>, String> {
    let output = ProcessCommand::new("/system/bin/pm")
        .args(["list", "packages"])
        .output()
        .map_err(|e| format!("pm list packages spawn: {e}"))?;

    if !output.status.success() {
        return Err(format!("pm list packages failed status={}", output.status));
    }

    let mut packages = std::collections::BTreeSet::new();

    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let pkg = line
            .trim()
            .strip_prefix("package:")
            .unwrap_or(line.trim())
            .trim();

        if validate_package_name(pkg) {
            packages.insert(pkg.to_string());
        }
    }

    Ok(packages)
}

fn prune_stale_profiles() -> Result<usize, String> {
    let installed = installed_packages()?;
    let mut removed = 0usize;

    mutate_persisted_state(|state| {
        let before = state.app_profiles.len();
        state.app_profiles.retain(|pkg, _| installed.contains(pkg));
        removed = before.saturating_sub(state.app_profiles.len());
    });

    if removed > 0 {
        PRUNED_APP_PROFILE_COUNT.fetch_add(removed.min(i32::MAX as usize) as i32, Ordering::AcqRel);
    }

    Ok(removed)
}

fn serialize_app_profiles(state: &PersistedState) -> String {
    state
        .app_profiles
        .iter()
        .map(|(pkg, profile)| format!("{pkg}:{profile}"))
        .collect::<Vec<String>>()
        .join(",")
}

fn screen_is_on() -> Option<bool> {
    for path in [
        "/sys/class/backlight/panel0-backlight/actual_brightness",
        "/sys/class/backlight/panel0-backlight/brightness",
        "/sys/class/leds/lcd-backlight/brightness",
    ] {
        if let Ok(raw) = fs::read_to_string(path)
            && let Ok(value) = raw.trim().parse::<i64>()
        {
            return Some(value > 0);
        }
    }

    let output = ProcessCommand::new("/system/bin/dumpsys")
        .arg("power")
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout);

    if text.contains("mWakefulness=Awake") || text.contains("Display Power: state=ON") {
        Some(true)
    } else if text.contains("mWakefulness=Asleep")
        || text.contains("mWakefulness=Dozing")
        || text.contains("Display Power: state=OFF")
    {
        Some(false)
    } else {
        None
    }
}

fn reassert_runtime_state(force_touch: bool) -> Result<(), String> {
    // NOTE: Refresh rate is NOT touched here. The system's own
    // DisplayModeDirector / PRIORITY_MIUI_REFRESH_RATE / thermal voter
    // handles refresh rate based on the user's choice in Settings.
    // Overriding it from the daemon caused a tug-of-war that made the
    // display oscillate between 60 Hz and 120 Hz.

    let state = persisted_state()
        .lock()
        .ok()
        .map(|guard| guard.clone())
        .unwrap_or_default();

    let mut attempted = 0i32;
    let mut applied = 0i32;

    if matches!(state.charging, 0 | 8) {
        attempted += 1;
        if write_verified(
            &charging_path(),
            if state.charging == 8 { "8" } else { "0" },
        )
        .is_ok()
        {
            applied += 1;
        }
    }

    if (1..=3).contains(&state.touch) {
        attempted += 1;
        let touch_matches = TOUCH_STATE.load(Ordering::Acquire) == state.touch
            && TOUCH_APPLY_ACK.load(Ordering::Acquire) == 1
            && touch_profile_is_live(state.touch);
        if (!force_touch && touch_matches) || set_touch_profile(state.touch).is_ok() {
            applied += 1;
        }
    }

    if matches!(state.dt2w, 0 | 1) {
        attempted += 1;
        if vendor_binder::set_touch_mode(0, 14, state.dt2w) {
            TOUCH_APPLY_ACK.store(1, Ordering::Release);
            applied += 1;
        } else {
            TOUCH_APPLY_ACK.store(0, Ordering::Release);
        }
    }

    let ok = attempted > 0 && applied == attempted;

    KEEPALIVE_APPLY_ACK.store(if ok { 1 } else { 0 }, Ordering::Release);

    if ok {
        DISPLAY_APPLY_ACK.store(1, Ordering::Release);
        KEEPALIVE_APPLY_COUNT.fetch_add(1, Ordering::AcqRel);
        Ok(())
    } else {
        Err(format!(
            "runtime persistence verify failed: applied {applied} of {attempted} settings"
        ))
    }
}

fn set_per_app_enabled(enabled: bool) -> Result<(), String> {
    let value = if enabled { 1 } else { 0 };

    let global_profile = persisted_state()
        .lock()
        .ok()
        .map(|state| state.perf)
        .unwrap_or(0);

    mutate_persisted_state(|state| state.perapp_enabled = value);

    if enabled {
        PER_APP_APPLY_ACK.store(-1, Ordering::Release);
        return Ok(());
    }

    ACTIVE_PER_APP_PROFILE.store(-1, Ordering::Release);
    LAST_PER_APP_PROFILE.store(-1, Ordering::Release);

    if (0..=3).contains(&global_profile) {
        match apply_performance_profile(global_profile) {
            Ok(()) => {
                PER_APP_APPLY_ACK.store(1, Ordering::Release);
                Ok(())
            }
            Err(error) => {
                PER_APP_APPLY_ACK.store(0, Ordering::Release);
                Err(format!(
                    "restore global profile after per-app disable: {error}"
                ))
            }
        }
    } else {
        PER_APP_APPLY_ACK.store(1, Ordering::Release);
        Ok(())
    }
}

fn assign_last_app_profile(profile: i32) -> Result<(), String> {
    let pkg = last_external_package()
        .lock()
        .ok()
        .map(|slot| slot.clone())
        .unwrap_or_default();

    if pkg.is_empty() {
        return Err("no previous external foreground app captured".into());
    }

    set_app_profile(&pkg, profile)
}

fn restore_sunlight(state: &PersistedState) {
    if state.sunlight == 1 {
        if vendor_binder::set_display_feature(12, 1, 255) {
            DISPLAY_SUNLIGHT_STATE.store(1, Ordering::Release);

            // A saved pre-reboot brightness must not be restored later as if
            // it belonged to the new boot/session. Keep the HAL state only.
            mutate_persisted_state(|s| s.brightness_prev = -1);
        }
    } else if state.sunlight == 0 && vendor_binder::set_display_feature(12, 0, 255) {
        DISPLAY_SUNLIGHT_STATE.store(0, Ordering::Release);
        mutate_persisted_state(|s| s.brightness_prev = -1);
    }
}

fn restore_persisted_state() {
    restore_cpu_state();

    let mut state = persisted_state()
        .lock()
        .ok()
        .map(|s| s.clone())
        .unwrap_or_default();

    let legacy_state = state.gpu_profile_cpu_isolated != 1;
    let reset_legacy_cpu = migrate_legacy_gpu_profile_cpu_state(&mut state);
    if legacy_state {
        if let Ok(mut guard) = persisted_state().lock() {
            *guard = state.clone();
        }
        let _ = save_persisted_state(&state);
    }
    if reset_legacy_cpu {
        // Undo only the exact CPU signature written by an older GPU profile.
        // Custom CPU settings that do not match that signature are preserved.
        restore_vendor_cpu_defaults();
    }

    PERSISTENCE_LOADED.store(1, Ordering::Release);

    if matches!(state.charging, 0 | 8) {
        let _ = write_verified(
            &charging_path(),
            if state.charging == 8 { "8" } else { "0" },
        );
    }

    if (1..=3).contains(&state.touch) {
        let _ = set_touch_profile(state.touch);
    }

    if matches!(state.dt2w, 0 | 1) {
        let _ = vendor_binder::set_touch_mode(0, 14, state.dt2w);
    }

    if state.display_width >= 0 && state.display_height >= 0 {
        let _ = apply_display_resolution(
            state.display_width,
            state.display_height,
            state.display_density,
            false,
        );
    }

    if (0..=2).contains(&state.display_color) {
        let _ = set_display_color(state.display_color);
    }

    if (1..=3).contains(&state.display_temp) {
        let _ = set_display_temp(state.display_temp);
    }

    restore_sunlight(&state);
    // A pre-reboot brightness value belongs to the previous Android session.
    // Keep the saved hardware intent, but never resurrect that stale value
    // after the profile restore below replaces the in-memory state.
    state.brightness_prev = -1;

    if matches!(state.silky, 0 | 1) {
        let _ = set_display_toggle(57, state.silky == 1, &DISPLAY_SILKY_STATE);
    }

    if matches!(state.video, 0 | 1) {
        let _ = set_display_toggle(27, state.video == 1, &DISPLAY_VIDEO_STATE);
    }

    if matches!(state.dolby, 0 | 1) {
        let _ = set_display_toggle(44, state.dolby == 1, &DISPLAY_DOLBY_STATE);
    }

    if state.display_color == 0 {
        if matches!(state.expert_gamut, 1..=3) {
            let _ = vendor_binder::set_display_feature(26, state.expert_gamut, 0);
        }

        for channel in 1..=8 {
            let value = state.expert[(channel - 1) as usize];

            if let Some((min, max)) = expert_value_range(channel)
                && (min..=max).contains(&value)
            {
                let _ = vendor_binder::set_display_feature(26, value, channel);
            }
        }
    }

    if (0..=3).contains(&state.perf) {
        // GPU profiles are isolated from CPU controls. Preserve the exact
        // persisted selection while restoring the requested Mali state.
        let persisted = state.clone();
        let _ = apply_performance_profile(state.perf);
        PERFORMANCE_STATE.store(persisted.perf, Ordering::Release);
        if let Ok(mut guard) = persisted_state().lock() {
            *guard = persisted.clone();
        }
        let _ = save_persisted_state(&persisted);
        state = persisted;
    }

    if !state.cpu0.is_empty() {
        let _ = set_cpu_governor(0, &state.cpu0);
    }

    if !state.cpu4.is_empty() {
        let _ = set_cpu_governor(4, &state.cpu4);
    }

    if !state.cpu7.is_empty() {
        let _ = set_cpu_governor(7, &state.cpu7);
    }

    let target_gpu = if !state.gpu_governor.is_empty() {
        &state.gpu_governor
    } else if !state.gpu.is_empty() {
        &state.gpu
    } else {
        "simple_ondemand"
    };
    let _ = set_gpu_governor(target_gpu);

    if !state.io.is_empty() {
        let _ = set_io_scheduler(&state.io);
    }

    if state.zram_swappiness >= 0 {
        let _ = set_zram_swappiness(state.zram_swappiness);
    }

    if !state.zram_algorithm.is_empty() {
        let _ = set_zram_algorithm(&state.zram_algorithm);
    }

    if state.zram_size_mb >= 0 {
        let _ = set_zram_size(state.zram_size_mb);
    }

    if state.cpu_min_freq0 > 0 || state.cpu_max_freq0 > 0 {
        let min = if state.cpu_min_freq0 > 0 {
            state.cpu_min_freq0
        } else {
            300
        };
        let max = if state.cpu_max_freq0 > 0 {
            state.cpu_max_freq0
        } else {
            2100
        };
        let _ = apply_cluster_freq_controls(0, min, max);
    }
    if state.cpu_min_freq4 > 0 || state.cpu_max_freq4 > 0 {
        let min = if state.cpu_min_freq4 > 0 {
            state.cpu_min_freq4
        } else {
            400
        };
        let max = if state.cpu_max_freq4 > 0 {
            state.cpu_max_freq4
        } else {
            3000
        };
        let _ = apply_cluster_freq_controls(4, min, max);
    }
    if state.cpu_min_freq7 > 0 || state.cpu_max_freq7 > 0 {
        let min = if state.cpu_min_freq7 > 0 {
            state.cpu_min_freq7
        } else {
            1000
        };
        let max = if state.cpu_max_freq7 > 0 {
            state.cpu_max_freq7
        } else {
            3250
        };
        let _ = apply_cluster_freq_controls(7, min, max);
    }

    if state.gpu_uncap == 1 {
        let _ = set_gpu_uncap(true);
    } else {
        if !state.gpu_power_policy.is_empty() {
            let _ = set_gpu_power_policy(&state.gpu_power_policy);
        }
        if state.gpu_min_freq_mhz > 0 {
            let _ = set_gpu_min_freq(state.gpu_min_freq_mhz);
        }
        if state.gpu_max_freq_mhz > 0 {
            let _ = set_gpu_max_freq(state.gpu_max_freq_mhz);
        }
        if !state.gpu_governor.is_empty() {
            let _ = set_gpu_governor(&state.gpu_governor);
        }
        if state.gpu_ged_boost >= 0 {
            let _ = set_gpu_ged_boost(state.gpu_ged_boost == 1);
        }
    }
}

fn late_boot_restore_loop() {
    // Framework and vendor power/touch services can publish defaults after a
    // root module starts. Repeat the complete saved-state transaction across
    // that settling window; this is independent of the Android app process.
    for (attempt, delay_seconds) in [2u64, 4, 8].into_iter().enumerate() {
        std::thread::sleep(Duration::from_secs(delay_seconds));
        restore_persisted_state();
        let runtime_result = reassert_runtime_state(true);
        reassert_persisted_governors();
        eprintln!(
            "RODIN_BOOT_RESTORE attempt={} touch_ack={} runtime_ok={}",
            attempt + 1,
            TOUCH_APPLY_ACK.load(Ordering::Acquire),
            i32::from(runtime_result.is_ok()),
        );
    }
}

fn reassert_persisted_governors() {
    let Ok(_profile_guard) = gpu_profile_apply_lock().try_lock() else {
        return;
    };

    let state = persisted_state()
        .lock()
        .ok()
        .map(|s| s.clone())
        .unwrap_or_default();

    if matches!(state.charging, 0 | 8) {
        let desired = if state.charging == 8 { "8" } else { "0" };
        if read_trimmed(charging_path())
            .map(|actual| actual != desired)
            .unwrap_or(true)
        {
            let _ = write_verified(&charging_path(), desired);
        }
    }

    if state.cpu_manual == 1 {
        let desired_mask = (state.cpu_online_mask | 0x01) & 0xFF;
        if live_cpu_mask() != desired_mask {
            let _ = set_core_ctl_enabled(false).and_then(|_| apply_saved_cpu_mask(desired_mask));
        }
    }

    for (policy, desired) in [
        (0, state.cpu0.as_str()),
        (4, state.cpu4.as_str()),
        (7, state.cpu7.as_str()),
    ] {
        if desired.is_empty() {
            continue;
        }

        let actual = policy_governor(policy);

        if actual != desired {
            let _ = set_cpu_governor(policy, desired);
        }
    }

    // Stock mode is owned by MediaTek's power HAL. Tuned profiles use the
    // persisted desired state as their single source of truth, so the guard
    // cannot fight a second hard-coded profile writer.
    if state.perf != 0 {
        let target_gpu = if !state.gpu_governor.is_empty() {
            state.gpu_governor.as_str()
        } else if !state.gpu.is_empty() {
            state.gpu.as_str()
        } else {
            "simple_ondemand"
        };

        if gpu_get_governor() != target_gpu {
            let _ = set_gpu_governor(target_gpu);
        }
        if state.gpu_min_freq_mhz > 0 && gpu_get_min_freq_mhz() != state.gpu_min_freq_mhz {
            let _ = set_gpu_min_freq(state.gpu_min_freq_mhz);
        }
        if state.gpu_max_freq_mhz > 0 && gpu_get_max_freq_mhz() != state.gpu_max_freq_mhz {
            let _ = set_gpu_max_freq(state.gpu_max_freq_mhz);
        }
        if !state.gpu_power_policy.is_empty() && gpu_get_power_policy() != state.gpu_power_policy {
            let _ = set_gpu_power_policy(&state.gpu_power_policy);
        }

        if state.gpu_uncap == 1 {
            // Do not freeze a lower boot OPP. This step leaves DVFS enabled
            // until the live frequency reaches 1300 MHz, then locks it.
            let _ = arm_or_lock_beast_gpu();
        } else if gpu_get_dvfs_enabled() != 1 {
            let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
        }
    }

    // GED boost is profile-owned. Keep all three MediaTek boost flags enabled
    // only for Gaming Dynamic and Extreme Beast, including while Stock is
    // otherwise left under the vendor power HAL.
    let desired_ged_boost = profile_uses_ged_boost(state.perf);
    if !gpu_boost_pipeline_matches(desired_ged_boost) {
        let _ = set_gpu_ged_boost(desired_ged_boost);
    }

    PERFORMANCE_PROFILE_VERIFIED.store(1, Ordering::Release);
    PERFORMANCE_PROFILE_OK.store(
        if gpu_profile_verified(state.perf) {
            1
        } else {
            0
        },
        Ordering::Release,
    );

    if !state.io.is_empty() && io_scheduler() != state.io {
        let _ = set_io_scheduler(&state.io);
    }

    let desired_zram_alg = if !state.zram_algorithm.is_empty() {
        state.zram_algorithm.as_str()
    } else {
        "lz4"
    };
    if zram_get_algorithm() != desired_zram_alg {
        let _ = set_zram_algorithm(desired_zram_alg);
    }

    if state.zram_swappiness >= 0 && zram_get_swappiness() != state.zram_swappiness {
        let _ = set_zram_swappiness(state.zram_swappiness);
    }

    if state.zram_size_mb > 0 && zram_get_disksize_mb() != state.zram_size_mb {
        let _ = set_zram_size(state.zram_size_mb);
    }
}

fn cpu_frequency_guard() {
    loop {
        let mut has_saved_range = false;

        if let Ok(_guard) = cpu_freq_apply_lock().try_lock() {
            let state = persisted_state()
                .lock()
                .ok()
                .map(|state| state.clone())
                .unwrap_or_default();

            for (policy, min_mhz, max_mhz) in [
                (0, state.cpu_min_freq0, state.cpu_max_freq0),
                (4, state.cpu_min_freq4, state.cpu_max_freq4),
                (7, state.cpu_min_freq7, state.cpu_max_freq7),
            ] {
                if min_mhz <= 0 || max_mhz <= 0 {
                    continue;
                }

                has_saved_range = true;
                if get_cpu_cluster_live_min_freq(policy) != min_mhz
                    || get_cpu_cluster_live_max_freq(policy) != max_mhz
                {
                    let _ = apply_cluster_freq_controls_unlocked(policy, min_mhz, max_mhz);
                }
            }
        } else {
            // A foreground apply is already in progress. Check again quickly
            // after that transaction releases the shared CPU control lock.
            has_saved_range = true;
        }

        std::thread::sleep(Duration::from_millis(if has_saved_range {
            100
        } else {
            500
        }));
    }
}

fn gaming_dynamic_guard() {
    let mut last_written_opp = -1;
    let mut smoothed_load = 0;
    let mut boost_until = Instant::now();

    loop {
        let Ok(profile_guard) = gpu_profile_apply_lock().try_lock() else {
            std::thread::sleep(Duration::from_millis(20));
            continue;
        };

        let profile = persisted_state()
            .lock()
            .ok()
            .map(|state| state.perf)
            .unwrap_or(0);

        let desired_ged_boost = profile_uses_ged_boost(profile);
        if !gpu_boost_pipeline_matches(desired_ged_boost) {
            let _ = set_gpu_ged_boost(desired_ged_boost);
        }

        if !desired_ged_boost {
            last_written_opp = -1;
            smoothed_load = 0;
            boost_until = Instant::now();
            drop(profile_guard);
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }

        // Gaming and Beast own only the Mali cooling device. The vendor thermal
        // services remain running for CPU and platform management while this
        // guard prevents a GPU cooling cap from replacing their 1300 MHz target.
        let _ = fs::write("/sys/class/thermal/cooling_device3/cur_state", "0");

        if profile == 3 {
            // MediaTek's power HAL can publish its stock OPP 40 target after
            // boot completion. Reassert every Beast-owned node and lock DVFS
            // only after GED confirms that OPP 0 is actually live.
            let _ = arm_or_lock_beast_gpu();
            drop(profile_guard);
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }

        let load = gpu_get_loading();
        smoothed_load = ((smoothed_load * 3) + load) / 4;
        let now = Instant::now();

        // The MT6899 accepts the generic simple_ondemand governor name but
        // does not drive the MediaTek GED OPP policy from it. GED's custom
        // boost node is an OPP floor (0 = fastest, last = slowest), so use it
        // as the real on-demand actuator while retaining the requested
        // governor and the full unrestricted frequency table.
        if load >= 85 {
            boost_until = now + Duration::from_millis(500);
        }

        let lowest_opp = gpu_get_lowest_opp_index();
        let current_opp = gpu_get_cur_opp_index();
        let target_opp = if now < boost_until {
            0
        } else {
            gaming_dynamic_target_opp(smoothed_load, current_opp, lowest_opp)
        };

        if target_opp != last_written_opp
            && fs::write(
                "/sys/kernel/ged/hal/custom_boost_gpu_freq",
                target_opp.to_string(),
            )
            .is_ok()
        {
            last_written_opp = target_opp;
        }

        drop(profile_guard);
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn maintenance_loop() {
    let mut last_package = String::new();
    let mut last_profile: i32 = -99;

    let mut _last_apply = Instant::now()
        .checked_sub(Duration::from_secs(10))
        .unwrap_or_else(Instant::now);

    let mut last_guard = Instant::now()
        .checked_sub(Duration::from_secs(10))
        .unwrap_or_else(Instant::now);

    let mut last_packages = Instant::now()
        .checked_sub(Duration::from_secs(35))
        .unwrap_or_else(Instant::now);

    let mut last_screen_check = Instant::now()
        .checked_sub(Duration::from_secs(5))
        .unwrap_or_else(Instant::now);

    let mut last_keepalive = Instant::now()
        .checked_sub(Duration::from_secs(65))
        .unwrap_or_else(Instant::now);

    let mut last_display_refresh = Instant::now()
        .checked_sub(Duration::from_secs(12))
        .unwrap_or_else(Instant::now);

    let mut screen_was_on: Option<bool> = None;

    loop {
        let state = persisted_state()
            .lock()
            .ok()
            .map(|guard| guard.clone())
            .unwrap_or_default();

        if state.perapp_enabled == 1 {
            let current_pkg = foreground_package();
            if let Some(pkg) = current_pkg.as_ref()
                && pkg != "io.github.neeschal.rodinessential"
                && let Ok(mut slot) = last_external_package().lock()
            {
                *slot = pkg.clone();
            }
            let package = current_pkg.unwrap_or_default();

            let selected = if package.is_empty() || package == "io.github.neeschal.rodinessential" {
                state.perf
            } else {
                state
                    .app_profiles
                    .get(&package)
                    .copied()
                    .unwrap_or(state.perf)
            };

            if package != last_package || selected != last_profile {
                match apply_performance_profile(selected) {
                    Ok(()) => {
                        ACTIVE_PER_APP_PROFILE.store(selected, Ordering::Release);
                        LAST_PER_APP_PROFILE.store(selected, Ordering::Release);
                        PER_APP_APPLY_ACK.store(1, Ordering::Release);
                        last_profile = selected;
                        last_package = package;
                        _last_apply = Instant::now();
                    }
                    Err(_) => {
                        PER_APP_APPLY_ACK.store(0, Ordering::Release);
                    }
                }
            }
        } else {
            ACTIVE_PER_APP_PROFILE.store(-1, Ordering::Release);
            LAST_PER_APP_PROFILE.store(-1, Ordering::Release);
            last_profile = -99;
            last_package.clear();
        }

        if last_guard.elapsed() >= Duration::from_millis(500) {
            reassert_persisted_governors();
            last_guard = Instant::now();
        }

        if last_packages.elapsed() >= Duration::from_secs(30) {
            let _ = prune_stale_profiles();
            last_packages = Instant::now();
        }

        if last_display_refresh.elapsed() >= Duration::from_secs(10) {
            refresh_display_info();
            last_display_refresh = Instant::now();
        }

        if last_screen_check.elapsed() >= Duration::from_secs(3) {
            if let Some(screen_on) = screen_is_on() {
                let woke = screen_was_on == Some(false) && screen_on;

                if woke {
                    std::thread::sleep(Duration::from_millis(300));
                    let _ = reassert_runtime_state(true);
                    last_keepalive = Instant::now();
                } else if screen_on && last_keepalive.elapsed() >= Duration::from_secs(60) {
                    let _ = reassert_runtime_state(false);
                    last_keepalive = Instant::now();
                }

                screen_was_on = Some(screen_on);
            }

            last_screen_check = Instant::now();
        }

        std::thread::sleep(Duration::from_millis(1500));
    }
}

pub fn start_background_services() {
    let _ = persisted_state();
    refresh_display_info();
    // Older releases stopped global thermal services for GPU profiles. Keep
    // vendor CPU and platform thermal management alive in every GPU mode.
    ensure_vendor_thermal_services_running();
    // Persisted custom touch profiles can be restored below, so the worker
    // must be ready before set_touch_profile() waits for its attachment ACK.
    touch_resampler::start_background();
    restore_persisted_state();
    std::thread::spawn(late_boot_restore_loop);
    std::thread::spawn(maintenance_loop);
    std::thread::spawn(cpu_frequency_guard);
    std::thread::spawn(gaming_dynamic_guard);
}

// ZRAM & MEMORY TUNING HELPERS

fn zram_get_disksize_mb() -> i32 {
    if let Ok(raw) = fs::read_to_string("/sys/block/zram0/disksize")
        && let Ok(bytes) = raw.trim().parse::<u64>()
    {
        return (bytes / (1024 * 1024)) as i32;
    }
    0
}

fn zram_get_swappiness() -> i32 {
    if let Ok(raw) = fs::read_to_string("/proc/sys/vm/swappiness")
        && let Ok(v) = raw.trim().parse::<i32>()
    {
        return v;
    }
    100
}

fn zram_get_algorithm() -> String {
    if let Ok(raw) = fs::read_to_string("/sys/block/zram0/comp_algorithm") {
        for token in raw.split_whitespace() {
            if token.starts_with('[') && token.ends_with(']') {
                return token[1..token.len() - 1].to_string();
            }
        }
    }
    "lz4".to_string()
}

struct ZramMmStat {
    orig_data_mb: i32,
    compr_data_mb: i32,
    mem_used_mb: i32,
}

fn zram_get_mm_stat() -> ZramMmStat {
    if let Ok(raw) = fs::read_to_string("/sys/block/zram0/mm_stat") {
        let parts: Vec<&str> = raw.split_whitespace().collect();
        if parts.len() >= 3 {
            let orig = parts[0].parse::<u64>().unwrap_or(0) / (1024 * 1024);
            let compr = parts[1].parse::<u64>().unwrap_or(0) / (1024 * 1024);
            let used = parts[2].parse::<u64>().unwrap_or(0) / (1024 * 1024);
            return ZramMmStat {
                orig_data_mb: orig as i32,
                compr_data_mb: compr as i32,
                mem_used_mb: used as i32,
            };
        }
    }
    ZramMmStat {
        orig_data_mb: 0,
        compr_data_mb: 0,
        mem_used_mb: 0,
    }
}

fn set_zram_size(size_mb: i32) -> Result<(), String> {
    if !(0..=32768).contains(&size_mb) {
        return Err("invalid ZRAM size".to_string());
    }

    // 1. Drop pagecache to relieve RAM before swapoff
    let _ = fs::write("/proc/sys/vm/drop_caches", "3");

    // 2. swapoff /dev/block/zram0
    let _ = ProcessCommand::new("/system/bin/swapoff")
        .arg("/dev/block/zram0")
        .output();

    // 3. Reset zram
    fs::write("/sys/block/zram0/reset", "1").map_err(|e| format!("zram reset failed: {e}"))?;

    // 3.5. Reapply configured compression algorithm before setting disksize!
    let target_alg = persisted_state()
        .lock()
        .ok()
        .map(|s| {
            if !s.zram_algorithm.is_empty() {
                s.zram_algorithm.clone()
            } else {
                "lz4".to_string()
            }
        })
        .unwrap_or_else(|| "lz4".to_string());
    let _ = fs::write("/sys/block/zram0/comp_algorithm", &target_alg);

    if size_mb == 0 {
        mutate_persisted_state(|state| {
            state.zram_size_mb = 0;
        });
        return Ok(());
    }

    // 4. Write new disksize
    let bytes = (size_mb as u64) * 1024 * 1024;
    fs::write("/sys/block/zram0/disksize", bytes.to_string())
        .map_err(|e| format!("zram disksize failed: {e}"))?;

    // 5. mkswap
    let mkswap_res = ProcessCommand::new("/system/bin/mkswap")
        .arg("/dev/block/zram0")
        .output()
        .map_err(|e| format!("mkswap failed: {e}"))?;

    if !mkswap_res.status.success() {
        return Err("mkswap failed".to_string());
    }

    // 6. swapon
    let swapon_res = ProcessCommand::new("/system/bin/swapon")
        .args(["-p", "32758", "/dev/block/zram0"])
        .output();

    if let Ok(res) = swapon_res
        && !res.status.success()
    {
        let _ = ProcessCommand::new("/system/bin/swapon")
            .arg("/dev/block/zram0")
            .output();
    }

    mutate_persisted_state(|state| {
        state.zram_size_mb = size_mb;
    });

    Ok(())
}

fn set_zram_algorithm(alg: &str) -> Result<(), String> {
    let alg = alg.trim();
    if !matches!(alg, "lz4" | "zstd" | "lzo-rle" | "lzo") {
        return Err("unsupported compression algorithm".to_string());
    }

    let current_size_mb = zram_get_disksize_mb();

    let _ = fs::write("/proc/sys/vm/drop_caches", "3");
    let _ = ProcessCommand::new("/system/bin/swapoff")
        .arg("/dev/block/zram0")
        .output();

    let _ = fs::write("/sys/block/zram0/reset", "1");

    fs::write("/sys/block/zram0/comp_algorithm", alg)
        .map_err(|e| format!("comp_algorithm failed: {e}"))?;

    if current_size_mb > 0 {
        let bytes = (current_size_mb as u64) * 1024 * 1024;
        let _ = fs::write("/sys/block/zram0/disksize", bytes.to_string());
        let _ = ProcessCommand::new("/system/bin/mkswap")
            .arg("/dev/block/zram0")
            .output();
        let _ = ProcessCommand::new("/system/bin/swapon")
            .args(["-p", "32758", "/dev/block/zram0"])
            .output();
    }

    mutate_persisted_state(|state| {
        state.zram_algorithm = alg.to_string();
    });

    Ok(())
}

fn set_zram_swappiness(val: i32) -> Result<(), String> {
    if !(0..=200).contains(&val) {
        return Err("invalid swappiness value (0-200)".to_string());
    }

    fs::write("/proc/sys/vm/swappiness", val.to_string())
        .map_err(|e| format!("swappiness write failed: {e}"))?;

    mutate_persisted_state(|state| {
        state.zram_swappiness = val;
    });

    Ok(())
}

fn compact_zram() -> Result<(), String> {
    fs::write("/sys/block/zram0/compact", "1").map_err(|e| format!("compact failed: {e}"))?;
    Ok(())
}

// MALI GPU & MEDIATEK GED HELPERS

fn gpu_read_file(primary: &str, fallback: &str) -> Option<String> {
    fs::read_to_string(primary)
        .or_else(|_| fs::read_to_string(fallback))
        .ok()
}

fn gpu_write_file(primary: &str, fallback: &str, value: &str) {
    let _ = fs::write(primary, value);
    let _ = fs::write(fallback, value);
}

fn gpu_read_raw(path: &str) -> Option<String> {
    use std::io::Read;
    let mut f = fs::File::open(path).ok()?;
    let mut buf = [0u8; 256];
    let n = f.read(&mut buf).ok()?;
    if n == 0 {
        return None;
    }
    String::from_utf8(buf[..n].to_vec()).ok()
}

fn gpu_get_loading() -> i32 {
    if let Some(s) = gpu_read_raw("/sys/kernel/ged/hal/gpu_utilization")
        && let Some(first) = s.split_whitespace().next()
        && let Ok(val) = first.parse::<i32>()
    {
        return val.clamp(0, 100);
    }
    gpu_read_raw("/sys/module/ged/parameters/gpu_loading")
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn gpu_get_cur_opp_index() -> i32 {
    gpu_read_raw("/sys/kernel/ged/hal/current_freqency")
        .and_then(|value| {
            value
                .split_whitespace()
                .next()
                .and_then(|part| part.parse::<i32>().ok())
        })
        .unwrap_or(40)
}

fn gpu_get_lowest_opp_index() -> i32 {
    gpu_read_raw("/sys/kernel/ged/hal/total_gpu_freq_level_count")
        .and_then(|value| {
            value
                .split_whitespace()
                .next()
                .and_then(|part| part.parse::<i32>().ok())
        })
        .map(|count| count.saturating_sub(1))
        .or_else(|| {
            gpu_read_raw("/sys/class/devfreq/13000000.mali/available_frequencies")
                .map(|value| value.split_whitespace().count().saturating_sub(1) as i32)
        })
        .unwrap_or(40)
        .clamp(0, 255)
}

fn gaming_dynamic_target_opp(load: i32, current_opp: i32, lowest_opp: i32) -> i32 {
    let load = load.clamp(0, 100);
    let current_opp = current_opp.clamp(0, lowest_opp);

    if load >= 85 {
        0
    } else if load >= 70 {
        current_opp.saturating_sub(8)
    } else if load >= 55 {
        current_opp.saturating_sub(4)
    } else if load >= 40 {
        current_opp.saturating_sub(2)
    } else if load <= 10 {
        lowest_opp
    } else if load <= 20 {
        (current_opp + 8).min(lowest_opp)
    } else if load <= 30 {
        (current_opp + 4).min(lowest_opp)
    } else {
        current_opp
    }
}

fn parse_ged_current_frequency_mhz(raw: &str) -> Option<i32> {
    let value = raw
        .split_whitespace()
        .filter_map(|part| part.parse::<i64>().ok())
        .next_back()?;

    if value <= 0 {
        None
    } else if value > 10_000_000 {
        Some((value / 1_000_000) as i32)
    } else if value > 1_300 {
        Some((value / 1_000) as i32)
    } else {
        Some(value as i32)
    }
}

fn gpu_get_cur_freq_mhz() -> i32 {
    // MediaTek GED reports the active OPP (for example `40 260000`). The
    // generic devfreq node can expose a 26 MHz deep-idle clock instead, which
    // is useful for power debugging but not the live OPP selected by GED.
    if let Some(mhz) = gpu_read_raw("/sys/kernel/ged/hal/current_freqency")
        .as_deref()
        .and_then(parse_ged_current_frequency_mhz)
    {
        return mhz;
    }

    gpu_read_raw("/sys/class/devfreq/13000000.mali/cur_freq")
        .or_else(|| gpu_read_raw("/sys/class/misc/mali0/device/devfreq/13000000.mali/cur_freq"))
        .and_then(|s| s.trim().parse::<i64>().ok())
        .filter(|hz| *hz > 0)
        .map(|hz| (hz / 1_000_000) as i32)
        .unwrap_or(0)
}

fn gpu_get_min_freq_mhz() -> i32 {
    gpu_read_file(
        "/sys/class/devfreq/13000000.mali/min_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
    )
    .and_then(|s| s.trim().parse::<i64>().ok())
    .map(|hz| (hz / 1_000_000) as i32)
    .unwrap_or(260)
}

fn gpu_get_max_freq_mhz() -> i32 {
    gpu_read_file(
        "/sys/class/devfreq/13000000.mali/max_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
    )
    .and_then(|s| s.trim().parse::<i64>().ok())
    .map(|hz| (hz / 1_000_000) as i32)
    .unwrap_or(650)
}

fn gpu_get_governor() -> String {
    gpu_read_file(
        "/sys/class/devfreq/13000000.mali/governor",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
    )
    .map(|s| s.trim().to_string())
    .unwrap_or_else(|| "simple_ondemand".to_string())
}

fn gpu_get_ged_master_flag() -> i32 {
    fs::read_to_string("/sys/module/ged/parameters/ged_boost_enable")
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn gpu_flag(path: &str) -> i32 {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(-1)
}

fn gpu_get_ged_boost() -> i32 {
    if gpu_get_ged_master_flag() == 1
        && gpu_flag("/sys/module/ged/parameters/boost_gpu_enable") == 1
        && gpu_flag("/sys/module/ged/parameters/ged_smart_boost") == 1
    {
        1
    } else {
        0
    }
}

fn gpu_boost_pipeline_matches(enabled: bool) -> bool {
    let expected = if enabled { 1 } else { 0 };
    gpu_get_ged_master_flag() == expected
        && gpu_flag("/sys/module/ged/parameters/boost_gpu_enable") == expected
        && gpu_flag("/sys/module/ged/parameters/ged_smart_boost") == expected
}

fn gpu_get_thermal_state() -> i32 {
    fs::read_to_string("/sys/class/thermal/cooling_device3/cur_state")
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(-1)
}

fn gpu_get_dvfs_enabled() -> i32 {
    fs::read_to_string("/sys/module/ged/parameters/gpu_dvfs_enable")
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(-1)
}

fn gpu_get_uncap_active() -> i32 {
    if gpu_get_min_freq_mhz() == 1300
        && gpu_get_max_freq_mhz() == 1300
        && gpu_get_cur_freq_mhz() == 1300
        && gpu_get_governor() == "performance"
        && gpu_get_dvfs_enabled() == 0
        && gpu_get_power_policy() == "always_on"
    {
        1
    } else {
        0
    }
}

fn gpu_profile_verified(profile: i32) -> bool {
    let min = gpu_get_min_freq_mhz();
    let max = gpu_get_max_freq_mhz();
    let governor = gpu_get_governor();
    let dvfs = gpu_get_dvfs_enabled();
    let power_policy = gpu_get_power_policy();

    match profile {
        3 => {
            min == 1300
                && max == 1300
                && gpu_get_cur_freq_mhz() == 1300
                && governor == "performance"
                && gpu_boost_pipeline_matches(true)
                && dvfs == 0
                && power_policy == "always_on"
        }
        1 => {
            min == 260
                && max == 1300
                && governor == "simple_ondemand"
                && gpu_boost_pipeline_matches(true)
                && dvfs == 1
                && power_policy == "always_on"
        }
        2 => {
            min == 260
                && max == 598
                && governor == "powersave"
                && gpu_boost_pipeline_matches(false)
                && dvfs == 1
                && power_policy == "coarse_demand"
        }
        _ => {
            governor == "dummy"
                && gpu_boost_pipeline_matches(false)
                && dvfs == 1
                && power_policy == "coarse_demand"
        }
    }
}

fn gpu_profile_configured(profile: i32) -> bool {
    let min = gpu_get_min_freq_mhz();
    let max = gpu_get_max_freq_mhz();
    let governor = gpu_get_governor();
    let dvfs = gpu_get_dvfs_enabled();
    let power_policy = gpu_get_power_policy();
    let thermal_limited = gpu_get_thermal_state() > 0;

    match profile {
        3 => {
            min == 1300
                && max == 1300
                && gpu_get_cur_freq_mhz() == 1300
                && governor == "performance"
                && gpu_boost_pipeline_matches(true)
                && dvfs == 0
                && power_policy == "always_on"
        }
        1 => {
            min == 260
                && (max == 1300 || (thermal_limited && (260..1300).contains(&max)))
                && governor == "simple_ondemand"
                && gpu_boost_pipeline_matches(true)
                && dvfs == 1
                && power_policy == "always_on"
        }
        2 => {
            min == 260
                && (max == 598 || (thermal_limited && max < 598))
                && governor == "powersave"
                && gpu_boost_pipeline_matches(false)
                && dvfs == 1
                && power_policy == "coarse_demand"
        }
        _ => {
            governor == "dummy"
                && gpu_boost_pipeline_matches(false)
                && dvfs == 1
                && power_policy == "coarse_demand"
        }
    }
}

fn set_gpu_min_freq(mhz: i32) -> Result<(), String> {
    let mhz = mhz.clamp(260, 1300);
    let hz = (mhz as u64) * 1_000_000;
    let khz = (mhz as u64) * 1_000;
    let opp_boost = ((1300 - mhz) / 26).clamp(0, 40);
    let _ = fs::write(
        "/sys/kernel/ged/hal/custom_boost_gpu_freq",
        opp_boost.to_string(),
    );
    gpu_write_file(
        "/sys/class/devfreq/13000000.mali/min_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
        &hz.to_string(),
    );
    let _ = fs::write(
        "/sys/module/ged/parameters/gpu_bottom_freq",
        khz.to_string(),
    );
    let _ = fs::write(
        "/sys/module/ged/parameters/gpu_cust_boost_freq",
        khz.to_string(),
    );
    mutate_persisted_state(|state| {
        state.gpu_min_freq_mhz = mhz;
        if mhz < 1300 {
            state.gpu_uncap = 0;
        }
    });
    Ok(())
}

fn set_gpu_max_freq(mhz: i32) -> Result<(), String> {
    let mhz = mhz.clamp(260, 1300);
    let hz = (mhz as u64) * 1_000_000;
    let khz = (mhz as u64) * 1_000;
    let opp_upbound = ((1300 - mhz) / 26).clamp(0, 40);
    let _ = fs::write(
        "/sys/kernel/ged/hal/custom_upbound_gpu_freq",
        opp_upbound.to_string(),
    );
    gpu_write_file(
        "/sys/class/devfreq/13000000.mali/max_freq",
        "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
        &hz.to_string(),
    );
    let _ = fs::write(
        "/sys/module/ged/parameters/gpu_cust_upbound_freq",
        khz.to_string(),
    );
    mutate_persisted_state(|state| {
        state.gpu_max_freq_mhz = mhz;
        if mhz < 1300 {
            state.gpu_uncap = 0;
        }
    });
    Ok(())
}

fn set_gpu_ged_boost(enable: bool) -> Result<(), String> {
    let active_profile = PERFORMANCE_STATE.load(Ordering::Acquire);
    let required = profile_uses_ged_boost(active_profile);
    if enable != required {
        return Err(format!(
            "GED boost is controlled by GPU profile {active_profile}: expected {}",
            if required { "on" } else { "off" }
        ));
    }

    let val = if enable { "1" } else { "0" };
    let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", val);
    let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", val);
    let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", val);
    mutate_persisted_state(|state| {
        state.gpu_ged_boost = if enable { 1 } else { 0 };
    });
    Ok(())
}

fn set_gpu_uncap(enable: bool) -> Result<(), String> {
    let mut beast_locked = true;

    if enable {
        clear_gpu_cooling_cap();
        beast_locked = settle_beast_gpu_lock(60, Duration::from_millis(25));
    } else {
        let _ = fs::write("/sys/class/misc/mali0/device/power_policy", "coarse_demand");
        let _ = fs::write("/sys/kernel/ged/hal/custom_boost_gpu_freq", "40");
        let _ = fs::write("/sys/kernel/ged/hal/custom_upbound_gpu_freq", "0");
        let _ = fs::write("/sys/kernel/ged/hal/gpu_boost_level", "0");
        gpu_write_file(
            "/sys/class/devfreq/13000000.mali/min_freq",
            "/sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq",
            "260000000",
        );
        gpu_write_file(
            "/sys/class/devfreq/13000000.mali/max_freq",
            "/sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq",
            "1300000000",
        );
        let _ = fs::write("/sys/module/ged/parameters/gpu_bottom_freq", "260000");
        let _ = fs::write("/sys/module/ged/parameters/gpu_cust_boost_freq", "260000");
        let _ = fs::write(
            "/sys/module/ged/parameters/gpu_cust_upbound_freq",
            "1300000",
        );
        let _ = fs::write("/sys/module/ged/parameters/gpu_dvfs_enable", "1");
        let _ = fs::write("/sys/module/ged/parameters/ged_boost_enable", "0");
        let _ = fs::write("/sys/module/ged/parameters/boost_gpu_enable", "0");
        let _ = fs::write("/sys/module/ged/parameters/ged_smart_boost", "0");
        gpu_write_file(
            "/sys/class/devfreq/13000000.mali/governor",
            "/sys/class/misc/mali0/device/devfreq/13000000.mali/governor",
            "simple_ondemand",
        );
    }
    mutate_persisted_state(|state| {
        state.gpu_uncap = if enable { 1 } else { 0 };
        if enable {
            state.gpu_min_freq_mhz = 1300;
            state.gpu_max_freq_mhz = 1300;
            state.gpu_ged_boost = 1;
            state.gpu_power_policy = "always_on".to_string();
            state.gpu = "performance".to_string();
            state.gpu_governor = "performance".to_string();
        } else {
            state.gpu_min_freq_mhz = 260;
            state.gpu_max_freq_mhz = 1300;
            state.gpu_ged_boost = 0;
            state.gpu_power_policy = "coarse_demand".to_string();
            state.gpu = "simple_ondemand".to_string();
            state.gpu_governor = "simple_ondemand".to_string();
        }
    });

    if enable && !beast_locked {
        Err("Beast OPP 0 is armed and will lock when the GPU becomes active".into())
    } else {
        Ok(())
    }
}

fn gpu_get_power_policy() -> String {
    fs::read_to_string("/sys/class/misc/mali0/device/power_policy")
        .ok()
        .map(|s| {
            if s.contains("[always_on]") {
                "always_on".to_string()
            } else if s.contains("[coarse_demand]") {
                "coarse_demand".to_string()
            } else {
                s.trim().to_string()
            }
        })
        .unwrap_or_else(|| {
            persisted_state()
                .lock()
                .ok()
                .map(|s| s.gpu_power_policy.clone())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "coarse_demand".to_string())
        })
}

fn set_gpu_power_policy(policy: &str) -> Result<(), String> {
    let valid = match policy.trim() {
        "always_on" | "1" => "always_on",
        _ => "coarse_demand",
    };
    let _ = fs::write("/sys/class/misc/mali0/device/power_policy", valid);
    mutate_persisted_state(|state| {
        state.gpu_power_policy = valid.to_string();
    });
    Ok(())
}

fn snapshot_persistence_fields() -> Vec<String> {
    let state = persisted_state()
        .lock()
        .ok()
        .map(|s| s.clone())
        .unwrap_or_default();

    let cpu0_drift = drift_status(&state.cpu0, &policy_governor(0));
    let cpu4_drift = drift_status(&state.cpu4, &policy_governor(4));
    let cpu7_drift = drift_status(&state.cpu7, &policy_governor(7));
    let desired_gpu_governor = if !state.gpu_governor.is_empty() {
        state.gpu_governor.as_str()
    } else {
        state.gpu.as_str()
    };
    let gpu_drift = drift_status(desired_gpu_governor, &gpu_governor());
    let io_drift = drift_status(&state.io, &io_scheduler());
    let cpu_live_min0 = get_cpu_cluster_live_min_freq(0);
    let cpu_live_max0 = get_cpu_cluster_live_max_freq(0);
    let cpu_live_min4 = get_cpu_cluster_live_min_freq(4);
    let cpu_live_max4 = get_cpu_cluster_live_max_freq(4);
    let cpu_live_min7 = get_cpu_cluster_live_min_freq(7);
    let cpu_live_max7 = get_cpu_cluster_live_max_freq(7);
    let cpu_freq_drift0 = cpu_frequency_drift_status(
        state.cpu_min_freq0,
        state.cpu_max_freq0,
        cpu_live_min0,
        cpu_live_max0,
    );
    let cpu_freq_drift4 = cpu_frequency_drift_status(
        state.cpu_min_freq4,
        state.cpu_max_freq4,
        cpu_live_min4,
        cpu_live_max4,
    );
    let cpu_freq_drift7 = cpu_frequency_drift_status(
        state.cpu_min_freq7,
        state.cpu_max_freq7,
        cpu_live_min7,
        cpu_live_max7,
    );

    let zram_stat = zram_get_mm_stat();
    let zram_disk_mb = zram_get_disksize_mb();
    let zram_swappiness = zram_get_swappiness();
    let zram_alg = zram_get_algorithm();

    vec![
        "phase=16".to_string(),
        format!("dt2w={}", state.dt2w),
        format!("expert_gamut={}", state.expert_gamut),
        format!("expert_1={}", state.expert[0]),
        format!("expert_2={}", state.expert[1]),
        format!("expert_3={}", state.expert[2]),
        format!("expert_4={}", state.expert[3]),
        format!("expert_5={}", state.expert[4]),
        format!("expert_6={}", state.expert[5]),
        format!("expert_7={}", state.expert[6]),
        format!("expert_8={}", state.expert[7]),
        format!(
            "perf_supported={}",
            PERFORMANCE_PROFILE_SUPPORTED.load(Ordering::Acquire)
        ),
        format!(
            "perf_verified={}",
            PERFORMANCE_PROFILE_VERIFIED.load(Ordering::Acquire)
        ),
        format!(
            "perf_verify_ok={}",
            PERFORMANCE_PROFILE_OK.load(Ordering::Acquire)
        ),
        format!(
            "gpu_profile_cpu_isolated={}",
            state.gpu_profile_cpu_isolated
        ),
        format!("cpu_drift0={cpu0_drift}"),
        format!("cpu_drift4={cpu4_drift}"),
        format!("cpu_drift7={cpu7_drift}"),
        format!("gpu_drift={gpu_drift}"),
        format!("io_drift={io_drift}"),
        format!("perapp_enabled={}", state.perapp_enabled),
        format!(
            "perapp_active={}",
            ACTIVE_PER_APP_PROFILE.load(Ordering::Acquire)
        ),
        format!("perapp_count={}", state.app_profiles.len()),
        format!("display_width={}", DISPLAY_WIDTH.load(Ordering::Acquire)),
        format!("display_height={}", DISPLAY_HEIGHT.load(Ordering::Acquire)),
        format!(
            "display_density={}",
            DISPLAY_DENSITY.load(Ordering::Acquire)
        ),
        format!(
            "display_native_density={}",
            DISPLAY_NATIVE_DENSITY.load(Ordering::Acquire)
        ),
        format!("display_hz_x10={}", DISPLAY_HZ_X10.load(Ordering::Acquire)),
        format!(
            "display_max_hz_x10={}",
            DISPLAY_MAX_HZ_X10.load(Ordering::Acquire)
        ),
        format!(
            "persistence_loaded={}",
            PERSISTENCE_LOADED.load(Ordering::Acquire)
        ),
        format!(
            "sunlight_saved={}",
            if state.brightness_prev >= 1 { 1 } else { 0 }
        ),
        format!("display_ack={}", DISPLAY_APPLY_ACK.load(Ordering::Acquire)),
        format!("touch_ack={}", TOUCH_APPLY_ACK.load(Ordering::Acquire)),
        format!(
            "perapp_apply_ack={}",
            PER_APP_APPLY_ACK.load(Ordering::Acquire)
        ),
        format!(
            "perapp_last_profile={}",
            LAST_PER_APP_PROFILE.load(Ordering::Acquire)
        ),
        format!(
            "perapp_pruned={}",
            PRUNED_APP_PROFILE_COUNT.load(Ordering::Acquire)
        ),
        format!(
            "perapp_last_pkg={}",
            sanitize(
                last_external_package()
                    .lock()
                    .ok()
                    .map(|slot| slot.clone())
                    .unwrap_or_default()
            )
        ),
        format!("perapp_map={}", serialize_app_profiles(&state)),
        format!("cpu_manual={}", state.cpu_manual),
        format!("cpu_saved_mask={}", state.cpu_online_mask | 0x01),
        format!("cpu_write_ack={}", CPU_WRITE_ACK.load(Ordering::Acquire)),
        format!(
            "core_ctl_nodes={}",
            CORE_CTL_NODE_COUNT.load(Ordering::Acquire)
        ),
        format!(
            "runtime_keepalive_ack={}",
            KEEPALIVE_APPLY_ACK.load(Ordering::Acquire)
        ),
        format!(
            "runtime_keepalive_count={}",
            KEEPALIVE_APPLY_COUNT.load(Ordering::Acquire)
        ),
        format!("zram_size={zram_disk_mb}"),
        format!("zram_orig={}", zram_stat.orig_data_mb),
        format!("zram_compr={}", zram_stat.compr_data_mb),
        format!("zram_used={}", zram_stat.mem_used_mb),
        format!("zram_swappiness={zram_swappiness}"),
        format!("zram_alg={zram_alg}"),
        format!("gpu_load={}", gpu_get_loading()),
        format!("gpu_cur_freq={}", gpu_get_cur_freq_mhz()),
        format!("gpu_min_freq={}", gpu_get_min_freq_mhz()),
        format!("gpu_max_freq={}", gpu_get_max_freq_mhz()),
        format!("gpu_gov={}", gpu_get_governor()),
        format!("gpu_ged_boost={}", gpu_get_ged_boost()),
        format!("gpu_thermal_state={}", gpu_get_thermal_state()),
        format!("gpu_uncap_active={}", gpu_get_uncap_active()),
        format!(
            "gpu_power_policy={}",
            if gpu_get_power_policy() == "always_on" {
                1
            } else {
                0
            }
        ),
        format!("gpu_power_policy_str={}", gpu_get_power_policy()),
        format!("cpu_min0={}", state.cpu_min_freq0),
        format!("cpu_max0={}", state.cpu_max_freq0),
        format!("cpu_min4={}", state.cpu_min_freq4),
        format!("cpu_max4={}", state.cpu_max_freq4),
        format!("cpu_min7={}", state.cpu_min_freq7),
        format!("cpu_max7={}", state.cpu_max_freq7),
        format!("cpu_live_min0={cpu_live_min0}"),
        format!("cpu_live_max0={cpu_live_max0}"),
        format!("cpu_live_min4={cpu_live_min4}"),
        format!("cpu_live_max4={cpu_live_max4}"),
        format!("cpu_live_min7={cpu_live_min7}"),
        format!("cpu_live_max7={cpu_live_max7}"),
        format!(
            "cpu_freq_ack={}",
            CPU_FREQ_WRITE_ACK.load(Ordering::Acquire)
        ),
        format!("cpu_freq_drift0={cpu_freq_drift0}"),
        format!("cpu_freq_drift4={cpu_freq_drift4}"),
        format!("cpu_freq_drift7={cpu_freq_drift7}"),
        format!("cpu_avail0={}", cpu_frequency_table_csv(0)),
        format!("cpu_avail4={}", cpu_frequency_table_csv(4)),
        format!("cpu_avail7={}", cpu_frequency_table_csv(7)),
        format!(
            "touch_sustained_rate={}",
            TOUCH_SUSTAINED_RATE.load(Ordering::Acquire)
        ),
        format!(
            "touch_instant_rate={}",
            TOUCH_INSTANT_RATE.load(Ordering::Acquire)
        ),
        format!("touch_panel={}", TOUCH_PANEL.load(Ordering::Acquire)),
        format!(
            "touch_control_path={}",
            TOUCH_CONTROL_PATH.load(Ordering::Acquire)
        ),
        format!(
            "touch_measured_rate_x10={}",
            touch_resampler::measured_hz_x10()
        ),
        format!(
            "touch_source_rate_x10={}",
            touch_resampler::source_measured_hz_x10()
        ),
        format!(
            "touch_measurement_active={}",
            touch_resampler::measurement_active()
        ),
        format!("touch_resampler_ready={}", touch_resampler::ready_hz()),
        format!(
            "touch_resampler_path={}",
            touch_resampler::attachment_path()
        ),
        format!("touch_resampler_error={}", touch_resampler::last_error()),
        format!(
            "touch_physical_frames={}",
            touch_resampler::physical_frames()
        ),
        format!(
            "touch_injected_frames={}",
            touch_resampler::injected_frames()
        ),
    ]
}

fn snapshot() -> String {
    let charging = read_trimmed(charging_path()).unwrap_or_else(|_| "NA".into());
    let touch_hal = if vendor_binder::touch_available()
        || Path::new("/sys/devices/platform/goodix_ts.0/switch_report_rate").exists()
    {
        1
    } else {
        0
    };
    let display_hal = if vendor_binder::display_available() {
        1
    } else {
        0
    };
    let fields = [
        format!("protocol={PROTOCOL_VERSION}"),
        format!("charging={}", sanitize(charging)),
        format!("cap={}", sanitize(battery("capacity"))),
        format!("temp={}", sanitize(battery("temp"))),
        format!("voltage={}", sanitize(battery("voltage_now"))),
        format!("current={}", sanitize(battery("current_now"))),
        format!("status={}", sanitize(battery("status"))),
        format!("health={}", sanitize(battery("health"))),
        format!(
            "usb_type={}",
            sanitize({
                let real_type = usb("real_type");
                if real_type != "NA" && !real_type.is_empty() {
                    real_type
                } else {
                    usb("usb_type")
                }
            })
        ),
        format!("usb_online={}", sanitize(usb("online"))),
        format!("cpu_online={}", sanitize(read_cpu_online_mask_string())),
        format!("cpu0={}", sanitize(cpu_freq(0))),
        format!("cpu1={}", sanitize(cpu_freq(1))),
        format!("cpu2={}", sanitize(cpu_freq(2))),
        format!("cpu3={}", sanitize(cpu_freq(3))),
        format!("cpu4={}", sanitize(cpu_freq(4))),
        format!("cpu5={}", sanitize(cpu_freq(5))),
        format!("cpu6={}", sanitize(cpu_freq(6))),
        format!("cpu7={}", sanitize(cpu_freq(7))),
        format!("gov0={}", sanitize(policy_governor(0))),
        format!("gov4={}", sanitize(policy_governor(4))),
        format!("gov7={}", sanitize(policy_governor(7))),
        format!("gpu_gov={}", sanitize(gpu_governor())),
        format!("io={}", sanitize(io_scheduler())),
        format!("touch_hal={touch_hal}"),
        format!("display_hal={display_hal}"),
        format!("touch={}", TOUCH_STATE.load(Ordering::Acquire)),
        format!(
            "display_color={}",
            DISPLAY_COLOR_STATE.load(Ordering::Acquire)
        ),
        format!(
            "display_temp={}",
            DISPLAY_TEMP_STATE.load(Ordering::Acquire)
        ),
        format!(
            "sunlight={}",
            DISPLAY_SUNLIGHT_STATE.load(Ordering::Acquire)
        ),
        format!("silky={}", DISPLAY_SILKY_STATE.load(Ordering::Acquire)),
        format!("video={}", DISPLAY_VIDEO_STATE.load(Ordering::Acquire)),
        format!("dolby={}", DISPLAY_DOLBY_STATE.load(Ordering::Acquire)),
        format!("perf={}", PERFORMANCE_STATE.load(Ordering::Acquire)),
    ];
    format!(
        "{};{}",
        fields.join(";"),
        snapshot_persistence_fields().join(";")
    )
}

pub fn handle_command(line: &str) -> String {
    let cmd = line.trim();
    if cmd == "PING" {
        return format!("OK PONG {PROTOCOL_VERSION}");
    }
    if cmd == "GET snapshot" {
        return format!("OK {}", snapshot());
    }

    let result: Result<(), String> = if let Some(arg) = cmd.strip_prefix("SET charging ") {
        let value = match arg.trim() {
            "0" | "standard" => "0",
            "8" | "boost" => "8",
            _ => return "ERR invalid charging mode".into(),
        };
        match write_verified(&charging_path(), value) {
            Ok(actual) if actual == value => Ok(()),
            Ok(actual) => Err(format!("charging verify {actual}")),
            Err(e) => Err(e),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET touch ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "invalid touch profile".to_string())
            .and_then(set_touch_profile)
    } else if let Some(arg) = cmd.strip_prefix("SET touch.dt2w ") {
        match arg.trim() {
            "1" => set_dt2w(true),
            "0" => set_dt2w(false),
            _ => Err("invalid DT2W state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET display.expert.gamut ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad expert gamut".to_string())
            .and_then(set_expert_gamut)
    } else if let Some(rest) = cmd.strip_prefix("SET display.expert.channel ") {
        let mut parts = rest.split_whitespace();
        let channel = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let value = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(i32::MIN);
        set_expert_channel(channel, value)
    } else if cmd == "SET display.expert.reset" {
        reset_expert_display()
    } else if let Some(arg) = cmd.strip_prefix("SET perapp.enabled ") {
        match arg.trim() {
            "1" => set_per_app_enabled(true),
            "0" => set_per_app_enabled(false),
            _ => Err("invalid per-app state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET perapp.assign ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad per-app profile".to_string())
            .and_then(assign_last_app_profile)
    } else if let Some(rest) = cmd.strip_prefix("SET perapp.package ") {
        let mut parts = rest.split_whitespace();
        let profile = parts
            .next()
            .and_then(|value| value.parse::<i32>().ok())
            .unwrap_or(i32::MIN);
        let package = parts.next().unwrap_or("");

        if parts.next().is_some() {
            Err("too many per-app package arguments".into())
        } else {
            set_app_profile(package, profile)
        }
    } else if let Some(arg) = cmd.strip_prefix("SET display.color ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad display color".to_string())
            .and_then(set_display_color)
    } else if let Some(arg) = cmd.strip_prefix("SET display.temp ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad display temp".to_string())
            .and_then(set_display_temp)
    } else if let Some(arg) = cmd.strip_prefix("SET display.sunlight ") {
        match arg.trim() {
            "1" => set_sunlight(true),
            "0" => set_sunlight(false),
            _ => Err("invalid sunlight state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET display.silky ") {
        match arg.trim() {
            "1" => set_display_toggle(57, true, &DISPLAY_SILKY_STATE),
            "0" => set_display_toggle(57, false, &DISPLAY_SILKY_STATE),
            _ => Err("invalid silky state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET display.video ") {
        match arg.trim() {
            "1" => set_display_toggle(27, true, &DISPLAY_VIDEO_STATE),
            "0" => set_display_toggle(27, false, &DISPLAY_VIDEO_STATE),
            _ => Err("invalid video state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET display.dolby ") {
        match arg.trim() {
            "1" => set_display_toggle(44, true, &DISPLAY_DOLBY_STATE),
            "0" => set_display_toggle(44, false, &DISPLAY_DOLBY_STATE),
            _ => Err("invalid dolby state".into()),
        }
    } else if let Some(arg) = cmd.strip_prefix("SET perf ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad profile".to_string())
            .and_then(apply_performance_profile)
    } else if let Some(arg) = cmd.strip_prefix("SET cpu.manual ") {
        match arg.trim() {
            "1" => set_cpu_manual(true),
            "0" => set_cpu_manual(false),
            _ => Err("invalid CPU manual state".into()),
        }
    } else if let Some(rest) = cmd.strip_prefix("SET cpu.core ") {
        let mut parts = rest.split_whitespace();
        let cpu = parts
            .next()
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(usize::MAX);
        let online = parts.next().unwrap_or("");

        if parts.next().is_some() {
            Err("too many CPU core arguments".into())
        } else {
            match online {
                "1" => set_cpu_core(cpu, true),
                "0" => set_cpu_core(cpu, false),
                _ => Err("invalid CPU core state".into()),
            }
        }
    } else if let Some(rest) = cmd.strip_prefix("SET cpu.gov ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let governor = parts.next().unwrap_or("");
        set_cpu_governor(policy, governor)
    } else if let Some(rest) = cmd.strip_prefix("SET cpu.min_freq ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        set_cpu_cluster_min_freq(policy, mhz)
    } else if let Some(rest) = cmd.strip_prefix("SET cpu.max_freq ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        set_cpu_cluster_max_freq(policy, mhz)
    } else if let Some(rest) = cmd.strip_prefix("SET cpu.freq_range ") {
        let mut parts = rest.split_whitespace();
        let policy = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(-1);
        let min_mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        let max_mhz = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        set_cpu_cluster_freq_range(policy, min_mhz, max_mhz)
    } else if let Some(arg) = cmd.strip_prefix("SET cpu.freq_reset ") {
        let policy = arg.trim().parse::<i32>().unwrap_or(-1);
        reset_cpu_cluster_freq_range(policy)
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.gov ") {
        set_gpu_governor(arg.trim())
    } else if let Some(arg) = cmd.strip_prefix("SET io.scheduler ") {
        set_io_scheduler(arg.trim())
    } else if let Some(rest) = cmd.strip_prefix("SET display.res ") {
        let mut parts = rest.split_whitespace();
        let width = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        let height = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);
        let density = parts
            .next()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(0);

        apply_display_resolution(width, height, density, true)
    } else if let Some(arg) = cmd.strip_prefix("OPEN support ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad support link".to_string())
            .and_then(open_support_link)
    } else if let Some(arg) = cmd.strip_prefix("SET zram.size ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad zram size".to_string())
            .and_then(set_zram_size)
    } else if let Some(arg) = cmd.strip_prefix("SET zram.algorithm ") {
        set_zram_algorithm(arg.trim())
    } else if let Some(arg) = cmd.strip_prefix("SET zram.swappiness ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad swappiness".to_string())
            .and_then(set_zram_swappiness)
    } else if cmd == "ACTION zram.compact" {
        compact_zram()
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.min_freq ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad gpu min freq".to_string())
            .and_then(set_gpu_min_freq)
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.max_freq ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad gpu max freq".to_string())
            .and_then(set_gpu_max_freq)
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.governor ") {
        set_gpu_governor(arg.trim())
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.ged_boost ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad ged boost flag".to_string())
            .and_then(|v| set_gpu_ged_boost(v == 1))
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.power_policy ") {
        set_gpu_power_policy(arg.trim())
    } else if let Some(arg) = cmd.strip_prefix("SET gpu.uncap ") {
        arg.trim()
            .parse::<i32>()
            .map_err(|_| "bad uncap flag".to_string())
            .and_then(|v| set_gpu_uncap(v == 1))
    } else if cmd == "ACTION gpu.uncap_full_speed" {
        set_gpu_uncap(true)
    } else {
        return "ERR unknown command".into();
    };

    match result {
        Ok(()) => {
            record_successful_command(cmd);
            "OK applied".into()
        }
        Err(e) => format!("ERR {e}"),
    }
}

pub fn serve_client(mut stream: UnixStream) {
    let mut buf = [0u8; 4096];
    let Ok(n) = stream.read(&mut buf) else {
        return;
    };
    if n == 0 {
        return;
    }
    let req = String::from_utf8_lossy(&buf[..n]);
    let response = handle_command(&req);
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.write_all(b"\n");
    let _ = stream.flush();
}

#[cfg(test)]
mod tests {
    use super::{
        PersistedState, classify_touch_panel_version, cpu_frequency_drift_status,
        find_touch_thp_config_offset, gaming_dynamic_target_opp, mi_thermal_cpu_limit_request,
        migrate_legacy_gpu_profile_cpu_state, mtk_powerhal_cpu_range_request,
        parse_cpu_frequency_table, parse_cpu_time_in_state, parse_ged_current_frequency_mhz,
        profile_uses_ged_boost, scaled_display_density, validate_cpu_frequency_range_against,
    };

    fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
        bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    }

    #[test]
    fn parses_cpu_frequency_table_as_sorted_unique_mhz_opps() {
        assert_eq!(
            parse_cpu_frequency_table("2100000 2000000 1000000 2000000 bad 3250500"),
            vec![1000, 2000, 2100]
        );
    }

    #[test]
    fn parses_only_the_frequency_column_from_time_in_state() {
        assert_eq!(
            parse_cpu_time_in_state("2100000 298\n2000000 15718\n2100000 12\ninvalid\n"),
            vec![2000, 2100]
        );
    }

    #[test]
    fn accepts_only_ordered_frequencies_exposed_by_the_policy() {
        let available = [300, 400, 500, 600, 2100];
        assert!(validate_cpu_frequency_range_against(0, 400, 2100, &available).is_ok());
        assert!(validate_cpu_frequency_range_against(0, 400, 400, &available).is_ok());
        assert!(validate_cpu_frequency_range_against(0, 350, 2100, &available).is_err());
        assert!(validate_cpu_frequency_range_against(0, 2100, 400, &available).is_err());
    }

    #[test]
    fn formats_rodin_vendor_cpu_frequency_requests_per_policy() {
        assert_eq!(mi_thermal_cpu_limit_request(0, 2100), "cpu0 2100000");
        assert_eq!(mi_thermal_cpu_limit_request(4, 3000), "cpu4 3000000");
        assert_eq!(mi_thermal_cpu_limit_request(7, 3250), "cpu7 3250000");
        assert_eq!(
            mtk_powerhal_cpu_range_request(4, 400, 3000),
            "4 400000 3000000"
        );
    }

    #[test]
    fn distinguishes_saved_targets_from_live_frequency_drift() {
        assert_eq!(cpu_frequency_drift_status(-1, -1, 300, 2100), -1);
        assert_eq!(cpu_frequency_drift_status(1200, 1800, 1200, 1800), 0);
        assert_eq!(cpu_frequency_drift_status(1800, 1800, 1200, 1800), 1);
    }

    #[test]
    fn finds_rodin_thp_timing_block_without_a_fixed_address() {
        let mut bytes = vec![0u8; 0x80];
        let offset = 0x10;
        put_u16(&mut bytes, offset, 135);
        put_u16(&mut bytes, offset + 0x04, 135);
        put_u16(&mut bytes, offset + 0x18, 240);
        put_u16(&mut bytes, offset + 0x1c, 240);
        put_u16(&mut bytes, offset + 0x24, 240);
        put_u16(&mut bytes, offset + 0x28, 650);

        assert_eq!(find_touch_thp_config_offset(&bytes), Some(offset));
    }

    #[test]
    fn detects_both_rodin_touch_panel_families() {
        assert_eq!(classify_touch_panel_version("driver version: gt9916"), 1);
        assert_eq!(classify_touch_panel_version("Goodix GDIX algorithm"), 1);
        assert_eq!(classify_touch_panel_version("FocalTech FT3683G"), 2);
        assert_eq!(classify_touch_panel_version("unknown panel"), 0);
    }

    #[test]
    fn scales_resolution_density_from_the_rom_native_baseline() {
        assert_eq!(scaled_display_density(520, 1220), 520);
        assert_eq!(scaled_display_density(520, 1080), 460);
        assert_eq!(scaled_display_density(520, 720), 307);
        assert_eq!(scaled_display_density(520, 1440), 614);
        assert_eq!(scaled_display_density(440, 1080), 390);
    }

    #[test]
    fn parses_rodin_ged_current_opp() {
        assert_eq!(parse_ged_current_frequency_mhz("40 260000\n"), Some(260));
        assert_eq!(parse_ged_current_frequency_mhz("0 1300000\n"), Some(1300));
    }

    #[test]
    fn accepts_single_value_frequency_units() {
        assert_eq!(parse_ged_current_frequency_mhz("260000000"), Some(260));
        assert_eq!(parse_ged_current_frequency_mhz("26"), Some(26));
        assert_eq!(parse_ged_current_frequency_mhz("unavailable"), None);
    }

    #[test]
    fn gaming_dynamic_policy_uses_the_full_opp_table() {
        assert_eq!(gaming_dynamic_target_opp(100, 40, 40), 0);
        assert_eq!(gaming_dynamic_target_opp(75, 30, 40), 22);
        assert_eq!(gaming_dynamic_target_opp(60, 30, 40), 26);
        assert_eq!(gaming_dynamic_target_opp(0, 0, 40), 40);
    }

    #[test]
    fn ged_boost_is_owned_only_by_gaming_and_beast() {
        assert!(!profile_uses_ged_boost(0));
        assert!(profile_uses_ged_boost(1));
        assert!(!profile_uses_ged_boost(2));
        assert!(profile_uses_ged_boost(3));
    }

    #[test]
    fn migrates_only_the_cpu_signature_written_by_legacy_gpu_profiles() {
        let mut legacy = PersistedState {
            perf: 3,
            gpu_profile_cpu_isolated: 0,
            cpu0: "performance".into(),
            cpu4: "performance".into(),
            cpu7: "performance".into(),
            cpu_min_freq0: 2100,
            cpu_max_freq0: 2100,
            cpu_min_freq4: 3000,
            cpu_max_freq4: 3000,
            cpu_min_freq7: 3250,
            cpu_max_freq7: 3250,
            ..PersistedState::default()
        };

        assert!(migrate_legacy_gpu_profile_cpu_state(&mut legacy));
        assert_eq!(legacy.gpu_profile_cpu_isolated, 1);
        assert!(legacy.cpu0.is_empty());
        assert_eq!(legacy.cpu_min_freq0, -1);
        assert_eq!(legacy.cpu_max_freq7, -1);

        let mut custom = PersistedState {
            perf: 3,
            gpu_profile_cpu_isolated: 0,
            cpu0: "schedutil".into(),
            cpu4: "schedutil".into(),
            cpu7: "schedutil".into(),
            cpu_min_freq0: 600,
            cpu_max_freq0: 1800,
            cpu_min_freq4: 800,
            cpu_max_freq4: 2200,
            cpu_min_freq7: 1200,
            cpu_max_freq7: 2800,
            ..PersistedState::default()
        };

        assert!(!migrate_legacy_gpu_profile_cpu_state(&mut custom));
        assert_eq!(custom.gpu_profile_cpu_isolated, 1);
        assert_eq!(custom.cpu0, "schedutil");
        assert_eq!(custom.cpu_min_freq0, 600);
        assert_eq!(custom.cpu_max_freq7, 2800);
    }
}
