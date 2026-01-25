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
- GitHub release creation

**Never manually create GitHub releases** - the script ensures proper signing and notarization.

### After Running release.sh
The script creates generic release notes. **You must update them** with specific changes using:
```bash
gh release edit vX.Y.Z --notes "$(cat <<'EOF'
## What's New

### Bug Fix (or Feature, Improvement, etc.)
- **Short title** - Description of what changed and why it matters.

### Also in this release
- Any other notable points

## Installation

1. Download `Posturr-vX.Y.Z.dmg` or `Posturr-vX.Y.Z.zip`
2. Drag `Posturr.app` to Applications
3. Launch normally - no warnings!
4. Grant camera permission and complete calibration

## Requirements
- macOS 13.0 (Ventura) or later
EOF
)"
```

The release notes should describe what changed since the previous version, not generic feature lists.

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
