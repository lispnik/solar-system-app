# Getting this into TestFlight

TestFlight installs the app on real phones -- yours and anyone else's you
invite -- without the App Store. Apple wants three things before it will take
a build: an identity to sign it with, a record to attach it to, and a key to
upload it under. All three are made once, in a browser; after that every
build is one command.

There is no Xcode project here, so nothing is created for you behind the
scenes. What follows is that scenery, by hand.

## Once: the identity

You need an **Apple Developer Program** membership ($99 a year). The
`Developer ID Application` certificate already in this keychain means the
account is a paid one.

1. **Register the App ID.**
   [developer.apple.com › Certificates, Identifiers & Profiles ›
   Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   › **+** › App IDs › App. Description `Solar System`, Bundle ID
   **explicit**, `com.burnsidemk.solarsystem`. No capabilities: Core Location
   and Core Motion need none.

   An explicit ID, not a wildcard -- App Store Connect will not offer a
   wildcard when you create the app.

2. **Make an Apple Distribution certificate.** The quickest way is Xcode,
   which is installed: Xcode › Settings › Accounts › your Apple ID › your
   team › **Manage Certificates** › **+** › Apple Distribution. It lands in
   the keychain; `security find-identity -v -p codesigning` then lists

   ```
   Apple Distribution: Matthew Kennedy (Q47YS469F2)
   ```

   which is the string `IOS_SIGNING_IDENTITY` wants. (The portal will do the
   same from a certificate signing request made in Keychain Access, if you
   would rather not open Xcode.)

3. **Make an App Store provisioning profile.**
   [Profiles](https://developer.apple.com/account/resources/profiles/list) ›
   **+** › Distribution › **App Store Connect** › App ID
   `com.burnsidemk.solarsystem` › the distribution certificate from step 2 ›
   name it `Solar System App Store` › Generate › Download. Keep it anywhere;
   `IOS_PROVISIONING_PROFILE` is its path.

   This profile is what grants `beta-reports-active`, the entitlement that
   lets a build be tested in TestFlight. The build carries it through from
   the profile, and drops `get-task-allow`, which a distribution build may
   not have.

## Once: the record and the key

4. **Create the app in App Store Connect.**
   [appstoreconnect.apple.com › Apps](https://appstoreconnect.apple.com/apps)
   › **+** › New App. iOS; name **Where the Planets Are**; primary language;
   bundle ID `com.burnsidemk.solarsystem` from the list; SKU anything, say
   `solar-system`; Full Access.

   The subtitle, **The real sky, any date**, is not in that dialogue -- set
   it afterwards under App Information (30 characters, like the name).

   The store name and the name under the icon are separate, and differ on
   purpose: `CFBundleDisplayName` stays `Solar System`, because "Where the
   Planets Are" truncates to "Where the Pl…" on a home screen.

5. **Make an App Store Connect API key.** Users and Access › Integrations ›
   App Store Connect API › **+**. Name it `Upload`, access **App Manager**,
   and download the `.p8` -- it is offered exactly once.

   ```
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_*.p8 ~/.appstoreconnect/private_keys/
   ```

   Note the **Key ID** beside it and the **Issuer ID** above the list.

## Every build

```
export ECL_IOS_PREFIX=~/Projects/ecl/ecl-iOS/ \
       ECL_HOST=~/Projects/ecl/ecl-native/bin/ecl
export IOS_SIGNING_IDENTITY="Apple Distribution: Matthew Kennedy (Q47YS469F2)" \
       IOS_DEVELOPMENT_TEAM=Q47YS469F2 \
       IOS_PROVISIONING_PROFILE=~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/Solar_System_App_Store.mobileprovision
export ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

tools/testflight.sh                 # build, validate, upload
tools/testflight.sh --validate      # everything but the upload
tools/testflight.sh --build 1.0.20  # a build number of your own
```

The script builds for the device alone (`SOLAR_DISTRIBUTION=1`), numbers the
build `1.0.<commits>` so it never goes backwards and says which commit a
tester is holding, packages the bundle as an `.ipa`, and hands it to
`altool`. Before it uploads anything it checks the signature for
`get-task-allow`, which App Store Connect refuses, looks for the
`beta-reports-active` the profile should have granted, and refuses a build
with slynk linked into it -- the remote REPL is unauthenticated and must
never ship.

`CFBundleShortVersionString` stays `1.0` across builds; raise it in
`solar-system.asd` when the app itself changes version.

## Screenshots

`doc/store/` holds the eight App Store screenshots in both sizes App Store
Connect takes:

- `6.9-inch/` -- 1320 x 2868, from an iPhone 17 Pro Max simulator.
- `6.5-inch/` -- 1284 x 2778, from an iPhone 14 Plus simulator.

Upload them in order; the first three are what people see in search.

They are made in two steps. `tools/store-scenes.lisp` stages each moment in
a running app (built with `SOLAR_REPL=1`) and `xcrun simctl io <device>
screenshot` takes the picture; then

```
swift tools/make-store-shots.swift <raw-directory> doc/store/6.5-inch
```

puts each one under its caption from `doc/store/captions.txt`, at whatever
size the screenshots are -- the layout scales with them.

A simulator of a given size, if there is none:

```
xcrun simctl create "Solar 6.5" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

## Then, in App Store Connect

Processing takes a few minutes, after which the build appears under
**TestFlight**.

- **Internal testers** -- up to 100 people on your own team -- can install it
  at once, with no review. Add yourself, and TestFlight on the phone offers
  the build.
- **External testers** -- up to 10,000 by email or a public link -- need
  Beta App Review first, which is quick and looser than App Store review.
  Fill in **Test Information**: what to test, a feedback email, and a
  privacy policy URL. There is no account to demo.
- App Store Connect asks for **App Privacy** before external testing:
  everything is "Data Not Collected". The app makes no network requests at
  all, and `res/PrivacyInfo.xcprivacy` says so; the only API it declares is
  `NSUserDefaults`, for remembering where you left it.
- Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is
  `false` in the plist, so no question is asked on each upload.
- Location is asked for only when you press the location button, and the
  reason string says why.

A build expires 90 days after upload.

## If the upload is refused

- *"Invalid Code Signing Entitlements"* -- the profile and the bundle
  identifier disagree. The build refuses this before signing, so it usually
  means the profile is a development one.
- *"The provisioning profile ... does not include the beta-reports-active
  entitlement"* -- the profile is an Ad Hoc or Development one. Make an App
  Store one (step 3).
- *"The bundle version must be higher than the previously uploaded version"*
  -- commit, or pass `--build`.
- *"Missing Info.plist value ... CFBundleIconName"* -- `actool` did not run;
  build from a clean `build/iphoneos`, which the script does.
