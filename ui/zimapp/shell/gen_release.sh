#!/bin/bash
set -e  # Exit on error

# ========== Configuration ==========
# Core SDK Path
CORE_PATH="/Volumes/T7/Dev/Framework/open-im-sdk-core-enterprise"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "FLUTTER_PROJECT_PATH: $FLUTTER_PROJECT_PATH"

# Server Configuration
HOST="web.openim.io"

# Pgyer Upload API
PGYER_API_KEY="6f43600074306e8bc506ed0cd3275e9e"
PGYER_APP_KEY="d674f8c66f9247d69fd8b66ca8a28ae7"

# App Configuration
ANDROID_APP_ID="io.openim.flutter.enterprise"
IOS_BUNDLE_IDENTIFIER="io.openim.flutter.enterprise"
APP_NAME="IM-FE"

# Push Configuration (release defaults to FCM)
GETUI_APPID=""
GETUI_APPKEY=""
GETUI_APPSECRET=""
HUAWEI_APP_ID=""
PUSH_MODEL="fcm"

# ========== Functions ==========

# Show help message
show_help() {
    echo "Usage: $0 [options] [version-or-branch]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  --android         Build only Android"
    echo "  --ios             Build only iOS"
    echo "  --upload-only     Only upload existing builds"
    echo "  --version         Show script version"
    echo ""
    echo "Arguments:"
    echo "  version-or-branch  Git tag (e.g. v1.2.3) or branch name (builds latest of the branch)."
    echo ""
    echo "Defaults:"
    echo "  - If no version or branch is provided, the latest tag is used."
    echo ""
    echo "Examples:"
    echo "  $0                  # Build Android & iOS from latest tag"
    echo '  $0 v1.2.3           # Build specific tag'
    echo '  $0 feature/foo      # Build latest from branch feature/foo'
    echo "  $0 --android        # Build Android only (latest tag)"
    echo "  $0 --ios v1.2.3     # Build iOS for a specific tag"
    echo "  $0 --upload-only    # Only upload existing builds"
    exit 0
}

# Clean up backup files
cleanup_backups() {
    find "$FLUTTER_PROJECT_PATH" -name "*.bak" -delete
    echo "Cleaned up backup files"
}

# Upload build artifacts
upload_builds() {
    echo "Starting upload process..."
    
    # Upload APK
    if [ "$BUILD_ANDROID" = true ]; then
        APK_PATH="$FLUTTER_PROJECT_PATH/build/app/outputs/flutter-apk/app-release.apk"
        if [ -f "$APK_PATH" ]; then
            echo "Uploading APK to Pgyer..."
            cd "$FLUTTER_PROJECT_PATH/shell" || { echo "Directory not found: $FLUTTER_PROJECT_PATH/shell"; exit 1; }
            sh upload_to_pgyer.sh -k "$PGYER_API_KEY" "$APK_PATH"
        else
            echo "Warning: APK file not found: $APK_PATH"
        fi
    fi

    # Upload IPA
    if [ "$BUILD_IOS" = true ]; then
        IPA_PATH=$(ls $FLUTTER_PROJECT_PATH/build/ios/ipa/*.ipa | head -1)
        if [ -f $IPA_PATH ]; then
            echo "Uploading IPA to Pgyer..."
            cd "$FLUTTER_PROJECT_PATH/shell" || { echo "Directory not found: $FLUTTER_PROJECT_PATH/shell"; exit 1; }
            sh upload_to_pgyer.sh -k "$PGYER_API_KEY" "$IPA_PATH"
        else
            echo "Warning: IPA file not found: $IPA_PATH"
        fi
    fi

    echo "Upload completed"
}

# ========== Argument Parsing ==========

# Default values
BUILD_ANDROID=true
BUILD_IOS=true
UPLOAD_ONLY=false
VERSION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --android)
            BUILD_ANDROID=true
            BUILD_IOS=false
            shift
            ;;
        --ios)
            BUILD_IOS=true
            BUILD_ANDROID=false
            shift
            ;;
        --upload-only)
            UPLOAD_ONLY=true
            shift
            ;;
        --version)
            echo "gen_release.sh version 1.0.0"
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1"
            show_help
            exit 1
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# If only upload is requested
if [ "$UPLOAD_ONLY" = true ]; then
    upload_builds
    exit 0
fi

# ========== Version Handling ==========

echo "Processing version..."

# Change to Core directory
cd "$CORE_PATH" || { echo "Core directory not found: $CORE_PATH"; exit 1; }

INPUT_REF="$VERSION"

# Get latest tag if version/branch not specified
if [ -z "$INPUT_REF" ]; then
    echo "No version specified, using latest tag (including alpha/beta/rc)..."
    INPUT_REF=$(git tag --sort=-v:refname | head -n 1)
    if [ -z "$INPUT_REF" ]; then
        echo "Error: No version tags found and no version specified"
        exit 1
    fi
    echo "Using latest version (including pre-releases): $INPUT_REF"
fi

git fetch --all --tags -f

# Detect if the input is a branch
IS_BRANCH=false
if git show-ref --verify --quiet "refs/heads/$INPUT_REF" || git ls-remote --heads origin "$INPUT_REF" | grep -q "$INPUT_REF"; then
    IS_BRANCH=true
fi

if [ "$IS_BRANCH" = true ]; then
    echo "Detected branch input. Checking out latest branch: $INPUT_REF"
    git checkout "$INPUT_REF" 2>/dev/null || git checkout -b "$INPUT_REF" "origin/$INPUT_REF"
    git pull origin "$INPUT_REF"
else
    # Validate version format (including alpha/beta/rc and other pre-release versions)
    if ! echo "$INPUT_REF" | grep -qE '^[v]?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)*$|^alpha|^beta|^rc'; then
        echo "Error: Invalid version format '$INPUT_REF'. Examples: v1.2.3, 1.2.3-patch, 1.2.3-alpha.1, alpha1.2.3"
        exit 1
    fi
    echo "Checking out version tag: $INPUT_REF"
    git checkout "$INPUT_REF" -f
fi

git submodule update --init --recursive

# Extract version number (remove 'v' prefix if present). For branch builds, reuse the current SDK version.
if [ "$IS_BRANCH" = true ]; then
    echo "Branch build detected. Reusing existing SDK version from flutter_openim_sdk."
    VERSION_NUMBER=$(grep '^version:' "$FLUTTER_PROJECT_PATH/flutter_openim_sdk/pubspec.yaml" | cut -d ' ' -f 2)
    if [ -z "$VERSION_NUMBER" ]; then
        VERSION_NUMBER="1.0.0"
    fi
else
    VERSION_NUMBER=$(echo "$INPUT_REF" | sed 's/^v//')
fi

echo "Version number: $VERSION_NUMBER"

# ========== Update SDK Version ==========

echo "Updating SDK version..."

# ========== Check if SDK needs to be built ==========

# Get current flutter_openim_sdk version
FLUTTER_SDK_PUBSPEC="$FLUTTER_PROJECT_PATH/flutter_openim_sdk/pubspec.yaml"
if [ "$IS_BRANCH" = true ]; then
    echo "Branch build detected, forcing SDK build even if versions match."
    BUILD_SDK=true
elif [ -f "$FLUTTER_SDK_PUBSPEC" ]; then
    CURRENT_SDK_VERSION=$(grep '^version:' "$FLUTTER_SDK_PUBSPEC" | cut -d ' ' -f 2)
    echo "Current flutter_openim_sdk version: $CURRENT_SDK_VERSION"
    echo "Requested version: $VERSION_NUMBER"
    
    if [ "$CURRENT_SDK_VERSION" = "$VERSION_NUMBER" ]; then
        echo "flutter_openim_sdk version matches the requested version. Skipping SDK build."
        BUILD_SDK=false
    else
        echo "flutter_openim_sdk version does not match. Proceeding with SDK build."
        BUILD_SDK=true
    fi
else
    echo "flutter_openim_sdk pubspec.yaml not found. Proceeding with SDK build."
    BUILD_SDK=true
fi

# ========== Build SDK ==========

if [ "$BUILD_SDK" = true ] && ([ "$BUILD_ANDROID" = true ] || [ "$BUILD_IOS" = true ]); then
    echo "Building SDK..."
    # Ensure we're in the core directory
    cd "$CORE_PATH" || { echo "Core directory not found: $CORE_PATH"; exit 1; }

    # Remove existing protocol directory if it exists
    if [ -d "pkg/protocol" ]; then
        echo "Removing existing protocol directory..."
        rm -rf pkg/protocol
    fi

    # Add and initialize protocol submodule
    echo "Adding protocol submodule..."
    git submodule add --force https://github.com/openimsdk/protocol-enterprise.git pkg/protocol 2>/dev/null || true
    git submodule update --init --recursive

    # Reset and clean
    echo "Resetting repository and updating dependencies..."
    git reset --hard
    go mod tidy

    # Build both iOS and Android SDKs
    echo "Building iOS and Android SDKs..."
    
    # Build iOS framework
    echo "Building iOS framework..."
    make ios || { echo "iOS build failed"; exit 1; }
    
    # Build Android library
    echo "Building Android library..."
    make android || { echo "Android build failed"; exit 1; }

    # Copy generated files
    echo "Copying generated files..."
    
    # Copy iOS framework
    if [ "$BUILD_IOS" = true ]; then
        echo "Copying iOS framework..."
        mkdir -p "$FLUTTER_PROJECT_PATH/flutter_openim_sdk/ios/Framework/"
        cp -f -R ./build/*.xcframework "$FLUTTER_PROJECT_PATH/flutter_openim_sdk/ios/Framework/" || { 
            echo "Failed to copy xcframework"; 
            exit 1; 
        }
    fi
    
    # Copy Android AAR
    if [ "$BUILD_ANDROID" = true ]; then
        echo "Copying Android AAR..."
        # Create target directory with fixed version 0.0.1
        TARGET_AAR_DIR="$FLUTTER_PROJECT_PATH/flutter_openim_sdk/android/libs/io/openim/core-sdk/0.0.1"
        mkdir -p "$TARGET_AAR_DIR"
        
        # Find and copy the first aar file to the target directory with new name
        AAR_FILE=$(find . -name "*.aar" | head -1)
        if [ -n "$AAR_FILE" ]; then
            cp -f "$AAR_FILE" "$TARGET_AAR_DIR/core-sdk-0.0.1.aar" || {
                echo "Failed to copy aar to $TARGET_AAR_DIR";
                exit 1;
            }
            echo "Successfully copied AAR to $TARGET_AAR_DIR/core-sdk-0.0.1.aar"
        else
            echo "Error: No AAR file found in $CORE_PATH"
            exit 1
        fi
    fi
fi

# Update SDK version in openim.dart & pubspec.yaml (skip when building from branch)
if [ "$IS_BRANCH" != true ]; then
    SDK_DART_FILE="$FLUTTER_PROJECT_PATH/flutter_openim_sdk/lib/src/openim.dart"
    if [ -f "$SDK_DART_FILE" ]; then
        sed -i.bak "s/static const version = '[^']*';/static const version = '$VERSION_NUMBER';/" "$SDK_DART_FILE"
        rm -f "${SDK_DART_FILE}.bak"
    fi

    SDK_PUBSPEC="$FLUTTER_PROJECT_PATH/flutter_openim_sdk/pubspec.yaml"
    if [ -f "$SDK_PUBSPEC" ]; then
        sed -i.bak "s/^version: .*/version: $VERSION_NUMBER/" "$SDK_PUBSPEC"
        rm -f "${SDK_PUBSPEC}.bak"
    fi
else
    echo "Branch build detected, skipping flutter_openim_sdk version file updates."
fi

# ========== Update Flutter Project ==========

cd "$FLUTTER_PROJECT_PATH" || { echo "Flutter project directory not found"; exit 1; }

# Update push controller
PUSH_CONTROLLER_FILE="./openim_common/lib/src/controller/push_controller.dart"
if [ -f "$PUSH_CONTROLLER_FILE" ]; then
    echo "Updating push controller configuration..."
    sed -i.bak "s/const appID = '[^']*';/const appID = '$GETUI_APPID';/" "$PUSH_CONTROLLER_FILE"
    sed -i.bak "s/const appKey = '[^']*';/const appKey = '$GETUI_APPKEY';/" "$PUSH_CONTROLLER_FILE"
    sed -i.bak "s/const appSecret = '[^']*';/const appSecret = '$GETUI_APPSECRET';/" "$PUSH_CONTROLLER_FILE"
    perl -i -pe "s/PushType pushType *= *PushType\.[a-zA-Z0-9_]+/PushType pushType = PushType.${PUSH_MODEL}/" "$PUSH_CONTROLLER_FILE"
    rm -f "${PUSH_CONTROLLER_FILE}.bak"
fi

# Update Android project
if [ "$BUILD_ANDROID" = true ]; then
    echo "Updating Android project..."
    ANDROID_PROJECT_PATH="./android/app"
    
    # Update build.gradle
    GRADLE_FILE="$ANDROID_PROJECT_PATH/build.gradle"
    if [ -f "$GRADLE_FILE" ]; then
        sed -i.bak "s/applicationId \".*\"/applicationId \"$ANDROID_APP_ID\"/" "$GRADLE_FILE"
        sed -i.bak "s/GETUI_APPID    : \"[^\"]*\"/GETUI_APPID    : \"$GETUI_APPID\"/" "$GRADLE_FILE"
        sed -i.bak "s/HUAWEI_APP_ID  : \"[^\"]*\"/HUAWEI_APP_ID  : \"$HUAWEI_APP_ID\"/" "$GRADLE_FILE"
        rm -f "${GRADLE_FILE}.bak"
    fi
    
    # Update AndroidManifest.xml
    MANIFEST_FILE="$ANDROID_PROJECT_PATH/src/main/AndroidManifest.xml"
    if [ -f "$MANIFEST_FILE" ]; then
        sed -i.bak "s/android:label=\"[^\"]*\"/android:label=\"$APP_NAME\"/" "$MANIFEST_FILE"
        rm -f "${MANIFEST_FILE}.bak"
    fi
    
    # Update google-services.json if it exists
    GOOGLE_JSON_FILE="$ANDROID_PROJECT_PATH/google-services.json"
    if [ -f "$GOOGLE_JSON_FILE" ]; then
        sed -i.bak "s/\"package_name\": \"[^\"]*\"/\"package_name\": \"$ANDROID_APP_ID\"/" "$GOOGLE_JSON_FILE"
        rm -f "${GOOGLE_JSON_FILE}.bak"
    fi
    
    echo "Android project updated:"
    echo "  - Application ID: $ANDROID_APP_ID"
    echo "  - App Name: $APP_NAME"
fi

# Update iOS project
if [ "$BUILD_IOS" = true ]; then
    echo "Updating iOS project..."
    IOS_PROJECT_PATH="./ios"
    EXTENSIONS=("NotificationService" "ScreenShareBroadcastExtension")
    
    cd "$FLUTTER_PROJECT_PATH/shell" || { echo "Directory not found: $FLUTTER_PROJECT_PATH/shell"; exit 1; }
    
    if [ -f "update_bundle_identifier.rb" ]; then
        ruby update_bundle_identifier.rb "$IOS_BUNDLE_IDENTIFIER" "$FLUTTER_PROJECT_PATH" "$APP_NAME" "${EXTENSIONS[@]}"
        echo "iOS Bundle Identifier updated to: $IOS_BUNDLE_IDENTIFIER"
    else
        echo "Warning: update_bundle_identifier.rb not found, skipping iOS bundle identifier update"
    fi
fi

# Update API configuration
cd "$FLUTTER_PROJECT_PATH" || { echo "Failed to change to project directory"; exit 1; }

API_DART_FILE="./openim_common/lib/src/apis.dart"
if [ -f "$API_DART_FILE" ]; then
    echo "Updating API configuration..."
    sed -i.bak "s/'appKey': '[^']*'/'appKey': '$PGYER_APP_KEY'/" "$API_DART_FILE"
    rm -f "${API_DART_FILE}.bak"
fi

CONFIG_DART_FILE="./openim_common/lib/src/config.dart"
if [ -f "$CONFIG_DART_FILE" ]; then
    sed -i.bak "s/static const _host = \"[^\"]*\";/static const _host = \"$HOST\";/" "$CONFIG_DART_FILE"
    rm -f "${CONFIG_DART_FILE}.bak"
fi

# Update app version
PROJECT_PUBSPEC_FILE="$FLUTTER_PROJECT_PATH/pubspec.yaml"
if [ -f "$PROJECT_PUBSPEC_FILE" ]; then
    echo "Updating app version..."
    CURRENT_VERSION=$(grep '^version:' "$PROJECT_PUBSPEC_FILE" | cut -d ' ' -f 2)
    
    # Extract base version (e.g., 3.8.4 from 3.8.4-alpha.4-e-v1.1.11+234)
    if [[ "$CURRENT_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        BASE_VERSION="${BASH_REMATCH[1]}"
    else
        # Fallback to the version from VERSION_NUMBER if pattern doesn't match
        if [[ "$VERSION_NUMBER" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            BASE_VERSION="${BASH_REMATCH[1]}"
        else
            BASE_VERSION="1.0.0"  # Fallback version
        fi
    fi
    
    # Increment build number
    if [[ "$CURRENT_VERSION" =~ \+([0-9]+)$ ]]; then
        BUILD_NUMBER=$((BASH_REMATCH[1]))
    else
        BUILD_NUMBER=1
    fi
    
    # Create new version string (e.g., 3.8.4+234)
    NEW_VERSION="${BASE_VERSION}+${BUILD_NUMBER}"
    
    # Update pubspec.yaml
    sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$PROJECT_PUBSPEC_FILE"
    rm -f "${PROJECT_PUBSPEC_FILE}.bak"
    
    echo "App version updated to: $NEW_VERSION"
fi

# ========== Clean and Get Dependencies ==========

echo "Cleaning and getting Flutter dependencies..."
flutter clean
flutter pub get

# ========== Build Android ==========

if [ "$BUILD_ANDROID" = true ]; then
    echo "Building Flutter APK..."
    if flutter build apk --release; then
        echo "Flutter APK build succeeded"
        APK_PATH="$FLUTTER_PROJECT_PATH/build/app/outputs/flutter-apk/app-release.apk"
        echo "APK location: $APK_PATH"
    else
        echo "Flutter APK build failed"
        exit 1
    fi
fi

# ========== Build iOS ==========

if [ "$BUILD_IOS" = true ]; then
    echo "Building Flutter IPA..."
    cd ios || { echo "iOS directory not found"; exit 1; }
    
    # Clean up iOS build files
    echo "Cleaning iOS build files..."
    rm -f Podfile.lock
    rm -rf Pods
    
    # Install pods
    echo "Installing Pods..."
    pod repo update || { echo "Pod repo update failed"; exit 1; }
    pod update || { echo "Pod installation failed"; exit 1; }
    
    # Build IPA
    echo "Building IPA..."
    if flutter build ipa --release --export-method=ad-hoc; then
        echo "Flutter IPA build succeeded"
        IPA_PATH=$(ls $FLUTTER_PROJECT_PATH/build/ios/ipa/*.ipa | head -1)
        echo "IPA location: $(ls -1 $IPA_PATH | head -1)"
    else
        echo "Flutter IPA build failed"
        exit 1
    fi
fi

# ========== Upload Builds ==========

if [ "$UPLOAD_ONLY" = false ]; then
    echo "Uploading builds to Pgyer..."
    upload_builds
fi

# Clean up backup files
cleanup_backups

echo "Build process completed successfully!"
