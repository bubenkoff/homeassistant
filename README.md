# Home Assistant Configuration

SSH-based configuration management for Home Assistant.

## Connection Details

| Parameter | Value |
|-----------|-------|
| Host | `homeassistant.local` |
| User | `bubenkoff` |
| OS | Home Assistant OS (Alpine Linux 3.23) |
| Architecture | aarch64 (ARM64) |
| Kernel | 6.12.63-haos |
| HA Version | 2026.1.3 |

## SSH Access

```bash
ssh homeassistant.local
```

## Directory Structure

| Path | Description |
|------|-------------|
| `/homeassistant/` | Main config directory |
| `/config` | Symlink to `/homeassistant` |
| `/homeassistant/.storage/` | Internal HA storage |
| `/homeassistant/custom_components/` | HACS and custom integrations |
| `/homeassistant/scripts/` | Shell scripts |
| `/homeassistant/esphome/` | ESPHome configurations |
| `/homeassistant/nest/` | Nest integration data |

## Configuration Files

- `configuration.yaml` - Main configuration
- `automations.yaml` - Automations
- `scripts.yaml` - Scripts
- `scenes.yaml` - Scenes
- `secrets.yaml` - Secrets (API keys, passwords)

## Custom Components

- **HACS** - Home Assistant Community Store
- **browser_mod** - Browser customization
- **google_home** - Google Home integration

## Integrations

### MQTT Devices
- **Itho** - Ventilation system (`itho/lastcmd`)
- **Wordclock** - LED word clock with light sensor

### Nest
- Event media storage in `/config/nest/event_media/`

### Shell Commands
- `cleanup_recordings` - Clean up camera recordings
- `record_clip` - Record camera clip
- `copy_latest_nest_media` - Copy Nest media files

## Useful Commands

```bash
# View configuration
ssh homeassistant.local "cat /homeassistant/configuration.yaml"

# Check HA version
ssh homeassistant.local "cat /homeassistant/.HA_VERSION"

# View logs
ssh homeassistant.local "tail -f /homeassistant/home-assistant.log"

# List custom components
ssh homeassistant.local "ls /homeassistant/custom_components/"

# List automations
ssh homeassistant.local "cat /homeassistant/automations.yaml"
```

## API Token

Long-lived access token stored at `~/.ha_token` on HA for CLI/API access.

```bash
# Reload automations
TOKEN=$(ssh homeassistant.local "cat ~/.ha_token")
curl -X POST "http://homeassistant.local:8123/api/services/automation/reload" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

## Automations

### Humidity Control
Controls both Itho ventilation and bathroom dehumidifier based on humidity levels.

### Boiler Weather Compensation
Reduces short cycling by calculating optimal water setpoint based on weather and heat demand.

| Entity | Description |
|--------|-------------|
| `weather.forecast_home` | Outside temperature (from weather integration) |
| `sensor.opentherm_boiler_control_setpoint_1` | Current water setpoint |

**Logic:**
- When any room needs heat (demand > 0.2°C): setpoint = 25 + (15 - outside_temp) + demand * 5
- When all rooms at target (demand <= 0): setpoint = 0 (boiler off)
- Setpoint range: 20-55°C

| Entity | Description |
|--------|-------------|
| `input_number.target_humidity` | Target humidity (default: 60%) |
| `sensor.bathroom_climate_sensor_humidity` | Bathroom humidity sensor |
| `switch.bathroom_dehumidifier_socket` | Dehumidifier smart plug (Tuya/LSC) |

**Logic:**
- Dehumidifier ON: when bathroom humidity > target + 5%
- Dehumidifier OFF: when bathroom humidity <= target

## Notes

- The `ha` CLI requires API token authentication
- User `bubenkoff` is in the `wheel` group (sudo access)
- HA database: `home-assistant_v2.db` (~243MB)
- Files owned by root - use `sudo` via SSH to edit
