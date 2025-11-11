#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Building Caliper Sample App${NC}"

# Configuration
PROJECT_NAME="CaliperSampleApp"
SCHEME="CaliperSampleApp"
CONFIGURATION="Release"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/ipa"
IPA_NAME="$PROJECT_NAME.ipa"

# Clean previous builds
echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the app without code signing
echo -e "${BLUE}🔨 Building app (no code signing)...${NC}"
xcodebuild clean build \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    | xcpretty || echo "xcpretty not installed, showing raw output"

# Find the built .app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$PROJECT_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}❌ Failed to find built .app${NC}"
    exit 1
fi

echo -e "${GREEN}✅ App built successfully at: $APP_PATH${NC}"

# Find the link map - search in multiple possible locations
echo -e "${BLUE}🔍 Searching for link map...${NC}"

# First check the Products directory (where LD_MAP_FILE_PATH points to)
PRODUCTS_DIR=$(dirname "$APP_PATH")
LINK_MAP="$PRODUCTS_DIR/$PROJECT_NAME-LinkMap.txt"

if [ ! -f "$LINK_MAP" ]; then
    # Try searching in DerivedData
    LINK_MAP=$(find "$BUILD_DIR/DerivedData" -name "*LinkMap*.txt" -type f 2>/dev/null | head -n 1)
fi

if [ -z "$LINK_MAP" ]; then
    # Try alternative search patterns
    LINK_MAP=$(find "$BUILD_DIR/DerivedData" -name "*.map" -type f 2>/dev/null | head -n 1)
fi

if [ -n "$LINK_MAP" ] && [ -f "$LINK_MAP" ]; then
    echo -e "${GREEN}🗺️  Link map found at: $LINK_MAP${NC}"
    cp "$LINK_MAP" "$BUILD_DIR/$PROJECT_NAME-LinkMap.txt"
    echo -e "${GREEN}📋 Link map copied to: $BUILD_DIR/$PROJECT_NAME-LinkMap.txt${NC}"
else
    echo -e "${RED}⚠️  Link map not found${NC}"
    echo -e "${BLUE}💡 Searched in:${NC}"
    echo -e "  - $PRODUCTS_DIR/$PROJECT_NAME-LinkMap.txt"
    echo -e "  - $BUILD_DIR/DerivedData/**/*LinkMap*.txt"
    echo -e "${BLUE}🔍 All files matching *LinkMap* or *.map in DerivedData:${NC}"
    find "$BUILD_DIR/DerivedData" -type f \( -name "*LinkMap*" -o -name "*.map" \) 2>/dev/null | while read file; do
        echo -e "  ${BLUE}→${NC} $file"
    done || echo -e "  ${RED}None found${NC}"
fi

# Create IPA
echo -e "${BLUE}📦 Creating IPA...${NC}"
mkdir -p "$EXPORT_PATH/Payload"
cp -r "$APP_PATH" "$EXPORT_PATH/Payload/"

cd "$EXPORT_PATH"
zip -r "../$IPA_NAME" Payload
cd - > /dev/null

echo -e "${GREEN}✅ IPA created successfully!${NC}"
echo -e "${GREEN}📱 IPA location: $BUILD_DIR/$IPA_NAME${NC}"

# Display file sizes
echo -e "\n${BLUE}📊 Build Artifacts:${NC}"
ls -lh "$BUILD_DIR/$IPA_NAME"
if [ -f "$BUILD_DIR/$PROJECT_NAME-LinkMap.txt" ]; then
    ls -lh "$BUILD_DIR/$PROJECT_NAME-LinkMap.txt"
fi

echo -e "\n${GREEN}🎉 Build complete!${NC}"
echo -e "\n${BLUE}📝 Summary:${NC}"
echo -e "  • IPA: ${GREEN}$BUILD_DIR/$IPA_NAME${NC}"
echo -e "  • Link Map: ${GREEN}$BUILD_DIR/$PROJECT_NAME-LinkMap.txt${NC}"
echo -e "  • App Bundle: ${GREEN}$APP_PATH${NC}"

