# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Document boiler control system, automation logic, and diagnostics in CLAUDE.md
- Widen 30% modulation band (demand ≤1.0°C) to reduce short cycling; shift all thresholds up
- Add Aqara Hub M100 as second Thread Border Router for failover (ZBT-2 OTBR unreliable after HA restarts)
- Fix ZBT-2 OTBR "Unable to connect" by reflashing firmware and USB replug sequence
