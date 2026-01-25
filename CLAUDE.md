# Claude Code Instructions for Posturr

## Releasing

### GitHub Release (Direct Distribution)
Always use the release script for GitHub releases:
```bash
./release.sh 1.0.X
```

This script handles:
- Building the app
- Code signing with Developer ID
- Apple notarization
- DMG creation with drag-to-Applications
- ZIP archive
- Git tagging
- GitHub release with proper template

**Never manually create GitHub releases** - the script ensures proper signing, notarization, and consistent release notes.

### App Store Release
For App Store submissions:
```bash
./build.sh --appstore
```

Then sign and package:
```bash
# Copy to appstore folder
cp -r build/Posturr.app build-appstore/

# Sign with Apple Distribution
cd build-appstore
codesign --force --options runtime \
    --entitlements Posturr.entitlements \
    --sign "Apple Distribution: Thomas Johnell (KBF2YGT2KP)" \
    --timestamp \
    Posturr.app

# Create installer package
productbuild \
    --component Posturr.app /Applications \
    --sign "3rd Party Mac Developer Installer: Thomas Johnell (KBF2YGT2KP)" \
    Posturr.pkg

# Upload
xcrun altool --upload-app -f Posturr.pkg -t macos -u tjohnell@gmail.com -p APP_SPECIFIC_PASSWORD
```

## Build Configurations

- `./build.sh` - Regular build with private APIs (for GitHub/direct distribution)
- `./build.sh --appstore` - App Store build without private APIs
- `./build.sh --release` - Regular build + creates ZIP archive

## Version Bumping

Update version in BOTH files before releasing:
- `build.sh` - VERSION variable
- `appstore-release.sh` - VERSION variable

## Key Files

- `main.swift` - All application code
- `build.sh` - Build script with App Store support
- `release.sh` - Full GitHub release automation
- `appstore-release.sh` - App Store packaging reference
- `PRIVACY.md` - Privacy policy for App Store
