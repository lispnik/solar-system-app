#!/bin/bash
#
# testflight.sh -- build the app for the App Store, package it and upload it.
#
#     tools/testflight.sh                 # build, validate, upload
#     tools/testflight.sh --validate      # build and validate, upload nothing
#     tools/testflight.sh --build 1.0.7   # a build number of your own
#
# doc/testflight.md says where the certificate, the profile and the API key
# come from. Nothing here is secret: every identity is read from the
# environment.

set -euo pipefail
cd "$(dirname "$0")/.."

upload=yes
build=""
while [ $# -gt 0 ]; do
  case "$1" in
    --validate) upload=no ;;
    --build) build="$2"; shift ;;
    *) echo "usage: $0 [--validate] [--build N.N.N]" >&2; exit 2 ;;
  esac
  shift
done

missing=""
need () { eval "[ -n \"\${$1:-}\" ]" || missing="$missing  $1 -- $2\n"; }
need ECL_HOST            "the host ECL that cross-compiles"
need ECL_IOS_PREFIX      "the iOS (device) ECL prefix"
need IOS_SIGNING_IDENTITY "an Apple Distribution identity, in the keychain"
need IOS_DEVELOPMENT_TEAM "the ten-character team id"
need IOS_PROVISIONING_PROFILE "an App Store profile for this app"
if [ "$upload" = yes ]; then
  need ASC_KEY_ID   "the App Store Connect API key id"
  need ASC_ISSUER_ID "the issuer id the key was made under"
fi
if [ -n "$missing" ]; then
  printf "Not set:\n$missing" >&2
  exit 1
fi

case "$IOS_SIGNING_IDENTITY" in
  "Apple Distribution"*|"iPhone Distribution"*) ;;
  *) echo "IOS_SIGNING_IDENTITY is '$IOS_SIGNING_IDENTITY'. The App Store takes" >&2
     echo "only an Apple Distribution identity; a development one uploads and" >&2
     echo "is then rejected." >&2
     exit 1 ;;
esac

# The build number every upload must raise. One per commit, which never goes
# backwards and says which commit a tester is holding.
[ -n "$build" ] || build="1.0.$(git rev-list --count HEAD)"

# A shipped build has no REPL in it: the server is unauthenticated, and
# anyone who reaches the port gets EVAL.
unset SOLAR_REPL
export SOLAR_DISTRIBUTION=1 SOLAR_BUILD="$build"

echo "== building $build, device only, signed by $IOS_SIGNING_IDENTITY"
rm -rf build/iphoneos
"$ECL_HOST" --eval '(require :asdf)' \
            --eval '(asdf:make "solar-system")' \
            --eval '(ext:quit)'

app=build/iphoneos/Solar.app
[ -d "$app" ] || { echo "no $app" >&2; exit 1; }

echo "== checking what was built"
plutil -p "$app/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleVersion|CFBundleShortVersionString'
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - || true)
echo "$entitlements"
if echo "$entitlements" | grep -q 'get-task-allow.*1'; then
  echo "get-task-allow is in the signature; App Store Connect refuses that." >&2
  exit 1
fi
if ! echo "$entitlements" | grep -q 'beta-reports-active'; then
  echo "note: the profile does not grant beta-reports-active, so this build" >&2
  echo "cannot be tested in TestFlight. Is it an App Store profile?" >&2
fi
if nm -gU "$app/solar" 2>/dev/null | grep -qi slynk; then
  echo "slynk is linked into this build. Build without SOLAR_REPL." >&2
  exit 1
fi

echo "== packaging"
"$ECL_HOST" --eval '(require :asdf)' \
            --eval '(asdf:load-system "asdf-ios-app")' \
            --eval "(asdf-ios-app:export-ipa #p\"$PWD/$app/\" :output #p\"$PWD/build/Solar.ipa\")" \
            --eval '(ext:quit)'
ipa=build/Solar.ipa
ls -lh "$ipa"

# altool reads the .p8 from ~/.appstoreconnect/private_keys by key id.
echo "== validating with App Store Connect"
xcrun altool --validate-app -f "$ipa" -t ios \
             --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [ "$upload" = no ]; then
  echo "== validated; not uploading ($ipa is ready)"
  exit 0
fi

echo "== uploading"
xcrun altool --upload-app -f "$ipa" -t ios \
             --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded build $build. App Store Connect takes a few minutes to process"
echo "it; it then appears under TestFlight, and internal testers can install"
echo "it straight away."
