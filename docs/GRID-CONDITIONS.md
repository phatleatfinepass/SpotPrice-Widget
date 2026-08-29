# Grid Conditions signal

Grid Conditions deliberately presents two related but different views of Finland's electricity system:

- **Grid emissions** is the latest measured Fingrid value in gCO₂/kWh. It is the primary, live metric.
- **Renewable outlook** is a keyless Energy-Charts forecast. It is the supporting timeline and never extrapolates the current emissions reading into the future.

## Renewable normalization

The provider's raw 0/1/2 signal is not used as the displayed color. The app derives its own conservative signal from Energy-Charts `renewable_share_of_load`:

1. Average each point over the next four contiguous 15-minute slots (60 minutes).
2. Compare that smoothed value with the P33/P67 band for the same Finland calendar month and Helsinki local hour.
3. Compare it again with the remaining forecast window using empirical percentile rank.
4. Show green only when the value is at or above its historical P67 **and** at or above the window's 75th percentile.
5. Show red only when the value is at or below its historical P33 **and** at or below the window's 25th percentile.
6. Keep a colored run only when it lasts at least one hour. Use 65%/35% exit thresholds to reduce edge flicker.
7. Leave the track neutral when its interquartile range is below 3 percentage points, the cadence is unsupported, the data is substituted/stale, or confidence is otherwise insufficient.

An explicit Energy-Charts grid-congestion signal (`-1`) remains an immediate red warning.

## Historical baseline

The embedded matrix uses the three latest complete years available during the 2026 calibration: **2023–2025**. Quarter-hour records are first normalized to hourly means so newer years do not receive four times the statistical weight of hourly history. The 288 cells cover all 12 calendar months × 24 Helsinki local hours.

If a cell is unavailable, classification falls back to its calendar month, then its meteorological season. The embedded baseline should be rebuilt once per year from completed years only.

Source field: Energy-Charts `renewable_share_of_load`. Original Finland electricity data is attributed by Energy-Charts to ENTSO-E.

## Visual semantics

- Green filled run + `leaf.fill`: a strong, sustained cleaner opportunity.
- Red filled run + `carbon.dioxide.cloud.fill`: a strong, sustained less-clean period.
- Empty neutral track: no strong signal; it does **not** mean “average all day.”

Small shows the next 12 hours. Medium shows the next 24 hours. Both begin at the current forecast slot and use a `Now` axis label without a separate marker.
