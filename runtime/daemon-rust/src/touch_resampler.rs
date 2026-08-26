use std::sync::Once;
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::time::Duration;

static TARGET_HZ: AtomicI32 = AtomicI32::new(0);
static READY_HZ: AtomicI32 = AtomicI32::new(0);
static LAST_ERROR: AtomicI32 = AtomicI32::new(0);
static MEASURED_HZ_X10: AtomicI32 = AtomicI32::new(0);
static SOURCE_MEASURED_HZ_X10: AtomicI32 = AtomicI32::new(0);
static MEASUREMENT_ACTIVE: AtomicI32 = AtomicI32::new(0);
static ATTACHMENT_PATH: AtomicI32 = AtomicI32::new(0);
static PHYSICAL_FRAMES: AtomicU64 = AtomicU64::new(0);
static INJECTED_FRAMES: AtomicU64 = AtomicU64::new(0);
static START: Once = Once::new();

pub fn start_background() {
    START.call_once(|| {
        std::thread::spawn(worker);
    });
}

pub fn set_target_hz(target: i32) -> Result<(), String> {
    if target != 0 && target != 1000 {
        return Err(format!("unsupported Rodin resampling target {target}"));
    }

    TARGET_HZ.store(target, Ordering::Release);
    if target == 0 {
        for _ in 0..50 {
            if READY_HZ.load(Ordering::Acquire) == 0 {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        return Ok(());
    }

    for _ in 0..200 {
        if READY_HZ.load(Ordering::Acquire) == target {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(5));
    }

    Err(format!(
        "Rodin touch resampler did not attach (code {})",
        LAST_ERROR.load(Ordering::Acquire)
    ))
}

pub fn ready_hz() -> i32 {
    READY_HZ.load(Ordering::Acquire)
}

pub fn measured_hz_x10() -> i32 {
    MEASURED_HZ_X10.load(Ordering::Acquire)
}

pub fn source_measured_hz_x10() -> i32 {
    SOURCE_MEASURED_HZ_X10.load(Ordering::Acquire)
}

pub fn measurement_active() -> i32 {
    MEASUREMENT_ACTIVE.load(Ordering::Acquire)
}

pub fn attachment_path() -> i32 {
    ATTACHMENT_PATH.load(Ordering::Acquire)
}

pub fn last_error() -> i32 {
    LAST_ERROR.load(Ordering::Acquire)
}

pub fn physical_frames() -> u64 {
    PHYSICAL_FRAMES.load(Ordering::Acquire)
}

pub fn injected_frames() -> u64 {
    INJECTED_FRAMES.load(Ordering::Acquire)
}

fn worker() {
    loop {
        let target = TARGET_HZ.load(Ordering::Acquire);
        if target == 0 {
            READY_HZ.store(0, Ordering::Release);
            ATTACHMENT_PATH.store(0, Ordering::Release);
            std::thread::sleep(Duration::from_millis(25));
            continue;
        }

        #[cfg(target_os = "android")]
        let result = android::run(target);
        #[cfg(not(target_os = "android"))]
        let result: Result<(), i32> = Err(-100);

        READY_HZ.store(0, Ordering::Release);
        if let Err(code) = result {
            LAST_ERROR.store(code, Ordering::Release);
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[cfg(target_os = "android")]
mod android {
    use super::{
        ATTACHMENT_PATH, INJECTED_FRAMES, LAST_ERROR, PHYSICAL_FRAMES, READY_HZ, TARGET_HZ,
    };
    use std::fs::{self, File, OpenOptions};
    use std::io::{Read, Write};
    use std::mem::size_of;
    use std::os::fd::{AsRawFd, FromRawFd, RawFd};
    use std::os::raw::{c_int, c_long};
    use std::os::unix::fs::OpenOptionsExt;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::Ordering;

    const O_NONBLOCK: i32 = 0x800;
    const O_CLOEXEC: i32 = 0x80000;
    const CLOCK_MONOTONIC: i32 = 1;
    const TIMER_ABSTIME: i32 = 1;
    const PRIO_PROCESS: i32 = 0;
    const SYS_PIDFD_OPEN: c_long = 434;
    const SYS_PIDFD_GETFD: c_long = 438;
    const EVIOCSCLOCKID: c_long = 0x4004_45a0;

    const EV_SYN: u16 = 0;
    const EV_ABS: u16 = 3;
    const SYN_REPORT: u16 = 0;
    const ABS_MT_SLOT: u16 = 0x2f;
    const ABS_MT_TOUCH_MAJOR: u16 = 0x30;
    const ABS_MT_WIDTH_MAJOR: u16 = 0x32;
    const ABS_MT_WIDTH_MINOR: u16 = 0x33;
    const ABS_MT_POSITION_X: u16 = 0x35;
    const ABS_MT_POSITION_Y: u16 = 0x36;
    const ABS_MT_TRACKING_ID: u16 = 0x39;

    #[repr(C)]
    #[derive(Clone, Copy, Default)]
    struct TimeVal {
        sec: i64,
        usec: i64,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Default)]
    struct InputEvent {
        time: TimeVal,
        event_type: u16,
        code: u16,
        value: i32,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Default)]
    struct TimeSpec {
        sec: i64,
        nsec: i64,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Default)]
    struct InputAbsInfo {
        value: i32,
        minimum: i32,
        maximum: i32,
        fuzz: i32,
        flat: i32,
        resolution: i32,
    }

    #[derive(Clone, Copy)]
    struct SlotState {
        active: bool,
        tracking_id: i32,
        x: i32,
        y: i32,
        previous_x: i32,
        previous_y: i32,
        marker_value: i32,
        point_time_ns: i64,
        previous_time_ns: i64,
    }

    impl Default for SlotState {
        fn default() -> Self {
            Self {
                active: false,
                tracking_id: -1,
                x: 0,
                y: 0,
                previous_x: 0,
                previous_y: 0,
                marker_value: 0,
                point_time_ns: 0,
                previous_time_ns: 0,
            }
        }
    }

    unsafe extern "C" {
        fn syscall(number: c_long, ...) -> c_long;
        fn clock_gettime(clock_id: c_int, time: *mut TimeSpec) -> c_int;
        fn clock_nanosleep(
            clock_id: c_int,
            flags: c_int,
            request: *const TimeSpec,
            remain: *mut TimeSpec,
        ) -> c_int;
        fn ioctl(fd: c_int, request: c_long, ...) -> c_int;
        fn setpriority(which: c_int, who: u32, priority: c_int) -> c_int;
    }

    fn monotonic_ns() -> i64 {
        let mut now = TimeSpec::default();
        unsafe {
            clock_gettime(CLOCK_MONOTONIC, &mut now);
        }
        now.sec.saturating_mul(1_000_000_000) + now.nsec
    }

    fn use_monotonic_event_clock(fd: RawFd) {
        let clock_id = CLOCK_MONOTONIC;
        unsafe {
            ioctl(fd, EVIOCSCLOCKID, &clock_id);
        }
    }

    fn sleep_until_ns(deadline: i64) {
        let request = TimeSpec {
            sec: deadline / 1_000_000_000,
            nsec: deadline % 1_000_000_000,
        };
        unsafe {
            clock_nanosleep(
                CLOCK_MONOTONIC,
                TIMER_ABSTIME,
                &request,
                std::ptr::null_mut(),
            );
        }
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
            let name = cmdline.split(|byte| *byte == 0).next().unwrap_or_default();
            if name == b"vendor.xiaomi.hw.touchfeature-service"
                || name.ends_with(b"/vendor.xiaomi.hw.touchfeature-service")
            {
                return Some(pid);
            }
        }
        None
    }

    unsafe fn libc_close(fd: RawFd) {
        unsafe extern "C" {
            fn close(fd: c_int) -> c_int;
        }
        unsafe {
            close(fd);
        }
    }

    fn ev_iocgabs(code: u16) -> c_long {
        // _IOR('E', 0x40 + code, struct input_absinfo)
        (0x8000_0000u32
            | ((size_of::<InputAbsInfo>() as u32) << 16)
            | (0x45u32 << 8)
            | (0x40u32 + code as u32)) as c_long
    }

    fn has_axis(fd: RawFd, code: u16) -> bool {
        let mut info = InputAbsInfo::default();
        unsafe { ioctl(fd, ev_iocgabs(code), &mut info) == 0 && info.maximum > info.minimum }
    }

    fn is_multitouch_device(fd: RawFd) -> bool {
        has_axis(fd, ABS_MT_POSITION_X)
            && has_axis(fd, ABS_MT_POSITION_Y)
            && marker_axis(fd).is_some()
    }

    fn marker_axis(fd: RawFd) -> Option<u16> {
        [ABS_MT_WIDTH_MINOR, ABS_MT_WIDTH_MAJOR, ABS_MT_TOUCH_MAJOR]
            .into_iter()
            .find(|code| has_axis(fd, *code))
    }

    fn service_output_handle(pid: u32) -> Result<(File, PathBuf), i32> {
        let entries = fs::read_dir(format!("/proc/{pid}/fd")).map_err(|_| -1)?;
        let mut candidates = Vec::new();
        for entry in entries.flatten() {
            let Ok(fd_number) = entry.file_name().to_string_lossy().parse::<i32>() else {
                continue;
            };
            let Ok(path) = fs::read_link(entry.path()) else {
                continue;
            };
            if path.to_string_lossy().starts_with("/dev/input/event") {
                candidates.push((fd_number, path));
            }
        }
        candidates.sort_by(|left, right| left.1.cmp(&right.1));

        let pidfd = unsafe { syscall(SYS_PIDFD_OPEN, pid as c_int, 0 as c_int) } as i32;
        if pidfd < 0 {
            return Err(-3);
        }

        for (target_fd, path) in candidates {
            let duplicate =
                unsafe { syscall(SYS_PIDFD_GETFD, pidfd, target_fd, 0 as c_int) } as i32;
            if duplicate < 0 {
                continue;
            }
            let file = unsafe { File::from_raw_fd(duplicate) };
            if is_multitouch_device(file.as_raw_fd()) {
                unsafe {
                    libc_close(pidfd);
                }
                return Ok((file, path));
            }
        }

        unsafe {
            libc_close(pidfd);
        }
        Err(-4)
    }

    fn direct_output_handle() -> Result<(File, PathBuf), i32> {
        let mut paths = fs::read_dir("/dev/input")
            .map_err(|_| -10)?
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with("event"))
            })
            .collect::<Vec<_>>();
        paths.sort();

        for path in paths {
            let Ok(file) = OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(O_NONBLOCK | O_CLOEXEC)
                .open(&path)
            else {
                continue;
            };
            if is_multitouch_device(file.as_raw_fd()) {
                return Ok((file, path));
            }
        }
        Err(-11)
    }

    fn output_handle() -> Result<(File, PathBuf, i32, Option<u32>), i32> {
        // AOSP policy deliberately does not grant CAP_SYS_PTRACE to the
        // daemon: Android's platform neverallows reserve that capability for
        // a fixed set of core diagnostics. ROM-native deployments therefore
        // use TouchFeature for native calibration and open the panel event
        // directly under the daemon's dedicated input permission. Root-module
        // deployments may first duplicate the vendor service handle and retain
        // the direct path as their fallback.
        if std::env::var("RODIN_DIRECT_INPUT_ONLY").as_deref() != Ok("1") {
            if let Some(pid) = touch_service_pid()
                && let Ok((file, path)) = service_output_handle(pid)
            {
                return Ok((file, path, 1, Some(pid)));
            }
        }

        direct_output_handle().map(|(file, path)| (file, path, 2, None))
    }

    fn axis_range(fd: RawFd, code: u16) -> (i32, i32) {
        let mut info = InputAbsInfo::default();
        let result = unsafe { ioctl(fd, ev_iocgabs(code), &mut info) };
        if result == 0 && info.maximum > info.minimum {
            (info.minimum, info.maximum)
        } else if code == ABS_MT_POSITION_X {
            (0, 121_999)
        } else {
            (0, 271_199)
        }
    }

    fn frame_is_injected(events: &[InputEvent], marker_code: u16) -> bool {
        // Rodin-generated frames finish with a temporary width change followed
        // by its original value. Both values occur before SYN_REPORT, so
        // Android only observes the restored valid pointer state. The pair
        // survives kernel event coalescing and lets us ignore our own output.
        let mut payload = events
            .iter()
            .rev()
            .skip_while(|event| event.event_type == EV_SYN && event.code == SYN_REPORT);
        let Some(last) = payload.next() else {
            return false;
        };
        let Some(previous) = payload.next() else {
            return false;
        };
        last.event_type == EV_ABS
            && last.code == marker_code
            && previous.event_type == EV_ABS
            && previous.code == marker_code
            && last.value != previous.value
    }

    fn events_as_bytes(events: &[InputEvent]) -> &[u8] {
        unsafe {
            std::slice::from_raw_parts(events.as_ptr().cast::<u8>(), std::mem::size_of_val(events))
        }
    }

    fn emit_interpolated(
        output: &mut File,
        slots: &[SlotState; 10],
        now_ns: i64,
        x_range: (i32, i32),
        y_range: (i32, i32),
        marker_code: u16,
        marker_range: (i32, i32),
    ) -> bool {
        let Some(first_active_slot) = slots.iter().position(|slot| slot.active) else {
            return false;
        };
        let mut events = Vec::with_capacity(40);
        let mut push = |event_type, code, value| {
            events.push(InputEvent {
                event_type,
                code,
                value,
                ..InputEvent::default()
            });
        };
        let mut changed = false;
        let mut final_slot = first_active_slot;
        for (slot, state) in slots.iter().enumerate() {
            if !state.active {
                continue;
            }
            let mut x = state.x;
            let mut y = state.y;
            let source_delta = state.point_time_ns - state.previous_time_ns;
            let mut future_delta = now_ns - state.point_time_ns;
            if source_delta > 0 && source_delta < 50_000_000 && future_delta > 0 {
                future_delta = future_delta.min(source_delta);
                x = x.saturating_add(
                    ((state.x - state.previous_x) as i64 * future_delta / source_delta) as i32,
                );
                y = y.saturating_add(
                    ((state.y - state.previous_y) as i64 * future_delta / source_delta) as i32,
                );
            }
            x = x.clamp(x_range.0, x_range.1);
            y = y.clamp(y_range.0, y_range.1);
            changed |= x != state.x || y != state.y;
            push(EV_ABS, ABS_MT_SLOT, slot as i32);
            push(EV_ABS, ABS_MT_POSITION_X, x);
            push(EV_ABS, ABS_MT_POSITION_Y, y);
            final_slot = slot;
        }
        push(EV_ABS, ABS_MT_SLOT, final_slot as i32);
        let original_marker = slots[final_slot]
            .marker_value
            .clamp(marker_range.0, marker_range.1);
        let temporary_marker = if original_marker < marker_range.1 {
            original_marker + 1
        } else {
            original_marker - 1
        };
        push(EV_ABS, marker_code, temporary_marker);
        push(EV_ABS, marker_code, original_marker);
        push(EV_SYN, SYN_REPORT, 0);

        changed && output.write_all(events_as_bytes(&events)).is_ok()
    }

    fn parse_events(bytes: &[u8]) -> impl Iterator<Item = InputEvent> + '_ {
        bytes
            .chunks_exact(size_of::<InputEvent>())
            .map(|chunk| unsafe { std::ptr::read_unaligned(chunk.as_ptr().cast::<InputEvent>()) })
    }

    pub(super) fn run(initial_target: i32) -> Result<(), i32> {
        let (mut output, path, attachment_path, service_pid) = output_handle()?;
        let mut input = OpenOptions::new()
            .read(true)
            .custom_flags(O_NONBLOCK | O_CLOEXEC)
            .open(&path)
            .map_err(|_| -6)?;
        use_monotonic_event_clock(input.as_raw_fd());
        let x_range = axis_range(input.as_raw_fd(), ABS_MT_POSITION_X);
        let y_range = axis_range(input.as_raw_fd(), ABS_MT_POSITION_Y);
        let marker_code = marker_axis(input.as_raw_fd()).ok_or(-13)?;
        let marker_range = axis_range(input.as_raw_fd(), marker_code);
        unsafe {
            setpriority(PRIO_PROCESS, 0, -10);
        }

        let mut slots = [SlotState::default(); 10];
        let mut frame = Vec::with_capacity(128);
        let mut current_slot = 0usize;
        let mut session = false;
        let mut session_start = 0i64;
        let mut ideal_count = 0u64;
        let mut actual_count = 0u64;
        let mut next_tick = 0i64;
        let mut last_source_frame = 0i64;
        let mut service_check = monotonic_ns() + 500_000_000;
        let mut read_buffer = [0u8; size_of::<InputEvent>() * 64];

        LAST_ERROR.store(0, Ordering::Release);
        ATTACHMENT_PATH.store(attachment_path, Ordering::Release);
        READY_HZ.store(initial_target, Ordering::Release);

        loop {
            let target = TARGET_HZ.load(Ordering::Acquire);
            if target == 0 || target != initial_target {
                return Ok(());
            }

            loop {
                let bytes = match input.read(&mut read_buffer) {
                    Ok(0) => return Err(-7),
                    Ok(bytes) => bytes,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => break,
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => return Err(-8),
                };

                for event in parse_events(&read_buffer[..bytes]) {
                    frame.push(event);
                    if event.event_type != EV_SYN || event.code != SYN_REPORT {
                        continue;
                    }

                    if !frame_is_injected(&frame, marker_code) {
                        let frame_ns = monotonic_ns();
                        last_source_frame = frame_ns;
                        let was_active = slots.iter().any(|slot| slot.active);
                        let mut parsed_slot = current_slot;
                        let mut position_changed = [false; 10];
                        for item in &frame {
                            if item.event_type != EV_ABS {
                                continue;
                            }
                            match item.code {
                                ABS_MT_SLOT if (0..10).contains(&item.value) => {
                                    parsed_slot = item.value as usize;
                                }
                                ABS_MT_TRACKING_ID => {
                                    slots[parsed_slot].tracking_id = item.value;
                                    slots[parsed_slot].active = item.value >= 0;
                                }
                                ABS_MT_POSITION_X if slots[parsed_slot].x != item.value => {
                                    slots[parsed_slot].previous_x = slots[parsed_slot].x;
                                    slots[parsed_slot].x = item.value;
                                    position_changed[parsed_slot] = true;
                                }
                                ABS_MT_POSITION_Y if slots[parsed_slot].y != item.value => {
                                    slots[parsed_slot].previous_y = slots[parsed_slot].y;
                                    slots[parsed_slot].y = item.value;
                                    position_changed[parsed_slot] = true;
                                }
                                code if code == marker_code => {
                                    slots[parsed_slot].marker_value = item.value;
                                }
                                _ => {}
                            }
                        }
                        current_slot = parsed_slot;
                        for slot in 0..10 {
                            if position_changed[slot] {
                                slots[slot].previous_time_ns = slots[slot].point_time_ns;
                                slots[slot].point_time_ns = frame_ns;
                            }
                        }
                        let active = slots.iter().any(|slot| slot.active);
                        if active && (!was_active || !session) {
                            session = true;
                            session_start = frame_ns;
                            actual_count = 1;
                            ideal_count = 2;
                            next_tick = session_start
                                + ((ideal_count - 1) * 1_000_000_000u64 / target as u64) as i64;
                        } else if active && session {
                            actual_count += 1;
                        } else if !active {
                            session = false;
                        }
                        if active {
                            PHYSICAL_FRAMES.fetch_add(1, Ordering::AcqRel);
                        }
                    }
                    frame.clear();
                }
            }

            let now = monotonic_ns();
            // A screen-off transition or interrupted gesture can omit the
            // final tracking-id release. Never keep synthesizing from stale
            // coordinates after the physical panel has stopped reporting.
            if session && now.saturating_sub(last_source_frame) > 40_000_000 {
                session = false;
            }
            while session && now >= next_tick {
                if actual_count < ideal_count
                    && emit_interpolated(
                        &mut output,
                        &slots,
                        next_tick,
                        x_range,
                        y_range,
                        marker_code,
                        marker_range,
                    )
                {
                    actual_count += 1;
                    INJECTED_FRAMES.fetch_add(1, Ordering::AcqRel);
                }
                ideal_count += 1;
                next_tick =
                    session_start + ((ideal_count - 1) * 1_000_000_000u64 / target as u64) as i64;
            }

            if now >= service_check {
                if let Some(pid) = service_pid
                    && touch_service_pid() != Some(pid)
                {
                    return Err(-9);
                }
                if !Path::new(&path).exists() {
                    return Err(-12);
                }
                service_check = now + 500_000_000;
            }

            // Poll closely only while a finger is active so source frames and
            // 1 ms deadlines are not lost to scheduler wake latency. Idle mode
            // remains inexpensive and the stale-session cutoff guarantees an
            // interrupted gesture cannot leave this fast path running.
            let wake = if session {
                next_tick.min(now + 250_000)
            } else {
                now + 2_000_000
            };
            sleep_until_ns(wake);
        }
    }
}
