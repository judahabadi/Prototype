#!/bin/sh

# Xcode Cloud: give every build a unique, increasing build number.
#
# CURRENT_PROJECT_VERSION is hardcoded to 1 in the project and the targets use a
# generated Info.plist (GENERATE_INFOPLIST_FILE = YES), so CFBundleVersion is
# derived from CURRENT_PROJECT_VERSION. Without bumping it, every Xcode Cloud
# build has the same build number (1); App Store Connect rejects the duplicate
# upload, so new builds never reach TestFlight and the installed app/keyboard
# never updates on device.
#
# CI_BUILD_NUMBER is the monotonically-increasing number Xcode Cloud assigns to
# each build. Stamp it into every target's CURRENT_PROJECT_VERSION so each
# TestFlight build is unique and installs as a real update.

set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "ci_post_clone: CI_BUILD_NUMBER not set; leaving build number unchanged."
    exit 0
fi

PBXPROJ="$CI_PRIMARY_REPOSITORY_PATH/ProtoType/ProtoType/ProtoType.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "ci_post_clone: project.pbxproj not found at $PBXPROJ" >&2
    exit 1
fi

echo "ci_post_clone: setting CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9.]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PBXPROJ"
