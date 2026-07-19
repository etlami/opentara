# Supported scales

Status legend:
- ✅ **verified** — confirmed working on real hardware
- ⚠️ **pending calibration** — driver written, awaiting first real‑hardware check
- 🧪 **experimental** — ported blind from openScale, unverified

| Scale | BLE name | Type | Metrics | Status |
|-------|----------|------|---------|--------|
| Xiaomi Mi Body Composition Scale 2 | `MIBFS` | advertisement | weight + impedance → full body composition | ⚠️ pending calibration |
| Xiaomi Mi Smart Scale (v1) | `MI_SCALE` / `MI SCALE` | advertisement | weight only | 🧪 experimental |
| Bluetooth‑SIG standard scales | varies | connection (GATT) | weight (0x2A9D); body composition + impedance (0x2A9C, best‑effort) | 🧪 experimental |

## Wanted (help welcome)

Common scales openScale supports that could be ported once a tester is available:
Beurer BF700/BF710/BF800, Sanitas SBF70, Silvercrest SBF75, Yunmai (Mini/SE),
Medisana BS444/BS430, Trisa, Excelvan, and other Bluetooth‑SIG compliant scales.

If you own any Bluetooth body scale, please help verify it — see
[CONTRIBUTING.md](CONTRIBUTING.md). Capturing a few raw‑data lines is enough.
