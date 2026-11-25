#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Stress the claim of the code region's gap (Sources/Crate/JIT/CodeRegion.c) on
# a Mac, as the test workflow does: Tests/CodeRegion/race.c claims the region
# while other threads map memory, and fails if the claim replaced any of
# theirs. It's a race, which one run can miss, so it's run several times.
#
#     ./Scripts/test-code-region.sh [RUNS]     # default 5, of 300 claims each
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="${1:-5}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# DEBUG for CodeRegion.c's CRATE_TEST_HIGH_REGION hook: see race.c.
clang -Wall -DDEBUG=1 -O1 -I "$REPO/Sources/Crate/JIT" \
    "$REPO/Tests/CodeRegion/race.c" "$REPO/Sources/Crate/JIT/CodeRegion.c" -o "$WORK/race"
for _ in $(seq 1 "$RUNS"); do
    "$WORK/race" 300
done
echo "code region: $RUNS runs, nothing replaced"
