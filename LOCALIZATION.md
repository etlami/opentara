# Localization

OpenTara's UI is currently written in German string literals. SwiftUI makes these
localizable through a **String Catalog** (`Localizable.xcstrings`). The development
(source) language is German; other languages are added as translations.

## Status

- [ ] Add `Localizable.xcstrings` and register languages in Xcode
- [ ] Extract strings (automatic on build)
- [ ] English (en)
- [ ] French (fr), Spanish (es), Italian (it), … (as contributors provide them)
- [ ] Localize `String(format:)` values (need a small refactor to localized format strings)

## How to add the String Catalog (one‑time, in Xcode)

1. **File → New → File… → String Catalog**, name it `Localizable`, add to the
   `OpenScaleIOS` target.
2. Select the **project** in the navigator → target **OpenScaleIOS** is fine, but set
   languages on the **project**: *Info → Localizations → `+`* and add e.g. English, French.
3. **Build once** (⌘B). Xcode extracts every `Text("…")` literal into the catalog.
4. Open `Localizable.xcstrings` and fill in translations (or send the file to a
   translator / open a PR).

## Notes for contributors

- Most UI text is `Text("…")` / `Label("…")` and localizes automatically once the
  catalog exists — just translate the German key.
- A handful of strings use `String(format: "%.1f kg", …)`. These need converting to
  localized format strings (`NSLocalizedString` / catalog entries with placeholders)
  so numbers/units translate correctly. Tracked as a task above.
- Keep body‑type labels (`bodyTypeLabel`) and assessment terms consistent across
  languages.

Want to contribute a language? Open a PR editing `Localizable.xcstrings`, or just open
an issue with the translated strings and we'll add them.
