# The App Store listing

Everything App Store Connect asks to be typed in, in the fields it asks for.
Apple counts **characters**, not words: the description takes 4,000, the
promotional text 170, the subtitle and name 30 each, keywords 100. The counts
below are what these run to.

## Name (30)

    Where the Planets Are

## Subtitle (30)

    The real sky, any date

## Promotional text (170)

Changeable any time, without a new build — good for the next eclipse.

    Every planet, moon and comet exactly where it is tonight, and on any date
    from 3000 BC to 3000 AD. Hold your phone up to the sky and see what you
    are looking at.

## Keywords (100)

Comma separated, no spaces -- a space costs a character and buys nothing.
Apple indexes the name and subtitle already, so nothing here repeats *where*,
*planets*, *real*, *sky* or *date*, and it builds phrases by combining terms,
so "solar" and "system" cover "solar system" without spending the space.

    orrery,solar,system,astronomy,planetarium,ephemeris,eclipse,stargazing,moon,comet,orbit,space

93 of the 100. The four left out on purpose: *stars*, because there is no star
field and someone searching for one would be disappointed; *telescope*,
because this is not one; *horoscope* and *astrology*, because they are the
highest-volume terms near this app and the wrong audience for it.

## Description (4,000)

Plain text, and the store keeps every line break exactly as it is given, so
each paragraph is one long line -- a hard-wrapped one would come out ragged on
a phone. The shape comes from blank lines and capitals.

---

Tonight, Saturn is somewhere over your shoulder, about nine times as far away as the Sun. This app knows exactly where.

Where the Planets Are is an orrery for your phone: the Sun, eight planets, five dwarf planets, twenty-one moons, nine comets and 8,825 asteroids, each where it really is, at whatever moment you ask for. Nothing here is a loop of animation. Every position is worked out from the tables professional astronomers use, on your phone, as you watch — so tonight costs no more than the morning of the Battle of Hastings, or a Tuesday in the year 2870.

FROM ABOVE

Drag to turn the solar system over, pinch to zoom, tap a planet to follow it. Distances are gently squeezed so that Mercury and Neptune fit on one screen; tap the ruler and everything eases out to true distances, where the inner planets disappear into the Sun's glare and you can see what empty really means.

Come close to a planet and its moons fade in around it, each on its own orbit. Saturn's rings lie in its equator and tilt over the decades exactly as they do, the planet's shadow across them and the rings' shadow banded onto the planet, the Cassini Division letting a stripe of daylight through. Uranus rolls on its side, its ten rings at the radii Voyager 2 measured. Every planet turns the right way at the right speed, lit on the side facing the Sun.

FROM THE EARTH

Press the globe and the view drops to the centre of the Earth and looks out. Planets hang where they really hang, showing the phases they really show. Narrow the view to a thirtieth of a degree and Jupiter becomes a banded disc with four moons strung out beside it — the sight that told Galileo the Earth was not the centre of anything. The ecliptic and the celestial equator cross the sky, and each planet draws the path it has taken over the past year, including the strange backwards loop Mars makes when the Earth overtakes it on the inside.

Press the compass and the phone becomes a window. Stand outside, hold it up, and it turns as you turn: there is Saturn, 21 degrees up in the east-southeast, whatever the clouds say.

ECLIPSES, AND EVERYTHING ELSE WORTH BEING THERE FOR

A search runs quietly through the ephemeris for things about to happen, and marks them along the timeline: gold for solar eclipses, red for lunar, white for transits, blue for oppositions, green for two planets passing within half a degree. Step from one to the next.

Step to a solar eclipse and you stand on the spot where it is deepest — 65.2°N 25.1°W, in the Atlantic, on 12 August 2026 — and stay there as the Earth turns under the Moon's shadow. Step to a lunar eclipse and the Moon goes copper in the Earth's shadow. Both are checked against NASA's eclipse canon: times within three minutes, places within a degree.

HOW GOOD ARE THE NUMBERS

Checked against JPL Horizons, the service mission planners use. The planets agree within a tenth of a degree across four centuries. The Moon, within a hundredth. Pluto, Ceres, Eris, Haumea and Makemake, within a hundredth. Twenty-one moons within a degree. Halley, Hale-Bopp, NEOWISE and six other comets within half a degree of their famous perihelia. The asteroid belt is 8,825 real asteroids, each one solved afresh every frame — and the Kirkwood gaps, where Jupiter has swept the belt clean, appear by themselves, because nothing put them there but the arithmetic.

THINGS TO TRY

- A month a second: Mercury laps the Sun while Neptune barely stirs.
- Follow the Earth, and watch the daylight sweep across the Atlantic.
- Find the next total eclipse near you, and see where the shadow lands.
- 3 July 2020: NEOWISE rounding the Sun with its tail thrown out behind it.
- 1610, and Jupiter, the way Galileo saw it.

NO ACCOUNT, NO ADS, NOTHING COLLECTED

The app never connects to anything. There is no sign-in, no advertising, no tracking, no analytics, no subscription and no network at all. Everything it knows, it works out where you are holding it. The only thing it stores is where you left it.

---

## What to Test (TestFlight)

    Everything is computed on the phone, so the things worth watching are
    whether it stays smooth and whether it stays cool: play at a month a
    second with the comets and asteroids on, and zoom in and out of Saturn.

    Then hold it up to the sky in the Earth view, with the location button
    on, and tell me whether what it points at matches what is up there.
