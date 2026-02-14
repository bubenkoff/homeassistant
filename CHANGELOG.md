# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Document boiler control system, automation logic, and diagnostics in CLAUDE.md
- Widen 30% modulation band (demand ≤1.0°C) to reduce short cycling; shift all thresholds up
- Add Aqara Hub M100 as second Thread Border Router for failover (ZBT-2 OTBR unreliable after HA restarts)
- Fix ZBT-2 OTBR "Unable to connect" by reflashing firmware and USB replug sequence
- Add Aqara H2 EU 4-button switch (2-channel) for living room back entrance
- Configure H2 in coupled mode (upper buttons = direct relay, lower buttons = toggle via automation)
- Connect H2 via Matter/Thread directly (bypassing M100 Zigbee bridge) for lower latency
- Add automation for H2 lower buttons to toggle lights
- Switch H2 to Zigbee via M100 with coupled mode; lower button automations in Aqara Home app
- Remove HA automation for H2 (replaced by Aqara Home automations on M100 hub)
- Add Aqara H1 Wireless Switch for living room back door (pass-through via Aqara automations on M100)
- Fix humidity control: sync dehumidifier with fan by lowering threshold from 5 to 0; add explicit medium fan threshold variable
- Enable H1 multi-function mode; add double-click right button to toggle backyard floodlight
- Enable H2 multi-function mode; M100 Matter bridge does not forward multi-press events for wired switches (only initial_press)
- Re-pair H2 to M100 to refresh Matter endpoints; rename entities to living_room_front_door_switch_* pattern
- Submit bug report to Aqara support: M100 should expose multi_press_2/long_press for H2 like it does for H1
- Add double-click left button on H1 (back door) to toggle front door camera floodlight
- Change floodlight automations to auto-off after 15 min; double-click again to turn off immediately
- Add second Aqara H1 Wireless Switch for stairs door; rename entities to living_room_stairs_door_switch_*
- Simplify floodlight automations: merge 4 into 2, each with two triggers (back door + stairs door switches)
