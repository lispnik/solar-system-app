# Solar System

The Sun and the eight planets seen from above the ecliptic, where they are
right now, in Common Lisp on iOS. It uses ECL through
[asdf-ios-app](../asdf-ios-app), with UIKit and Metal reached through
[objc](../objc).

- **Positions** come from E. M. Standish's Keplerian elements (JPL): table 1
  inside 1800–2050 and tables 2a/2b outside it, with Kepler's equation solved
  for every planet on every frame. Nothing is integrated, so any date costs the
  same. They are checked against JPL Horizons at five epochs from 1600 to 2400:
  within 0.1° for all but Saturn, which is within 0.15° (a known limit of mean
  elements).
- **Dwarf planets**: Pluto, Ceres, Eris, Haumea and Makemake. JPL
  Horizons' osculating elements are sampled every 10 years from 1600 to 2500,
  and a position is propagated from the samples on either side and blended.
  All are within 0.01° of Horizons except Ceres (0.4°, pulled by Jupiter).
- **Moons**: the Moon comes from Meeus's ELP-2000 series (within 0.01°). Twenty
  more moons of Mars, Jupiter, Saturn, Uranus, Neptune and Pluto use elements
  that `tools/fit-moons.py` fits to Horizons, including the resonance swing of
  Mimas and Tethys. Over 1850–2150 each is within a degree, except Mimas
  (4.6°) and Triton (2.8°).
- **Screen**: each body's direction from the Sun is exact. Distance is
  compressed as r^0.4 (`*radius-exponent*`; 1 is linear) so that Neptune and
  Eris fit on one screen. Each planet's moons are magnified around it on a
  scale of their own, so they fade in as you zoom towards the planet. Disc
  sizes are exaggerated, and each disc is lit on the side facing the Sun.
- **3D**: the scene is a real 3D model (planets' inclinations included), seen
  through a perspective camera. Orbits and discs are drawn in pixels after
  projection, so they stay crisp at any zoom, and each planet shows the phase
  it has from where you are looking.
- **Time** runs at real time by default. It stops at the ends of the
  ephemeris, 3000 BC and 3000 AD.

## Controls

| Gesture | Does |
|---|---|
| one-finger drag | turn the scene about the screen's x and y axes |
| two-finger twist | turn it about the axis out of the screen |
| pinch | zoom |
| two-finger drag | pan |
| tap a body | follow it; for a planet with moons, zoom in until its moons show |
| double tap | back to the view from above the north pole, following nothing |
| tap empty space | hide or show the controls |

The panel at the bottom works like a video player:
- ⏸/▶ plays and pauses.
- The scrubber covers a window of time around the current date; the window
  moves along when the date runs off either end.
- **±10 y** cycles the window's width: 1, 10, 100 or 1000 years each way.
- ⏩/⏪ sets the direction of play.
- The speed selector sets how much simulated time passes per real second:
  real time, an hour, a day, a week, a month or a year.
- **Now** returns to the present in real time.

## Refitting the moons

```
python3 tools/fit-moons.py      # needs numpy; rewrites src/moon-elements.lisp
```

The Horizons states are cached in `tools/moon-states.json`; delete that
file to fetch them again.

## Test the physics (no simulator)

```
sbcl --eval '(asdf:test-system "solar-system-core")' --quit
```

## Build and run

```
export ECL_IOS_PREFIX=~/Projects/ecl/ecl-iOS/ \
       ECL_IOS_SIM_PREFIX=~/Projects/ecl/ecl-iOS-sim/ \
       ECL_HOST=~/Projects/ecl/ecl-native/bin/ecl
$ECL_HOST --eval '(require :asdf)' --eval '(asdf:make "solar-system")' --eval '(ext:quit)'
xcrun simctl install booted build/iphonesimulator/Solar.app
xcrun simctl launch --console-pty booted org.asdf-ios-app.solar-system
```

To start the clock fast, for example at a million times real time (Mercury
laps in about 8 s):

```
xcrun simctl launch booted org.asdf-ios-app.solar-system -SolarTimeScale 1000000
```

Build with `SOLAR_REPL=1` to include slynk on port 4005. Slynk must be on the
source registry. Then, from SLY:

```lisp
(solar-system:set-time-scale 86400)                          ; a day a second
(solar-system:set-sim-date (solar-system:jd-from-calendar 1969 7 20))
(setf solar-system:*radius-exponent* 1d0)                    ; true scale
(solar-system:now)
```

If drawing ever signals an error, the view pauses and the clock label shows
the error. Fix it over the REPL, then call `(solar-system:resume)`.
