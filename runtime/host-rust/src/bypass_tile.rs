//! Tile presentation must not turn a saved request into evidence of direct power.
pub fn direct_power_confirmed(phase: i32, active: i32, online: i32, current: i64) -> bool {
    phase == 4 && active == 1 && online == 1 && (-100_000..=100_000).contains(&current)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_measured_active_power_is_confirmed() {
        for current in [-100_000, 0, 100_000] {
            assert!(direct_power_confirmed(4, 1, 1, current));
        }
        for phase in [0, 1, 2, 3, 5, 6, 7, -1] {
            assert!(!direct_power_confirmed(phase, 1, 1, 0));
        }
        for current in [-100_001, 100_001, i64::MIN] {
            assert!(!direct_power_confirmed(4, 1, 1, current));
        }
        assert!(!direct_power_confirmed(4, 0, 1, 0));
        assert!(!direct_power_confirmed(4, 1, 0, 0));
        assert!(!direct_power_confirmed(4, 1, -1, 0));
    }
}
