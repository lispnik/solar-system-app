# App Review information

What App Review asked for under Guideline 2.1 on the first submission, and
the answers. Paste 1-6 into the Resolution Center reply *and* into the Notes
field of App Review Information, where they will stand for later
submissions. The screen recording has to be made on a phone: the shot list
is at the end.

---

**What the app is.** Where the Planets Are is an orrery: it draws the Sun,
the eight planets, five dwarf planets, twenty-one moons, nine comets and
8,825 asteroids in the positions they really occupy, at any date between
3000 BC and 3000 AD. Every position is computed on the device from
astronomical tables built into the app. There is no account, no purchase,
no advertising, no user-generated content, and the app makes no network
requests of any kind.

**1. Screen recording.** Attached (see the shot list below). It is recorded
on a physical iPhone running the current version of iOS, begins with the app
being launched from the Home Screen, and shows the typical flow through
every main feature. The app has no account registration, login or deletion,
no user-generated content, and no paid content or features, so none of the
listed flows apply.

**2. Purpose and audience.** The app answers "where is Saturn right now, and
what does the solar system look like from here today?" It is for anyone
curious about the sky: amateur astronomers deciding what is worth looking at
tonight, teachers and students who want to see why Mars appears to go
backwards or why an eclipse falls where it does, and general readers who
like knowing what is overhead. The value is that everything shown is real
rather than illustrative: positions are computed from JPL's published
elements and agree with JPL Horizons to a tenth of a degree, so the app can
be pointed at the sky and believed.

**3. Setting up and reaching the features.** Nothing to set up: no account,
no login, no credentials, no sample files. Open the app and it draws the
solar system as it is at this moment. Drag to turn the view, pinch to zoom,
tap a body to follow it and see its facts. Along the bottom: the play and
speed controls run time from real time up to a year a second; the arrows
step to the next or previous event (eclipses, transits, oppositions,
conjunctions); the row of buttons turns on name labels, trails, comets and
asteroids, the view from the Earth, and true distances. In the view from
the Earth, the location button (a compass arrow) asks for location
permission -- optional; declining leaves every other feature working -- and
then draws the horizon and compass so the phone can be held up to the sky.
Tapping the clock at the top shows the credits.

**4. External services, tools and platforms.** None. The app makes no
network connections at all: no data provider, no authentication, no payment
processor, no analytics, no advertising, no AI service, no third-party SDK.
Its astronomical data is static, compiled into the app when it is built,
from published sources: E. M. Standish's planetary elements (JPL), elements
fitted to JPL Horizons for moons, dwarf planets and comets, and JPL's
Small-Body Database for the asteroid belt. From iOS it uses Metal and
MetalKit to draw, Core Location for the optional "where am I" feature, and
Core Motion to know which way the phone is pointing. Nothing is collected
and nothing leaves the device; the privacy policy is at
https://lispnik.github.io/solar-system-app/privacy.html

**5. Regional differences.** None. The app behaves identically everywhere
and is not gated, priced or restricted by region. The only thing that
varies with place is astronomical: the view from the Earth depends on where
the phone is, because the sky does. The interface is English only, and
dates and times are shown in UTC.

**6. Regulated industry and third-party material.** The app is not in a
regulated industry. Its third-party material is licensed and credited in
the app itself, on the credits screen reached by tapping the clock:

- Planet, moon and ring textures: Solar System Scope
  (https://www.solarsystemscope.com/textures/), licensed CC BY 4.0
  (https://creativecommons.org/licenses/by/4.0/), which permits commercial
  use with attribution. Attribution is given in the app and in the
  repository.
- Astronomical data: JPL and NASA publications (Standish's "Approximate
  Positions of the Planets", JPL Horizons, JPL Small-Body Database), which
  are US Government works in the public domain, and Jean Meeus's published
  lunar series, used as a formula rather than as copied data.

The app itself is open source, so the reviewer can see exactly what it does:
https://github.com/lispnik/solar-system-app

---

## The screen recording

About a minute and three-quarters, one take, on the phone. The reviewer
wants to see the app launched and used; they do not need narration, and a
silent recording is fine. Captions can be added afterwards if you like --
the line to show is given for each beat.

### Before pressing record

- Install **1.0.26** from TestFlight, and open it once to be sure it is the
  build with the store name under the icon.
- In the app: double-tap the background to put the view back to straight
  above, then press **Now**, then close the app. It remembers where it was
  left, and this makes the recording start from the obvious place.
- Settings > Apps > Where the Planets Are > Location > **Ask Next Time**,
  so the permission prompt appears in the recording with its reason on it.
- Turn on Do Not Disturb, and turn portrait orientation lock **off** --
  landscape is one of the beats.
- Start the recording from the Home Screen, with the icon in shot, using
  iOS Screen Recording or QuickTime on the Mac (File > New Movie Recording,
  then the iPhone as camera; that one also catches the phone being tilted).

### The beats

| Time | Do this | It shows | Caption, if captioning |
|---|---|---|---|
| 0:00 | Home Screen, tap the icon | the app launching, nothing before it | |
| 0:05 | Let it stand still for three seconds | the solar system at today's date, the clock reading real time | Everything where it is, right now |
| 0:10 | Drag slowly to tilt, then pinch to zoom in and out | a real 3D scene, not a picture | |
| 0:22 | Tap **Saturn**, wait for it to settle | following a planet: its moons, its rings, and the card of facts | Tap anything to follow it |
| 0:30 | Let the card stand four seconds | distance, speed, size, next event | |
| 0:34 | Tap **1mo**, watch six seconds, tap **1x**, then **Now** | time running a month a second, then back to the present | Run time at a month a second |
| 0:44 | Tap **›** twice, stopping on an eclipse | the event search: eclipses, transits, oppositions | Step to the next eclipse |
| 0:54 | Tap the **globe** | the view from the Earth's surface | Or stand on the Earth and look up |
| 1:00 | Pinch in on **Jupiter** until the moons show | 0.03° of sky: a disc with four moons beside it | |
| 1:08 | Tap the **location arrow**, then Allow When Using | the permission and its reason, then the horizon and compass | It can use where you are |
| 1:16 | Raise the phone; turn slowly left to right; tilt up and down | the view turning with the phone: the sky-pointing feature | Hold it up and it turns with you |
| 1:28 | Turn the phone sideways, keep turning slowly | the same in landscape, the panel moving out of the way | |
| 1:36 | Back to portrait, tap the **ruler**, wait, tap again | true distances, and back | |
| 1:42 | Tap the **clock**, let the credits stand four seconds, tap to close | where the numbers and the pictures come from | Whose numbers these are |

Let each thing settle before the next tap: the reviewer is watching at
normal speed, and a hurried recording reads as a broken app. Avoid tapping
empty space, which hides the controls.

If the file is too large for Resolution Center, upload it somewhere
unlisted and put the link in the reply instead.
