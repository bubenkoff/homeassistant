# Project Instructions

## Git

- **Always `git pull`** at the start of work to ensure the local repo is up to date.

## Changelog

- **Always read `CHANGELOG.md`** at the start of work to understand recent changes.
- **Always update `CHANGELOG.md`** after making any changes to the project.
- Use the `## [Unreleased]` section for new entries.
- Format: `- <short description of what was changed and why>`
- When a release is made, move unreleased entries under a dated heading `## [YYYY-MM-DD]`.

## Boiler Control System

### Architecture

```
Netatmo TRVs (7 rooms) → set water temperature setpoint
Boiler Modulation Control → limits max modulation (boiler power)
OpenTherm Gateway (OTGW) → sends commands to boiler via opentherm_gw.set_max_modulation
```

Netatmo controls **when** to heat (setpoint), automation controls **how hard** (modulation).

### Rooms (Netatmo TRVs)

| Entity                          | Room               |
|---------------------------------|--------------------|
| `climate.living_room`           | Living Room        |
| `climate.kitchen`               | Kitchen            |
| `climate.master_bedroom`        | Master Bedroom     |
| `climate.kateryna_s_bedroom`    | Kateryna's Bedroom |
| `climate.margarya_s_bedroom`    | Margarya's Bedroom |
| `climate.alexander_s_bedroom`   | Alexander's Bedroom|
| `climate.bathroom`              | Bathroom           |

### Automation: Boiler Modulation Control

**File:** `automations.yaml`, id: `boiler_modulation_control`

**Triggers:**
- Home Assistant start
- Every 1 minute (time_pattern)
- Any climate entity state change (with 30s delay)

**Logic:** Calculates `max_heat_demand` — maximum difference (target - current) across all rooms, and sets the corresponding modulation level:

| Demand (°C)  | Max Modulation | Variable         |
|--------------|----------------|------------------|
| ≤ 0          | 30%            | mod_level_low    |
| ≤ 1.0        | 30%            | mod_level_low    |
| ≤ 1.5        | 40%            | mod_level_med    |
| ≤ 3.0        | 50%            | mod_level_high   |
| > 3.0        | 80%            | mod_level_max    |

**Condition:** Command is sent only if the new value differs from current.

### Key Sensors

| Entity                                                                    | Description                   |
|---------------------------------------------------------------------------|-------------------------------|
| `sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting`     | Current modulation limit      |
| `binary_sensor.opentherm_boiler_flame`                                    | Flame status (on/off)         |
| `binary_sensor.opentherm_boiler_hot_water`                                | DHW mode (hot water)          |

### Diagnostics: boiler_report.sh

**File:** `scripts/boiler_report.sh [hours]` (default: 24 hours)

**Requirements:** SSH access to `homeassistant.local`, HA API token from `/data/.ha_token`, access to `otgw.local`.

**Report sections:**
1. **Current state** — flame, water temp, return, modulation, CH mode (from OTGW API)
2. **Rooms** — current/target temperature, demand, hvac_action per room
3. **Flame cycles** — burn cycle analysis split by CH/DHW:
   - Duration distribution: <30s (short), 30s-2min, 2-10min, >10min
   - Stats by modulation level
   - Duty cycle
4. **Automation** — state, last trigger, trigger count by source
5. **MaxMod changes** — modulation change history with demand validation

### Known Issues & Settings

- 20% modulation — too low, boiler cannot sustain flame
- 30% modulation — optimal for low demand, 0 short cycles
- 40% modulation — may cause short cycles at low demand
- Short cycle = flame < 30 seconds (wears out boiler)
- Goal: minimize CH short cycles, keep duty cycle stable

## Thread / Matter Infrastructure

### Border Routers

| Device | Role | Connection | Notes |
|--------|------|------------|-------|
| **ZBT-2** (Nabu Casa) | OTBR addon, RCP | USB-A → HA Green | Unreliable after HA restarts |
| **Aqara Hub M100** | Autonomous BR + Zigbee hub | WiFi, USB-A powered from HA Green | Primary, maintains network independently of HA |

Thread network: `ha-thread-da34`, two border routers for failover.

### W100 Climate Sensors (Matter over Thread)

| Entity prefix | Location |
|---------------|----------|
| `bathroom_climate_sensor` | Bathroom |
| `toilet_climate_sensor` | Toilet |
| `kitchen_climate_sensor` | Kitchen |
| `laundry_climate_sensor` | Laundry |

Sleepy end devices — after Thread network recovery, press button on each W100 to wake up.

### Known Issues: Thread/ZBT-2

- ZBT-2 OTBR often fails to connect after HA restart ("Unable to connect")
- Cause: RCP architecture — Thread stack runs in Docker addon, race condition at startup
- Fix: stop OTBR → unplug ZBT-2 → wait 1 min → replug → restart HA
- If that fails: reflash ZBT-2 firmware via Settings → Devices
- M100 provides failover — W100 sensors stay online even with OTBR down

## Aqara H2 EU Switch (Living Room)

### Connection

- **Protocol:** Zigbee via M100 hub (bridged to HA through Matter)
- **Mode:** Coupled (upper buttons control relays directly; lower buttons via Aqara automations)
- **No neutral:** Works without neutral wire (min 5W load)
- **LED:** Configured via Aqara Home app (stored on device)
- **Automations:** Managed in Aqara Home app (runs on M100 hub, no HA automation needed)

### Entity IDs

| Entity | Description |
|--------|-------------|
| `light.living_room_front_door_left` | Channel 1 (left relay) |
| `light.living_room_front_door_right` | Channel 2 (right relay) |
| `event.living_room_front_door_upper_left` | Upper left button |
| `event.living_room_front_door_lower_left` | Lower left button |
| `event.living_room_front_door_upper_right` | Upper right button |
| `event.living_room_front_door_lower_right` | Lower right button |

### Automation

Managed entirely in Aqara Home app (runs locally on M100 hub). No HA automation needed.

### Naming Convention

Format: `living_room_{location}_{position}` — e.g. `front_door`, `back_door` for different switch locations

## Aqara H1 Wireless Switch (Living Room Back Door)

### Connection

- **Protocol:** Zigbee via M100 hub (bridged to HA through Matter)
- **Battery:** CR2032
- **Automations:** Managed in Aqara Home app (toggle H2 relays, runs locally on M100)
- **Note:** Aqara binding (pass-through) only works between wired switches; battery switches use Aqara automations instead

### Entity IDs

| Entity | Description |
|--------|-------------|
| `event.living_room_back_door_left` | Left button |
| `event.living_room_back_door_right` | Right button |
| `sensor.living_room_back_door_battery` | Battery level |
