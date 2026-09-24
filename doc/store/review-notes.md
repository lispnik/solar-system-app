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

Record on the phone, portrait unless noted, one take, about 90 seconds.
Either iOS Screen Recording (Settings > Control Centre > Screen Recording)
or QuickTime on the Mac (File > New Movie Recording, then choose the iPhone
as the camera) -- QuickTime also catches the phone being tilted.

1. Start on the Home Screen. Tap the app's icon, so the recording begins
   with the launch.
2. The solar system appears at today's date, running in real time. Drag to
   tilt it; pinch to zoom.
3. Tap Saturn. It is followed, its moons come into view, and the card under
   the clock fills with its distances, speed, size and next event.
4. Tap the speed control: 1mo, so a month passes each second and the planets
   visibly move. Then 1x again.
5. Tap the right-hand arrow at the bottom two or three times to step through
   events, stopping on an eclipse.
6. Tap the globe button for the view from the Earth. Pinch in on Jupiter
   until its four moons show beside it.
7. Tap the location button. Allow the permission when iOS asks. The horizon
   and compass points appear.
8. Hold the phone up and turn slowly left and right, so the view turns with
   it. Turn the phone sideways too, to show it working in landscape.
9. Tap the ruler button to ease out to true distances, then again to come
   back.
10. Tap the clock at the top to show the credits, then tap to close.

If the file is too large for Resolution Center, upload it somewhere
unlisted and put the link in the reply instead.
