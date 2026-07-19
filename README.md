# OpenTara

*Open-source smart scale companion.*

**Local, private iOS app for Bluetooth body composition scales — no vendor account, no cloud.**

OpenTara reads Bluetooth body scales directly on your iPhone and computes the full
set of body metrics locally. All data stays on your device. It exists because the
excellent [openScale](https://github.com/oliexdev/openScale) is Android‑only, leaving
iPhone users with cloud‑bound vendor apps as the only option.

> ⚕️ **Not a medical device.** All values are estimates for personal orientation only.

---

## Features

- Read supported scales over BLE — **passively** (advertisement) or via **connection** (GATT)
- Body metrics with the original Xiaomi/Huami formulas (match Zepp Life / Mi Fit):
  weight, BMI + WHO class, body fat, water, muscle mass, bone mass, visceral fat,
  BMR, metabolic age, **protein, lean body mass, body type, body score**, ideal weight
- Waist/hip/chest/thigh/biceps/neck circumferences + WHtR/WHR, comments
- History with chart (weight / BMI / body fat), edit & delete, **manual entry**
- Multiple profiles with **automatic assignment by weight** (asks when ambiguous)
- Goal ring + projection ("reach your goal around …")
- Assisted weighing (babies / pets)
- Daily weigh‑in reminder
- Statistics, colour‑coded assessment, kg / lb / st units, show/hide metrics
- CSV import/export, PDF report (for your doctor)
- Fully offline, no account, no tracking

## Supported scales

See **[SUPPORTED_SCALES.md](SUPPORTED_SCALES.md)** for the live list and status.

| Scale | Type | Status |
|-------|------|--------|
| Xiaomi Mi Body Composition Scale 2 (MIBFS) | advertisement | ⚠️ pending hardware calibration |
| Xiaomi Mi Smart Scale v1 (weight only) | advertisement | 🧪 experimental |
| Bluetooth‑SIG standard scales (0x181D / 0x181B) | connection | 🧪 experimental |

**Have a Bluetooth scale? We need you.** Most drivers are ported from openScale but
**not yet verified on real hardware**. Helping is easy — see
**[CONTRIBUTING.md](CONTRIBUTING.md)** ("Test or add your scale").

## Requirements

- iPhone (a **real device** — the Simulator has no Bluetooth)
- **Xcode** (macOS)
- An Apple ID for signing (free works; app expires after 7 days — a paid Apple
  Developer account removes that limit)

## Build & run

```bash
git clone https://github.com/<your-user>/opentara.git
cd opentara
open OpenScaleIOS.xcodeproj
```

In Xcode: select your Apple ID team under *Signing & Capabilities*, pick your iPhone
as the run destination, and press ▶. On first launch, trust the developer certificate
under *Settings → General → VPN & Device Management* on the iPhone.

The Bluetooth usage description (`NSBluetoothAlwaysUsageDescription`) must be present in
the target's Info settings.

## How it works

- `ScaleDriver` — protocol every scale implements; `ScaleDriverRegistry` lists them
- `.advertisement` drivers parse passive BLE broadcasts (e.g. Xiaomi)
- `.connection` drivers connect and subscribe to GATT characteristics (e.g. SIG scales)
- `ScaleManager` — scans, routes packets to drivers, handles connections
- `BodyMetrics` / `BodyMetricsExtra` — the body‑composition formulas
- Raw BLE bytes are logged in‑app to make calibrating new scales easy

Adding a scale = one new `ScaleDriver` in a file. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Localization

The app is being localized via a String Catalog. See
**[LOCALIZATION.md](LOCALIZATION.md)** for status and how to add a language.

## Privacy

No account, no network calls, no analytics. Everything is stored locally on the device.
See **[PRIVACY.md](PRIVACY.md)**.

## Support

OpenTara is free and open source. If it's useful to you, you can support development:

☕ **[Buy me a coffee](https://buymeacoffee.com/etlami)**

## Credits & license

- Formulas & BLE protocols ported from **[openScale](https://github.com/oliexdev/openScale)**
  and **[bodymiscale](https://github.com/dckiller51/bodymiscale)** (both GPLv3).
- Licensed under **GPL‑3.0‑or‑later** — see [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).

This project is not affiliated with openScale, bodymiscale, or Xiaomi.
