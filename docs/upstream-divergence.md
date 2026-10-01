# Temperature changes relative to upstream

What SmartFan changes in upstream ThermalForge's temperature code, and how to
re-apply it after merging an upstream release. Scope: the 0.2.3.16 sensor
fixes, plus the deliberate behaviour divergences listed at the end. The product
rename and earlier fork changes are recorded in
`docs/upstream-followups-20260921.md` and the changelog.

The logic lives in new files so merges touch as few upstream lines as possible:

| New file | Purpose |
|---|---|
| `Sources/SmartFanCore/SMCSensorFilter.swift` | Drops SMC keys that IOHID identifies as battery sensors, and die readings below 10°C |
| `Sources/SmartFanCore/ThermalStatus+Display.swift` | CPU row = per-core keys (Stats' M4 map on the M4 generation); headline = hotter of CPU and GPU rows |
| `Sources/SmartFanCore/HighTempProtection.swift` | The graduated high-temperature protection ladder, replacing the single 95 °C threshold |
| `Tests/SmartFanTests/SMCSensorFilterTests.swift`, `DisplayedTemperatureTests.swift`, `HighTempProtectionTests.swift` | Coverage for all three |

## Upstream lines changed

| File | Change | Why |
|---|---|---|
| `Sources/SmartFanCore/FanControl.swift`, `readTemp` | +1 line: `guard SMCSensorFilter.accepts(key, temp) else { return nil }` after the 0–150°C range check | Single choke point shared by `status()` and the daemon's safety sweep |
| `Sources/SmartFanCore/FanControl.swift`, `thermalKeys` | +2 lines after the `Tp*` block: comment and `"Tp0V", "Tp0Y", "Tp0e", "Te05", "Te0S", "Te09", "Te0H"` | M4 core keys upstream does not probe |
| `Sources/SmartFanApp/MenuBarView.swift`, CPU `TemperatureRow` | `peakTemp(prefixes: ["TC", "Tp"])` → `appState.latestStatus?.displayedCPUTemp` | CPU row uses core keys, not hotspot keys |
| `Sources/SmartFanApp/AppState.swift`, `startMonitoring` `onUpdate` | The `displayPrefixes` filter → `self?.maxTemp = status.displayedPeakTemp` | Headline matches the panel |
| `Sources/SmartFanCore/ThermalMonitor.swift`, `tick` | The 95/90 latch → `HighTempProtection.evaluate(...)`; new `setProtection` and `applyProtectionSpeed` | The ladder, and the settings that turn it off |
| `Sources/SmartFanCore/Profile.swift` | `safetyTempThreshold` (95) → `emergencyTempThreshold` (105) | The daemon's floor moves above the ladder; see the divergence below |
| `Sources/SmartFanCore/DaemonInvariants.swift` | `ThermalFloor` default threshold → `FanProfile.emergencyTempThreshold` | Same |

Deliberately **not** changed: `ThermalStatus.safetyPeakTemp`, `FanControl.safetyTempKeys`,
the daemon's safety sweep, the profile curves. Fan control still follows the hottest
key, including `TCDX`/`TCMb`/`Tp06` — a known, measured divergence from the panel's
reading (the safety basis reads ~9 °C high) that is recorded in
`docs/high-temp-protection-plan.md` §5 and deliberately left for later.

## Re-applying after an upstream merge

1. Resolve conflicts in the four places above by keeping upstream's code and
   re-applying the listed one-line changes.
2. If upstream edits `thermalKeys`, keep the M4 key line; drop any key upstream
   now lists itself.
3. If upstream changes how the CPU row or headline is computed, compare with
   `ThermalStatus+Display.swift` and keep whichever matches the Stats key map;
   `DisplayedTemperatureTests` encodes the measured M4 Max case.
4. Run `scripts/setup.sh test` and `scripts/setup.sh test --release`, then compare the CPU
   and GPU rows with Stats under CPU and GPU load
   (`scripts/thermal-calibration/`).

## Deliberate behaviour divergences

These are product choices, not accidents. An upstream merge that touches the same
code will conflict, and upstream's own tests may encode the other choice — resolve
in favour of this list.

### A mode chosen from the menu skips the sustained window

`ThermalMonitor.switchProfile` sets `sustainedAboveSeconds` to the new profile's
`sustainedTriggerSec`, so a deliberate choice acts on the next tick whenever the
temperature qualifies instead of waiting 4–8 s. The window still applies normally
if the temperature later drops and has to rise again: it exists to filter transient
spikes, and a click is not a spike.

Upstream restarts the window and encodes that in
`ControlLoopRecoveryTests.newProfileTiming`, which therefore differs here.

### The ramp continues from the fans' current speed

`switchProfile` seeds `lastAppliedRPMPercent` from the actual RPM instead of 0.
Seeding zero made the first command after a switch the minimum speed, so choosing a
mode could slow the fans down before speeding them up.

### A cooldown between mode changes

`ModeSwitchCooldown` (Core) refuses another controlling mode within 10 s of the last
change; Default is exempt because it hands the fans back to Apple and is the escape
hatch when they are loud. Choosing Default still arms the cooldown, so the two
cannot be flipped back and forth either.

### "Idle" is not shown for the fan state

The Fans page Status row answers who controls the fans — the profile name, SAFETY,
Fixed Rate, or Apple auto — rather than reporting the monitor's own idle state,
which read as "the fan is idle" next to a spinning fan.

### High-temperature protection is a ladder, not a threshold

Upstream maxes the fans the moment a single 10 Hz sample reads 95 °C, and releases them
as soon as one reads below 90 °C. A die reading that swings 6–11 °C in two seconds
crossed both lines repeatedly, so the fans spun for a few seconds and stopped again,
over and over, and the mode that hands the fans to Apple was overridden by a controller
fighting the system's own.

`HighTempProtection` (Core) replaces it with the ladder in
`docs/high-temp-protection-plan.md`: half fan speed after ten seconds at 90 °C, full
after thirty seconds at 95 °C, and back down the same steps once each has been held for
thirty seconds. Off means never, and a hands-off mode is left alone unless the user
asks otherwise.

### The daemon's floor sits above the ladder

`ThermalFloor` engaged at 95 °C whenever it was holding the fans below max — the same
band the ladder works in, and the same sensor keys, so the two would fight over one fan:
the daemon would jump straight to max and skip the graduated steps. Its threshold is now
`FanProfile.emergencyTempThreshold` (105 °C, clearing below 100), above the ladder's
range *and* above its 30 s escalation window. The ladder owns the graduated response;
the floor is the backstop for a client that has stopped responding while pinning the
fans low.

`ControlLoopRecoveryTests` and `DaemonInvariantsTests` encode both.

