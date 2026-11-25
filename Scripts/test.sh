#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Run crate's tests in the Simulator, as the test workflow does: the unit tests
# (Tests/CrateTests), which run inside the app, and the UI tests
# (Tests/CrateUITests), which drive it.
#
#     ./Scripts/test.sh [DEVICE]     # a Simulator's name or UDID; default, the first iPhone there is
#
# More arguments go to xcodebuild, to run some of the tests:
#
#     ./Scripts/test.sh "iPhone 17" -only-testing:CrateTests/SeedDiskTests
#
# Needs Frameworks/ (Scripts/fetch-frameworks.sh and fetch-crate.sh) and XcodeGen.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

DEVICE="${1:-}"
[ $# -gt 0 ] && shift
if [ -z "$DEVICE" ]; then
    DEVICE="$(xcrun simctl list devices available |
        sed -n 's/^ *iPhone[^(]*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)"
    [ -n "$DEVICE" ] || { echo "no iPhone Simulator is installed" >&2; exit 1; }
fi
if [[ "$DEVICE" =~ ^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$ ]]; then
    DESTINATION="platform=iOS Simulator,id=$DEVICE"
else
    DESTINATION="platform=iOS Simulator,name=$DEVICE"
fi

xcodegen generate --quiet
xcodebuild test -quiet -project Crate.xcodeproj -scheme Crate \
    -destination "$DESTINATION" -derivedDataPath build/test "$@"
