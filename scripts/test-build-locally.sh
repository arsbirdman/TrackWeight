#!/bin/bash

# test-build-locally.sh
# Test the GitHub Actions workflow steps locally on macOS

set -e

echo "🧪 Testing TrackWeight Build Workflow Locally"
echo "=============================================="

# Load environment variables from .env file
if [[ -f ".env" ]]; then
  echo "📄 Loading environment variables from .env file..."
  # Export all variables from .env file
  set -a  # automatically export all variables
  source .env
  set +a  # turn off automatic export
  echo "✅ Environment variables loaded"
else
  echo "⚠️  No .env file found - some features may not work"
fi

# Configuration
export APP_NAME="Weightpad"
export SCHEME="TrackWeight"
export CONFIGURATION="Release"
export BUILD_DIR="$(pwd)/local_build"

# Clean up previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ""
echo "Step 1: Building and Archiving App (Universal Binary)"
echo "====================================================="
xcodebuild \
  -project TrackWeight.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  archive

echo ""
echo "Step 1.5: Setting up Code Signing (if available)"
echo "================================================"
if [[ -n "$BUILD_CERTIFICATE_BASE64" && -n "$P12_PASSWORD" ]]; then
  echo "🔐 Setting up code signing certificate from .env..."
  
  # Decode and import certificate
  echo "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$BUILD_DIR/certificate.p12"
  
  # Import into keychain (temporary)
  security import "$BUILD_DIR/certificate.p12" -k ~/Library/Keychains/login.keychain-db -P "$P12_PASSWORD" -T /usr/bin/codesign
  
  echo "✅ Certificate imported successfully"
  echo "📝 Note: Certificate will remain in keychain after script completion"
else
  echo "⚠️  No certificate in .env - will use existing keychain certificates"
fi

echo ""
echo "Step 2: Exporting App"
echo "===================="
# Use existing ExportOptions.plist or create a basic one
if [[ ! -f "ExportOptions.plist" ]]; then
  echo "Creating basic ExportOptions.plist..."
  cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
else
  cp ExportOptions.plist "$BUILD_DIR/ExportOptions.plist"
fi

        xcodebuild \
          -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
          -exportPath "$BUILD_DIR/export" \
          -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
          -exportArchive
  
  # Re-sign the framework explicitly to ensure proper signature
  if [[ -n "$BUILD_CERTIFICATE_BASE64" && -n "$P12_PASSWORD" ]]; then
    echo "🔏 Re-signing framework with Developer ID certificate..."
    FRAMEWORK_PATH="$BUILD_DIR/export/$APP_NAME.app/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
    if [[ -d "$FRAMEWORK_PATH" ]]; then
      codesign --force --sign "Developer ID Application: Krish Shah (9ZRLG6277G)" \
        --options runtime \
        --timestamp \
        "$FRAMEWORK_PATH/Versions/A/OpenMultitouchSupportXCF"
      
      codesign --force --sign "Developer ID Application: Krish Shah (9ZRLG6277G)" \
        --options runtime \
        --timestamp \
        "$FRAMEWORK_PATH"
      
      echo "✅ Framework re-signed successfully"
    fi
    
    # Re-sign the main app to ensure everything is consistent
    echo "🔏 Re-signing main application..."
    codesign --force --sign "Developer ID Application: Krish Shah (9ZRLG6277G)" \
      --options runtime \
      --entitlements "TrackWeight/TrackWeight.entitlements" \
      --timestamp \
      --deep \
      --strict \
      "$BUILD_DIR/export/$APP_NAME.app"
    
    echo "✅ Application re-signed successfully"
  fi

echo ""
echo "Step 2.5: Verifying Universal Binary and Code Signatures"
echo "========================================================"
echo "🏗️ Verifying Universal Binary Architecture..."
APP_BINARY="$BUILD_DIR/export/$APP_NAME.app/Contents/MacOS/$APP_NAME"
if [[ -f "$APP_BINARY" ]]; then
  echo "📊 Binary architectures:"
  lipo -archs "$APP_BINARY"
  
  if lipo -archs "$APP_BINARY" | grep -q "arm64" && lipo -archs "$APP_BINARY" | grep -q "x86_64"; then
    echo "✅ Universal binary confirmed: Contains both ARM64 and x86_64"
  else
    echo "❌ Warning: Binary may not be universal"
    lipo -detailed_info "$APP_BINARY"
  fi
fi

# Check framework architecture if it exists
FRAMEWORK_PATH="$BUILD_DIR/export/$APP_NAME.app/Contents/Frameworks/OpenMultitouchSupportXCF.framework"
if [[ -d "$FRAMEWORK_PATH" ]]; then
  FRAMEWORK_BINARY="$FRAMEWORK_PATH/Versions/A/OpenMultitouchSupportXCF"
  if [[ -f "$FRAMEWORK_BINARY" ]]; then
    echo "📊 Framework architectures:"
    lipo -archs "$FRAMEWORK_BINARY"
  fi
fi

echo "🔍 Verifying main application signature..."
codesign --verify --verbose "$BUILD_DIR/export/$APP_NAME.app" || echo "⚠️ Main app signature verification failed"

echo "🔍 Verifying framework signature..." 
if [[ -d "$FRAMEWORK_PATH" ]]; then
  codesign --verify --verbose "$FRAMEWORK_PATH" || echo "⚠️ Framework signature verification failed"
fi

echo "🔍 Checking for hardened runtime..."
RUNTIME_FLAGS=$(codesign --display --verbose "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | grep "flags=")
if [[ "$RUNTIME_FLAGS" == *"runtime"* ]]; then
  echo "✅ Hardened runtime enabled: $RUNTIME_FLAGS"
else
  echo "⚠️ No hardened runtime detected: $RUNTIME_FLAGS"
fi

echo "🔍 Checking certificate validity..."
codesign --display --verbose=4 "$BUILD_DIR/export/$APP_NAME.app" | grep -E "(Authority|Timestamp|TeamIdentifier)" || echo "Certificate details extracted"

echo "🔍 Deep verification with online validation..."
if codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/export/$APP_NAME.app"; then
  echo "✅ Deep verification passed"
else
  echo "⚠️ Deep verification failed but continuing..."
fi

echo ""
echo "Step 3: Testing Notarization (Optional)"
echo "======================================="
if [[ -n "$APPLE_ID" && -n "$APPLE_ID_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
  echo "🍎 Starting notarization with provided credentials..."
  
  cd "$BUILD_DIR/export"
  echo "📦 Creating zip file for notarization..."
  # Use ditto for creating zip compatible with Apple's notarization service
  ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
  
  echo "📤 Submitting for notarization..."
  if xcrun notarytool submit "$APP_NAME.zip" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --timeout 20m; then
    
    echo "✅ Notarization successful!"
    
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple "$APP_NAME.app"
    
    echo "✅ Verifying notarization..."
    xcrun stapler validate "$APP_NAME.app"
    
    echo "✅ Notarization complete!"
  else
    echo "❌ Notarization failed!"
    echo "🔍 This could be due to:"
    echo "   - Invalid Apple credentials"
    echo "   - App signing issues"
    echo "   - Missing hardened runtime"
    echo "   - Sandbox/entitlement issues"
    echo "   - Deprecated APIs"
    echo ""
    echo "⚠️  Continuing without notarization..."
  fi
  
  # Return to original directory
  cd "$BUILD_DIR"
else
  echo "⚠️  Skipping notarization (set APPLE_ID, APPLE_ID_PASSWORD, APPLE_TEAM_ID to test)"
fi

echo ""
echo "Step 4: Creating DMG"
echo "==================="
# Install create-dmg if not present
if ! command -v create-dmg &> /dev/null; then
  echo "Installing create-dmg..."
  brew install create-dmg
fi

# Create a clean directory with only the app for DMG creation
echo "📁 Preparing clean DMG contents..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy only the app to staging directory
cp -R "$BUILD_DIR/export/$APP_NAME.app" "$DMG_STAGING/"

# Create DMG with appropriate naming
if [[ -n "$APPLE_ID" && -n "$APPLE_ID_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
  DMG_NAME="$APP_NAME-local-NOTARIZED.dmg"
else
  DMG_NAME="$APP_NAME-local-SIGNED.dmg"
fi

echo "📀 Creating professional DMG..."
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 300 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 120 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 425 120 \
  --hdiutil-quiet \
  "$BUILD_DIR/$DMG_NAME" \
  "$DMG_STAGING/"

echo ""
echo "🎉 Local Build Complete!"
echo "======================="
echo "📦 DMG created: $BUILD_DIR/$DMG_NAME"
echo "📁 Build directory: $BUILD_DIR"
echo ""
if [[ -n "$APPLE_ID" && -n "$APPLE_ID_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
  echo "✅ Notarization was attempted using credentials from .env"
else
  echo "ℹ️  To enable notarization, add these to your .env file:"
  echo "   APPLE_ID=your@email.com"
  echo "   APPLE_ID_PASSWORD=xxxx-xxxx-xxxx-xxxx"
  echo "   APPLE_TEAM_ID=ABC1234567"
fi
echo ""
echo "🔧 Cleaning up temporary files..."
rm -f "$BUILD_DIR/certificate.p12"
rm -rf "$DMG_STAGING"
echo "✅ Cleanup complete" 