//! Threshold policy is independent of UI lifetime and measured activity.
//! `true` requests charge pause; it never means hardware is verified active.
pub fn valid_threshold(value: i32) -> bool {
    matches!(value, 0 | 20 | 40 | 80 | 90)
}

pub fn phase(
    enabled: bool,
    threshold: i32,
    capacity: Option<i32>,
    online: i32,
    requested: i32,
    verified: i32,
    current_ua: Option<i64>,
    error: bool,
) -> i32 {
    if !enabled {
        return 0;
    }
    if error {
        return 5;
    }
    if online == 0 {
        return 2;
    }
    if requested == 0 && threshold > 0 && capacity.is_some_and(|value| value < threshold) {
        return 1;
    }
    if requested != 1 {
        return 5;
    }
    if online != 1 {
        return 3;
    }
    if let Some(current) = current_ua {
        // Rodin's battery CURRENT_NOW convention: negative charges the cell.
        if current < -100_000 {
            return 7;
        }
        if current > 100_000 {
            return 6;
        }
        if verified == 1 {
            return 4;
        }
    }
    3
}

pub fn target(
    enabled: bool,
    threshold: i32,
    capacity: Option<i32>,
    held: bool,
) -> Result<bool, String> {
    if !valid_threshold(threshold) {
        return Err("invalid bypass threshold".into());
    }
    if !enabled {
        return Ok(false);
    }
    if threshold == 0 {
        return Ok(true);
    }
    let capacity = capacity
        .filter(|value| (0..=100).contains(value))
        .ok_or_else(|| "battery level unavailable for bypass threshold".to_string())?;
    // A two-point release band prevents repeated charging transitions at a
    // rounded SOC boundary. Crossing the selected level activates immediately.
    Ok(if held {
        capacity > threshold - 2
    } else {
        capacity >= threshold
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_threshold_charges_below_and_pauses_at_the_selected_level() {
        for threshold in [20, 40, 80, 90] {
            assert_eq!(
                target(true, threshold, Some(threshold - 1), false),
                Ok(false)
            );
            assert_eq!(target(true, threshold, Some(threshold), false), Ok(true));
            assert_eq!(target(true, threshold, Some(threshold - 1), true), Ok(true));
            assert_eq!(
                target(true, threshold, Some(threshold - 2), true),
                Ok(false)
            );
        }
    }

    #[test]
    fn immediate_and_disabled_modes_do_not_require_a_fuel_gauge() {
        assert_eq!(target(true, 0, None, false), Ok(true));
        assert_eq!(target(false, 80, None, true), Ok(false));
    }

    #[test]
    fn unknown_or_invalid_capacity_is_not_guessed() {
        for capacity in [None, Some(-1), Some(101)] {
            assert!(target(true, 40, capacity, false).is_err());
        }
        assert!(target(true, 50, Some(60), false).is_err());
    }

    #[test]
    fn activity_is_measured_not_inferred_from_the_saved_toggle() {
        assert_eq!(phase(true, 80, Some(60), 1, 0, 0, Some(-900000), false), 1);
        assert_eq!(phase(true, 20, Some(60), 1, 1, 0, Some(0), false), 3);
        assert_eq!(phase(true, 20, Some(60), 1, 1, 1, Some(0), false), 4);
        assert_eq!(phase(true, 20, Some(60), 1, 1, 1, Some(-900000), false), 7);
        assert_eq!(phase(true, 20, Some(60), 1, 1, 0, Some(900000), false), 6);
        assert_eq!(phase(true, 20, Some(60), 0, 1, 0, None, false), 2);
        assert_eq!(phase(true, 20, Some(60), 1, 0, 0, Some(0), true), 5);
    }
}
