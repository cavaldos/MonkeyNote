# Release scripts

One-command releases — no manual version edits. The version comes from the tag name.

## Every release (1 command)

```bash
# Commit your code, then create + push the tag (lints/builds first, version comes from the tag name)
./script/release.sh vX.Y.Z
```

Wait for CI to go green — `MonkeyNote.dmg` appears on the GitHub Release page.
Download link in `readme.md` points there, so nothing else to update.

## Tag rules

* Format `vX.Y.Z` (e.g. `v1.3.5`) and **greater** than the last release.
* Never re-tag an old number. No need to touch the version in Xcode or
  `AppConfig.swift` — CI injects `MARKETING_VERSION` from the tag name and
  the About screen reads it from the bundle.
* `release.sh` refuses a dirty tree — commit + push first.

## Local check without releasing

```bash
./ci-local.sh            # lint + Release build
./ci-local.sh v1.3.5     # ...plus validate a tag name
./build.sh v1.3.5        # local DMG stamped with a version
```
