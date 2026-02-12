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
