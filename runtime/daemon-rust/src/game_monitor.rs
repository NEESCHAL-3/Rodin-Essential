use super::run_process_with_timeout;
use serde_json::json;
use std::{fs, time::Duration};

fn surface(args: &[&str]) -> Option<String> {
    let output =
        run_process_with_timeout("/system/bin/dumpsys", args, Duration::from_millis(650)).ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

fn layer<'a>(list: &'a str, package: &str) -> Option<&'a str> {
    let belongs = |line: &str| {
        line.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '.'))
            .any(|s| s == package)
    };
    let candidates: Vec<_> = list
        .lines()
        .filter(|s| {
            belongs(s)
                && !s.contains("ActivityRecord")
                && !s.contains("InputSink")
                && !s.contains("leash")
        })
        .collect();
    for rank in 0..4 {
        let mut matching = candidates.iter().copied().filter(|s| {
            if s.contains("Background for") {
                return false;
            }
            let priority = if s.contains("SurfaceView") && s.contains("BLAST") {
                0
            } else if s.contains("SurfaceView") {
                1
            } else if s.starts_with("VRI-") || s.contains("BLAST") {
                2
            } else {
                3
            };
            priority == rank
        });
        if let Some(first) = matching.next() {
            return matching.next().is_none().then_some(first);
        }
    }
    None
}

pub(super) fn sample(package: &str) -> String {
    if package.is_empty()
        || package.len() > 255
        || !package
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._".contains(&b))
    {
        return "ERR invalid package".into();
    }
    let times = surface(&["SurfaceFlinger", "--list"])
        .and_then(|s| surface(&["SurfaceFlinger", "--latency", layer(&s, package)?]))
        .map(|s| {
            s.lines()
                .skip(1)
                .filter_map(|row| row.split_whitespace().nth(1)?.parse::<i64>().ok())
                .filter(|&t| t > 0 && t != i64::MAX)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let cpu = fs::read_to_string("/proc/stat").ok().and_then(|s| {
        let ticks: Vec<u64> = s
            .lines()
            .next()?
            .strip_prefix("cpu ")?
            .split_whitespace()
            .take(8)
            .map(str::parse)
            .collect::<Result<_, _>>()
            .ok()?;
        (ticks.len() == 8).then(|| [ticks.iter().sum::<u64>(), ticks[3] + ticks[4]])
    });
    let gpu = fs::read_to_string("/sys/kernel/ged/hal/gpu_utilization")
        .ok()
        .and_then(|s| s.split_whitespace().next()?.parse::<u32>().ok())
        .filter(|v| *v <= 100);
    format!("OK {}", json!({"present":times,"cpu":cpu,"gpu":gpu}))
}

#[cfg(test)]
mod tests {
    use super::layer;
    #[test]
    fn rejects_ambiguous_layers_and_package_prefixes() {
        let list = "SurfaceView[com.game.beta/Main]#1\nSurfaceView[com.game/Main]#2";
        assert_eq!(
            layer("abc com.game/Main#2\nVRI-com.game/Main#3", "com.game"),
            Some("VRI-com.game/Main#3")
        );
        assert_eq!(
            layer(list, "com.game"),
            Some("SurfaceView[com.game/Main]#2")
        );
        assert_eq!(
            layer(
                &format!("{list}\nSurfaceView[com.game/Video]#4"),
                "com.game"
            ),
            None
        );
    }
}
