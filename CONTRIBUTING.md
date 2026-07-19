# Contributing to Freescale

Thanks for helping! The single most valuable contribution right now is **verifying
scales on real hardware** — most drivers are ported blind from openScale and marked
*experimental* until someone confirms them.

## Test or add your scale (no coding needed)

1. Build and run the app on your iPhone (see [README](README.md)).
2. Open the **"Raw data (calibration)"** card at the bottom.
3. Tap **Search** and step on your scale (barefoot for body composition).
4. Open a **[new issue → "Test or add a scale"](../../issues/new/choose)** and paste:
   - Your scale's exact **model** and BLE name
   - Several **raw hex lines** from the log
   - Your **real weight** at that moment (and, if known, body fat %)
   - Whether the value shown was correct / wrong / missing

That's enough for us to calibrate or write a new driver.

## Add a driver (coding)

A scale is one file implementing `ScaleDriver`:

- **Passive scales** (data in the BLE advertisement): set `kind = .advertisement`,
  implement `matches(...)` and `parse(serviceData:localName:)`.
- **Connection scales** (GATT): set `kind = .connection`, provide a
  `connectionProfile` (services + characteristics to subscribe) and implement
  `handle(characteristic:data:)`.

Then register it in `ScaleDriverRegistry.all`. Keep `isTested = false` until it has
been confirmed on real hardware. Look at `MiBodyCompositionScale2Driver` (advertisement)
and `GenericSIGScaleDriver` (connection) as templates.

Reference protocols live in the [openScale source](https://github.com/oliexdev/openScale/tree/master/android_app).

## Ground rules

- License is **GPL‑3.0‑or‑later**; by contributing you agree your code is under it.
- Keep the core body‑metric formulas **Xiaomi/Mi‑Fit‑compatible** unless clearly labelled.
- Never claim a driver "works" without hardware confirmation — mark it experimental.
- Health values are estimates; don't present them as medical facts.

## Dev setup

Open `OpenScaleIOS.xcodeproj` in Xcode, run on a real device. New `.swift` files added
to the `OpenScaleIOS` folder are picked up automatically (synchronized folder groups).
