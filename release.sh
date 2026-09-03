#!/bin/bash

# Dorso Release Script
# Creates a new release with build, signing, notarization, DMG, and GitHub release

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Code signing identity
DEVELOPER_ID="Developer ID Application: Thomas Johnell (KBF2YGT2KP)"
NOTARY_PROFILE="notarytool-dorso"

# Check for required dependencies
check_dependency() {
    local cmd="$1"
    local install_cmd="$2"
    local description="$3"

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed${NC}"
        echo -e "$description"
        echo ""
        echo -e "Install with: ${CYAN}$install_cmd${NC}"
        echo ""
        echo -n "Would you like to install it now? (y/N): "
        read INSTALL
        if [ "$INSTALL" = "y" ] || [ "$INSTALL" = "Y" ]; then
            eval "$install_cmd"
            if ! command -v "$cmd" &> /dev/null; then
                echo -e "${RED}Installation failed. Please install manually.${NC}"
                exit 1
            fi
            echo -e "${GREEN}$cmd installed successfully${NC}"
        else
            exit 1
        fi
    fi
}

# Check Xcode Command Line Tools (for swiftc)
if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}Error: Xcode Command Line Tools not installed${NC}"
    echo -e "Required for compiling Swift code"
    echo ""
    echo -e "Install with: ${CYAN}xcode-select --install${NC}"
    exit 1
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}Error: Homebrew is not installed${NC}"
    echo -e "Required for installing dependencies"
    echo ""
    echo -e "Install with: ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
    exit 1
fi

# Check for create-dmg
check_dependency "create-dmg" "brew install create-dmg" "Required for creating DMG installer"

# Check for gh (GitHub CLI)
check_dependency "gh" "brew install gh" "Required for creating GitHub releases"

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}GitHub CLI is not authenticated${NC}"
    echo -n "Would you like to authenticate now? (y/N): "
    read AUTH
    if [ "$AUTH" = "y" ] || [ "$AUTH" = "Y" ]; then
        gh auth login
    else
        echo -e "${YELLOW}Skipping GitHub release creation${NC}"
        SKIP_GH_RELEASE=true
    fi
fi

# Check for git
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git is not installed${NC}"
    exit 1
fi

# Check for Developer ID certificate
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo -e "${RED}Error: Developer ID Application certificate not found${NC}"
    echo -e "Please install your Developer ID certificate first"
    exit 1
fi

# Get version from argument or prompt
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo -n "Enter version (e.g., 1.0.1): "
    read VERSION
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
    echo -e "${RED}Invalid version format. Use: X.Y.Z or X.Y.Z-suffix${NC}"
    exit 1
fi

# The appcast entry is generated from build.sh's version fields, so they must
# match the release version or auto-update would offer the wrong build
BUILD_SH_VERSION=$(grep '^VERSION=' build.sh | cut -d'"' -f2)
BUILD_NUMBER=$(grep '^BUILD_NUMBER=' build.sh | cut -d'"' -f2)
MIN_MACOS=$(grep '^MIN_MACOS=' build.sh | cut -d'"' -f2)
if [ "$VERSION" != "$BUILD_SH_VERSION" ]; then
    echo -e "${RED}Error: release version $VERSION does not match build.sh VERSION=$BUILD_SH_VERSION${NC}"
    echo "Bump VERSION (and BUILD_NUMBER) in build.sh first."
    exit 1
fi

# Sparkle tools ship with the SwiftPM artifact
SPARKLE_BIN="$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo -e "${YELLOW}Sparkle tools not found; fetching packages...${NC}"
    swift package resolve
fi
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo -e "${RED}Error: sign_update not found at $SPARKLE_BIN${NC}"
    exit 1
fi

TAG="v$VERSION"
ZIP_NAME="Dorso-$TAG.zip"
DMG_NAME="Dorso-$TAG.dmg"

echo ""
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  Dorso Release Script - $TAG${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    echo -n "Continue anyway? (y/N): "
    read CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        exit 1
    fi
fi

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${YELLOW}Tag $TAG already exists${NC}"
    echo -n "Delete and recreate? (y/N): "
    read DELETE_TAG
    if [ "$DELETE_TAG" = "y" ] || [ "$DELETE_TAG" = "Y" ]; then
        git tag -d "$TAG" 2>/dev/null || true
        git push origin ":refs/tags/$TAG" 2>/dev/null || true
    else
        exit 1
    fi
fi

# Step 1: Build
echo -e "${GREEN}[1/8] Building app...${NC}"
./build.sh

# Step 2: Code sign with Developer ID
echo -e "${GREEN}[2/8] Signing app with Developer ID...${NC}"

# Sign Sparkle's nested components first (inside-out order), per Sparkle's
# distribution docs. All need hardened runtime for notarization.
SPARKLE_FW="build/Dorso.app/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --preserve-metadata=entitlements --sign "$DEVELOPER_ID" --timestamp "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$SPARKLE_FW/Versions/B/Autoupdate"
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$SPARKLE_FW/Versions/B/Updater.app"
codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$SPARKLE_FW"

codesign --force --options runtime --entitlements "build/Dorso.entitlements" --sign "$DEVELOPER_ID" --timestamp "build/Dorso.app"

# Verify signature
echo "Verifying signature..."
codesign --verify --deep --strict "build/Dorso.app"
echo -e "${GREEN}Signature verified${NC}"

# Step 3: Create ZIP for notarization
# ditto preserves Sparkle.framework's symlinks; zip -r would flatten them and
# break the code signature
echo -e "${GREEN}[3/8] Creating ZIP for notarization...${NC}"
rm -f "build/$ZIP_NAME"
ditto -c -k --keepParent build/Dorso.app "build/$ZIP_NAME"

# Step 4: Submit for notarization
echo -e "${GREEN}[4/8] Submitting for notarization (this may take a few minutes)...${NC}"
xcrun notarytool submit "build/$ZIP_NAME" --keychain-profile "$NOTARY_PROFILE" --wait

# Step 5: Staple the notarization ticket
echo -e "${GREEN}[5/8] Stapling notarization ticket...${NC}"
xcrun stapler staple "build/Dorso.app"

# Recreate ZIP with stapled app
rm -f "build/$ZIP_NAME"
ditto -c -k --keepParent build/Dorso.app "build/$ZIP_NAME"

# Step 6: Create DMG (with notarized app)
echo -e "${GREEN}[6/8] Creating DMG...${NC}"
hdiutil detach /Volumes/Dorso 2>/dev/null || true
rm -f "build/$DMG_NAME"

create-dmg \
    --volname "Dorso" \
    --volicon "build/Dorso.app/Contents/Resources/AppIcon.icns" \
    --background "assets/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 654 444 \
    --icon-size 140 \
    --text-size 12 \
    --icon "Dorso.app" 197 195 \
    --hide-extension "Dorso.app" \
    --app-drop-link 473 195 \
    "build/$DMG_NAME" \
    build/Dorso.app

# Sign and notarize the DMG too
echo "Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" --timestamp "build/$DMG_NAME"

echo "Notarizing DMG..."
xcrun notarytool submit "build/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling DMG..."
xcrun stapler staple "build/$DMG_NAME"

# Step 7: Create git tag and GitHub release
echo -e "${GREEN}[7/8] Creating git tag and GitHub release...${NC}"
git tag "$TAG"
git push origin "$TAG"

RELEASE_NOTES="## Dorso $TAG

A macOS app that blurs your screen when you slouch.

### Features
- Real-time posture monitoring using Vision framework
- Multi-screen corner calibration for personalized detection
- Progressive blur that eases in gently
- Adjustable sensitivity and dead zone
- Camera selection (supports external webcams)
- Universal binary (Apple Silicon + Intel)
- **Signed and notarized** by Apple

### Installation

1. Download the \`.dmg\` or \`.zip\`
2. Drag \`Dorso.app\` to Applications
3. Launch normally - no Gatekeeper warning!
4. Grant camera permission, then complete calibration

### Requirements
- macOS 13.0 (Ventura) or later"

if [ "$SKIP_GH_RELEASE" = "true" ]; then
    echo -e "${YELLOW}Skipping GitHub release (not authenticated)${NC}"
    echo ""
    echo "To create the release manually, run:"
    echo -e "${CYAN}gh auth login${NC}"
    echo -e "${CYAN}gh release create $TAG build/$ZIP_NAME build/$DMG_NAME --title \"Dorso $TAG\"${NC}"
else
    # Delete existing release if present
    gh release delete "$TAG" --yes 2>/dev/null || true

    # Create release
    gh release create "$TAG" \
        "build/$ZIP_NAME" \
        "build/$DMG_NAME" \
        --title "Dorso $TAG" \
        --notes "$RELEASE_NOTES"

    echo -e "${GREEN}Release created!${NC}"
fi

# Step 8: Update the Sparkle appcast so existing installs see this release.
# The EdDSA signature must be of the exact ZIP uploaded to GitHub.
echo -e "${GREEN}[8/8] Updating appcast...${NC}"
SIGN_ATTRS=$("$SPARKLE_BIN/sign_update" "build/$ZIP_NAME")
PUB_DATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")
DOWNLOAD_URL="https://github.com/tldev/dorso/releases/download/$TAG/$ZIP_NAME"
RELEASE_URL="https://github.com/tldev/dorso/releases/tag/$TAG"

# Drop any existing appcast item for this tag (re-release), then insert the
# new item below the marker comment
awk -v tag="releases/download/$TAG/" '
    /<item>/ { buf = $0 ORS; initem = 1; drop = 0; next }
    initem {
        buf = buf $0 ORS
        if (index($0, tag)) drop = 1
        if (/<\/item>/) { if (!drop) printf "%s", buf; initem = 0 }
        next
    }
    { print }
' appcast.xml > build/appcast.tmp && mv build/appcast.tmp appcast.xml

cat > build/appcast-item.xml << EOF
        <item>
            <title>Version $VERSION</title>
            <link>$RELEASE_URL</link>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>$RELEASE_URL</sparkle:releaseNotesLink>
            <pubDate>$PUB_DATE</pubDate>
            <enclosure
                url="$DOWNLOAD_URL"
                $SIGN_ATTRS
                type="application/octet-stream"/>
        </item>
EOF
sed -i '' "/release.sh inserts new release items below this line/r build/appcast-item.xml" appcast.xml
rm -f build/appcast-item.xml

if ! git diff --quiet -- appcast.xml; then
    git commit -m "Update appcast for $TAG" -- appcast.xml
    if git push origin HEAD; then
        echo -e "${GREEN}Appcast published${NC}"
    else
        echo -e "${YELLOW}Could not push appcast.xml; push it manually or the update will not reach users${NC}"
    fi
else
    echo -e "${YELLOW}appcast.xml unchanged; nothing to publish${NC}"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Release $TAG complete!${NC}"
echo -e "${GREEN}  App is signed and notarized!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "Files:"
ls -lh "build/$ZIP_NAME" "build/$DMG_NAME" 2>/dev/null
echo ""
echo -e "Release URL: ${CYAN}https://github.com/tldev/dorso/releases/tag/$TAG${NC}"
