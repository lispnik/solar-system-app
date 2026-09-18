;;;; ephemeris-tests.lisp -- the physics, checked against JPL.
;;;;
;;;; The reference positions are JPL Horizons' own: heliocentric (500@10)
;;;; ecliptic J2000 vectors of each planet system's barycentre (bodies 1-8,
;;;; which is what Standish's elements were fitted to), in AU, fetched once
;;;; from https://ssd.jpl.nasa.gov/api/horizons.api with TIME_TYPE TT.

(defpackage #:solar-system/test
  (:use #:cl #:solar-system.core #:fiveam)
  (:export #:run-tests))

(in-package #:solar-system/test)

(def-suite solar-system)
(in-suite solar-system)

(defun run-tests ()
  "T when every test passes. FIVEAM:RUN! answers NIL on failure, but ASDF
discards what a TEST-OP returns, so the status comes from here."
  (let ((results (run 'solar-system)))
    (explain! results)
    (every (lambda (result) (typep result 'it.bese.fiveam::test-passed)) results)))

(defparameter +horizons+
  ;; JD (TT)   planet    x                      y                      z
  '((2415020.5d0
     ("Mercury" -3.873786086597009d-01 -1.626546484001203d-01  2.239016479510371d-02)
     ("Venus"    6.998542285693072d-01 -1.936805114543975d-01 -4.304705980255765d-02)
     ("Earth"   -1.968855472516132d-01  9.633225046957872d-01  2.145142891967984d-04)
     ("Mars"     4.353672637606895d-01 -1.352511632055670d+00 -3.907972599713234d-02)
     ("Jupiter" -3.016040410745475d+00 -4.460193700713316d+00  8.580442433444235d-02)
     ("Saturn"  -3.669663184956261d-01 -1.005835317286958d+01  1.915846966741367d-01)
     ("Uranus"  -6.479256690536241d+00 -1.785344415641295d+01  1.776408265133505d-02)
     ("Neptune"  1.514876809882932d+00  2.982557085902764d+01 -6.491142369486281d-01))
    (2451545.0d0
     ("Mercury" -1.300936053934398d-01 -4.472876181299281d-01 -2.459830695595736d-02)
     ("Venus"   -7.183022963460609d-01 -3.265430818272031d-02  4.101418202711851d-02)
     ("Earth"   -1.771587841694229d-01  9.672193524636139d-01 -1.139275508446145d-06)
     ("Mars"     1.390715921745722d+00 -1.341631816512547d-02 -3.446766277610819d-02)
     ("Jupiter"  4.001177161129903d+00  2.938576106960678d+00 -1.017852766338073d-01)
     ("Saturn"   6.406408859536422d+00  6.569989616909282d+00 -3.690764262449402d-01)
     ("Uranus"   1.443185661437953d+01 -1.373432146877321d+01 -2.381416877992296d-01)
     ("Neptune"  1.681204696805071d+01 -2.499176288928619d+01  1.272228799203305d-01))
    (2461301.5d0
     ("Mercury" -2.848027815664024d-01 -3.542421273650770d-01 -2.829011401707719d-03)
     ("Venus"    6.466721407857351d-01 -3.314939275925899d-01 -4.186654188338516d-02)
     ("Earth"    1.000744296380260d+00 -9.215133961180823d-02 -4.949571839132169d-07)
     ("Mars"     3.004377995008284d-01  1.512181215582875d+00  2.432299210655776d-02)
     ("Jupiter" -3.414770378530164d+00  4.056419729859266d+00  5.955045413073144d-02)
     ("Saturn"   9.276495526464478d+00  1.695593977931932d+00 -3.987906796979625d-01)
     ("Uranus"   8.976580382511601d+00  1.724740659331322d+01 -5.233682048630917d-02)
     ("Neptune"  2.983976590705068d+01  1.339177042496859d+00 -7.152252318723350d-01))))

(defparameter +horizons-table-2+
  ;; Outside 1800 -- 2050, where table 2 is used: 1600-01-01 and 2399-12-31.
  '((2305447.5d0
     ("Mercury" 2.737813605034315d-01 -3.164421022358910d-01 -5.109324513428219d-02)
     ("Venus"   -2.971096421536228d-01 6.537227936885946d-01 2.544784769209395d-02)
     ("Earth"   -2.638760462022865d-01 9.471123779328325d-01 8.461275066002970d-04)
     ("Mars"    -8.593166501601326d-01 1.394720825923549d+00 5.086469549807825d-02)
     ("Jupiter" -4.067265493674983d+00 3.466515181674654d+00 7.832967031791005d-02)
     ("Saturn"  -8.651412683615924d+00 -4.493428475920743d+00 4.216280623475084d-01)
     ("Uranus"  1.609653425980012d+01 1.149741508218621d+01 -1.663543845245938d-01)
     ("Neptune" -2.658644716759777d+01 1.418604710101901d+01 3.199393963553798d-01))
    (2597640.5d0
     ("Mercury" -3.932526884223135d-01 -5.527229196062249d-02 3.114525240867474d-02)
     ("Venus"   -2.864644872643163d-01 -6.663459422827906d-01 6.595727612702853d-03)
     ("Earth"   -5.429765953074055d-02 9.822451749947529d-01 -8.830694135220366d-04)
     ("Mars"    -1.125802535671482d+00 -1.093464987678189d+00 3.648614533568581d-03)
     ("Jupiter" 1.591855318755279d+00 -4.925270757894812d+00 -1.366696981812122d-02)
     ("Saturn"  -1.671778228254675d+00 -9.918503419571095d+00 2.338821806053355d-01)
     ("Uranus"  -1.145963075649081d+01 -1.477342625296520d+01 9.422129653961968d-02)
     ("Neptune" -4.905492526021018d+00 2.950388231273887d+01 -4.947285258976031d-01))))

(defparameter +horizons-dwarfs+
  ;; Heliocentric, ecliptic J2000, AU, between the ten-year samples: 1955-06-01,
  ;; 2026-09-18 and 2433-11-28.
  '(("Pluto" (2435259.5d0 -2.874406406573d+01 1.887887786928d+01 6.291331269243d+00) (2461301.5d0 1.992937603506d+01 -2.938374955468d+01 -2.619680394634d+00) (2610000.5d0 -1.936903218909d+01 3.432579788211d+01 1.935735935330d+00))
     ("Ceres" (2435259.5d0 5.552228253190d-01 -2.829367430799d+00 -1.838359372128d-01) (2461301.5d0 4.176041537425d-01 2.650901313451d+00 6.991477942501d-03) (2610000.5d0 -8.386051847446d-01 -2.622207273506d+00 1.556562408080d-02))
     ("Eris" (2435259.5d0 8.783394781895d+01 1.392147924162d+01 -3.894376821815d+01) (2461301.5d0 8.508887063820d+01 3.968567448286d+01 -1.725577035375d+01) (2610000.5d0 6.783944800960d+01 -1.815949383554d+01 -5.265481980344d+01))
     ("Haumea" (2435259.5d0 -4.035304873086d+01 2.679142538188d+01 1.075820384494d+01) (2461301.5d0 -3.666049829621d+01 -2.406186095535d+01 2.351340909422d+01) (2610000.5d0 2.545467535866d+01 1.845710282681d+01 -1.682267221765d+01))
     ("Makemake" (2435259.5d0 -2.039464358272d+01 3.883842008397d+01 1.505532620601d+01) (2461301.5d0 -4.593309927630d+01 -9.607140489447d+00 2.405637799076d+01) (2610000.5d0 1.024764107925d+01 -4.183896935517d+01 -9.846810167529d+00))))

(defparameter +horizons-moons+
  ;; Relative to each planet's centre, ecliptic J2000, AU: 1950, 2000, 2026
  ;; and 2050 -- none of them dates the moons were fitted at.
  '(("Moon" (2433282.5d0 1.246753512940d-03 2.355766677748d-03 1.764527851161d-04) (2451545.d0 -1.949281650000d-03 -1.838126039718d-03 2.424579738877d-04) (2461301.5d0 -6.818127496979d-04 -2.598227392845d-03 -2.361337693479d-04) (2469807.5d0 2.403647813376d-03 7.792582856280d-04 1.496495582496d-04))
     ("Phobos" (2433282.5d0 -3.941436763157d-05 4.396590399225d-05 2.117500012594d-05) (2451545.d0 -1.329549714362d-05 -6.208326084485d-05 3.731079139895d-06) (2461301.5d0 5.506540792091d-05 -7.901326428781d-06 -2.675101827472d-05) (2469807.5d0 5.014755169639d-05 2.816484102403d-05 -2.397791839196d-05))
     ("Deimos" (2433282.5d0 4.901656055214d-05 -1.444685081537d-04 -3.604723493304d-05) (2451545.d0 6.929537275069d-05 -1.336605864093d-04 -4.365399003405d-05) (2461301.5d0 1.071572147177d-04 1.071104439149d-04 -4.037062732000d-05) (2469807.5d0 8.813202103806d-05 -1.196205923496d-04 -5.002913939025d-05))
     ("Io" (2433282.5d0 4.488349271423d-04 2.791750839248d-03 1.049529430727d-04) (2451545.d0 2.671924639380d-03 8.640941822172d-04 7.127946398315d-05) (2461301.5d0 2.084590189255d-03 -1.892926992792d-03 -3.862407039660d-05) (2469807.5d0 2.020315299793d-03 -1.966864973924d-03 -4.184989153850d-05))
     ("Europa" (2433282.5d0 4.084372285149d-03 -1.833169519478d-03 -4.154225834448d-05) (2451545.d0 -3.751687585284d-03 -2.379800301270d-03 -1.200157297652d-04) (2461301.5d0 4.505692544929d-03 -3.320953294502d-04 8.115020642287d-05) (2469807.5d0 3.952141818321d-05 4.452209753964d-03 1.812652632239d-04))
     ("Ganymede" (2433282.5d0 6.923098488239d-03 1.813716060211d-03 1.578323798361d-04) (2451545.d0 -5.490352847439d-03 -4.581541304809d-03 -2.310042059416d-04) (2461301.5d0 -1.734484708482d-03 6.943467946574d-03 2.400434086581d-04) (2469807.5d0 2.968467270378d-03 6.496750320938d-03 2.807699164194d-04))
     ("Callisto" (2433282.5d0 1.157165679424d-02 -4.718607855315d-03 -3.970982714617d-05) (2451545.d0 2.173023785026d-03 1.238159356766d-02 4.328588775986d-04) (2461301.5d0 5.615245210258d-03 -1.122965016298d-02 -2.761123997977d-04) (2469807.5d0 -1.266263251806d-02 -2.678406456737d-04 -1.773715347300d-04))
     ("Mimas" (2433282.5d0 -1.167549056456d-03 4.571174832727d-04 -1.513804049747d-04) (2451545.d0 9.424462117081d-04 -7.195485789733d-04 2.967865527378d-04) (2461301.5d0 -2.070574905165d-04 1.105504053967d-03 -5.640405257887d-04) (2469807.5d0 8.040205679734d-04 8.254168950272d-04 -5.104303551800d-04))
     ("Enceladus" (2433282.5d0 -4.993781246551d-04 -1.310720556788d-03 7.353146481046d-04) (2451545.d0 1.080965229745d-03 -1.065020597649d-03 4.531252577859d-04) (2461301.5d0 -1.919562853231d-04 1.407611458777d-03 -7.187370643942d-04) (2469807.5d0 1.530970146020d-03 2.797751508101d-04 -2.951800201680d-04))
     ("Tethys" (2433282.5d0 1.846102422111d-03 -6.729328144454d-04 1.359092385049d-04) (2451545.d0 1.450781083303d-03 -1.246281688888d-03 4.718716773717d-04) (2461301.5d0 1.775745605139d-03 6.914436431338d-04 -4.995438119958d-04) (2469807.5d0 9.336859136712d-04 -1.587530638589d-03 6.995385240294d-04))
     ("Dione" (2433282.5d0 8.192807359445d-04 2.084928504183d-03 -1.173001390197d-03) (2451545.d0 1.527753249112d-03 -1.830343884066d-03 8.097825457312d-04) (2461301.5d0 -1.671694316409d-03 -1.608197283261d-03 1.003226484885d-03) (2469807.5d0 -2.506926562170d-03 -8.130809551221d-05 2.847037153396d-04))
     ("Rhea" (2433282.5d0 2.821577464236d-03 -1.958409031919d-03 7.719709559525d-04) (2451545.d0 -3.507819832569d-03 -9.923154488700d-06 3.652530576495d-04) (2461301.5d0 6.693291875552d-04 3.030979514169d-03 -1.667862083123d-03) (2469807.5d0 2.589232936073d-03 2.011034686657d-03 -1.282943664752d-03))
     ("Titan" (2433282.5d0 7.041450929183d-03 3.278958381359d-03 -2.371031169766d-03) (2451545.d0 -6.328986727950d-03 5.126196170877d-03 -2.025162433229d-03) (2461301.5d0 -5.380693023966d-04 7.314128566413d-03 -3.717897076385d-03) (2469807.5d0 -3.173492202435d-03 -6.641401419845d-03 3.734973344661d-03))
     ("Iapetus" (2433282.5d0 -1.989894184489d-02 1.399260501081d-02 4.656504307323d-04) (2451545.d0 -1.907629584271d-02 -1.350238682471d-02 7.023876130028d-03) (2461301.5d0 -2.034001760197d-02 -1.173973257469d-02 6.784263545122d-03) (2469807.5d0 7.823416731253d-03 -2.214018165755d-02 3.357617454286d-03))
     ("Miranda" (2433282.5d0 4.699777874581d-04 -2.299919017428d-04 -6.927401463664d-04) (2451545.d0 -6.973998457640d-04 3.073370805440d-05 -5.150642176510d-04) (2461301.5d0 5.895002690835d-04 -8.428085366017d-05 6.307146422265d-04) (2469807.5d0 -5.337825033351d-04 1.462789788934d-04 6.692616671733d-04))
     ("Ariel" (2433282.5d0 8.987853113713d-04 -3.152160416030d-04 -8.476245102643d-04) (2451545.d0 1.174334466357d-03 -3.121957397862d-04 -3.962185264135d-04) (2461301.5d0 1.012335017823d-03 -3.194933396039d-04 -7.074176406904d-04) (2469807.5d0 1.244937880837d-03 -2.546497887351d-04 1.253073276831d-04))
     ("Umbriel" (2433282.5d0 -1.433534519975d-03 1.685756432812d-04 -1.044161264463d-03) (2451545.d0 6.685277240749d-04 -3.678213215310d-04 -1.606005932002d-03) (2461301.5d0 -1.665591897324d-03 2.867113917762d-04 -5.459163400752d-04) (2469807.5d0 1.709950259009d-03 -3.265715650059d-04 3.290886708809d-04))
     ("Titania" (2433282.5d0 -2.718912994046d-03 7.071131639177d-04 8.038252920939d-04) (2451545.d0 -4.218442495584d-04 -3.104395421093d-04 -2.867062632094d-03) (2461301.5d0 2.729634134592d-03 -4.698205120880d-04 9.183581194189d-04) (2469807.5d0 2.850415918375d-03 -5.982772061760d-04 1.679778361280d-04))
     ("Oberon" (2433282.5d0 3.812380686590d-03 -8.063848160043d-04 1.610080146584d-04) (2451545.d0 -3.747178734832d-03 6.954436990712d-04 -8.319915701591d-04) (2461301.5d0 2.282613942233d-03 -9.257375768822d-04 -3.014325044827d-03) (2469807.5d0 3.551753584475d-03 -5.628606840697d-04 1.504282286181d-03))
     ("Triton" (2433282.5d0 1.826910069210d-03 -6.659343724542d-04 -1.357926782995d-03) (2451545.d0 -1.374996005778d-03 8.293000630125d-04 1.744682412283d-03) (2461301.5d0 5.668708113728d-04 1.925889239161d-03 1.261729931758d-03) (2469807.5d0 9.587985942324d-04 -1.150557075907d-03 -1.838965690184d-03))
     ("Charon" (2433282.5d0 7.623874249253d-05 1.734402611686d-05 -1.050859605928d-04) (2451545.d0 -4.570734202091d-05 -9.679682909908d-05 -7.552618158450d-05) (2461301.5d0 4.718324978763d-05 9.734320510306d-05 7.383450293748d-05) (2469807.5d0 -9.102272263621d-05 -4.865167758184d-05 8.068293648505d-05))))

(defun angle-between (ax ay az bx by bz)
  "Degrees between two vectors."
  (let ((dot (+ (* ax bx) (* ay by) (* az bz)))
        (na (sqrt (+ (* ax ax) (* ay ay) (* az az))))
        (nb (sqrt (+ (* bx bx) (* by by) (* bz bz)))))
    (/ (* 180d0 (acos (max -1d0 (min 1d0 (/ dot (* na nb)))))) pi)))

(test kepler-solves-its-equation
  (loop for e in '(0d0 0.01d0 0.05d0 0.1d0 0.2d0 0.25d0)
        do (loop for m from -3.1d0 to 3.1d0 by 0.1d0
                 do (let ((ea (solve-kepler m e)))
                      (is (< (abs (- ea (* e (sin ea)) m)) 1d-12)
                          "e=~a M=~a: residual ~a" e m (- ea (* e (sin ea)) m))))))

(test julian-dates
  (is (= 2451545d0 (jd-from-calendar 2000 1 1 12)))
  (is (= 2415020.5d0 (jd-from-calendar 1900 1 1)))
  (is (= 2461301.5d0 (jd-from-calendar 2026 9 18)))
  ;; Meeus's own examples, either side of the Gregorian reform.
  (is (= 2436116.31d0 (jd-from-calendar 1957 10 4.81d0)))
  (is (= 2299160.5d0 (jd-from-calendar 1582 10 15)))
  (is (= 2299159.5d0 (jd-from-calendar 1582 10 4)))
  (is (< (abs (- 1507900.13d0 (jd-from-calendar -584 5 28.63d0))) 1d-6))
  ;; NSDate's reference date, and CL's universal time zero.
  (is (= 2451910.5d0 (jd-from-2001-seconds 0)))
  (is (= 2451545d0 (jd-from-2001-seconds (* -365.5d0 86400))) "2000 was a leap year")
  (is (= 2415020.5d0 (jd-from-universal-time 0)))
  (is (string= "2026-09-18 14:31:07 UTC" (format-jd (jd-from-calendar 2026 9 18 14 31 7.2d0))))
  (multiple-value-bind (y m d) (calendar-from-jd 1507899.5d0)
    (is (equal '(-584 5 28) (list y m d)))))

(defun check-against (reference max-degrees max-fraction)
  (loop for (jd . rows) in reference
        for tc = (centuries-since-j2000 jd)
        do (loop for (name hx hy hz) in rows
                 do (multiple-value-bind (x y z) (heliocentric-position (find-planet name) tc)
                      (let ((angle (angle-between x y z hx hy hz))
                            (r (sqrt (+ (* x x) (* y y) (* z z))))
                            (hr (sqrt (+ (* hx hx) (* hy hy) (* hz hz)))))
                        (is (< angle max-degrees) "~a at JD ~a: ~,4f degrees off" name jd angle)
                        (is (< (abs (/ (- r hr) hr)) max-fraction)
                            "~a at JD ~a: r ~,5f AU, Horizons ~,5f AU" name jd r hr))))))

(test positions-match-horizons
  ;; Table 1, 1800 -- 2050: Standish quotes errors of seconds to a few
  ;; minutes of arc, and up to about 600" for Saturn, whose great
  ;; inequality with Jupiter no set of mean elements can follow; measured,
  ;; Saturn is 0.15 degree out and everything else under 0.1. 0.2 degree and
  ;; half a percent in distance is invisible on a phone and still catches
  ;; any sign or rotation slip.
  (check-against +horizons+ 0.2d0 0.005d0))

(test positions-match-horizons-far-from-now
  ;; Table 2, fitted over six millennia, is looser: Saturn's error runs to
  ;; a large fraction of a degree.
  (check-against +horizons-table-2+ 0.6d0 0.01d0))

(test clock-runs-and-rescales
  (let* ((now 2461301.5d0)
         (*wall-clock* (lambda () now))
         (*time-scale* 1d0)
         (solar-system.core::*anchor-wall* nil)
         (solar-system.core::*anchor-sim* nil))
    (is (= now (sim-jd)))
    (incf now 1d0)
    (is (= 2461302.5d0 (sim-jd)) "real time: a day is a day")
    (set-time-scale 10)
    (is (= 2461302.5d0 (sim-jd)) "changing the rate does not jump")
    (incf now 1d0)
    (is (= 2461312.5d0 (sim-jd)) "then ten days pass per day")
    (set-sim-date 2451545d0)
    (incf now 0.5d0)
    (is (= 2451550d0 (sim-jd)))
    (is (= now (real-time)))))

(test compression-keeps-directions-and-fits
  (let* ((tc (centuries-since-j2000 2461301.5d0))
         (k (compression tc)))
    (dolist (planet *planets*)
      (multiple-value-bind (x y z) (heliocentric-position planet tc)
        (multiple-value-bind (cx cy cz) (compress x y z k)
          (is (< (angle-between x y z cx cy cz) 1d-5) "~a's direction kept" (body-name planet))
          (is (<= (sqrt (+ (* cx cx) (* cy cy) (* cz cz))) 1d0) "~a inside the unit sphere"
              (body-name planet)))))
    ;; Order is kept: each planet's orbit further out than the last, and
    ;; the outermost aphelion of anything, Eris's, at 1.
    (let ((radii (mapcar (lambda (planet) (compress (aphelion planet tc) 0d0 0d0 k)) *planets*)))
      (is (apply #'< radii)))
    (is (< (abs (- 1d0 (reduce #'max (heliocentric-bodies)
                               :key (lambda (body) (compress (aphelion body tc) 0d0 0d0 k)))))
           1d-12))))

(test moon-systems-fit-between-the-orbits
  (let* ((tc (centuries-since-j2000 2461301.5d0))
         (k (compression tc))
         (scales (moon-system-scales tc k)))
    (is (= 7 (length scales)) "Earth, Mars, Jupiter, Saturn, Uranus, Neptune, Pluto")
    (loop for (body radius . outermost) in scales
          do (dolist (moon (moons-of body))
               (multiple-value-bind (dx dy dz) (moon-offset moon tc)
                 (multiple-value-bind (x y z) (moon-display-offset dx dy dz radius outermost)
                   (is (< (angle-between dx dy dz x y z) 1d-5) "~a's direction kept" (body-name moon))
                   ;; The Moon's distance varies, so it may exceed its mean a.
                   (is (<= (sqrt (+ (* x x) (* y y) (* z z))) (* 1.05 radius))
                       "~a inside its system's radius" (body-name moon))))))))

(defun on-screen (camera aspect x y z)
  "Values the normalised device x and y of a world point."
  (multiple-value-bind (vx vy vz) (view-position camera aspect x y z)
    (let ((m (projection-matrix camera aspect)))
      (values (/ (* (aref m 0) vx) (- vz))
              (/ (* (aref m 5) vy) (- vz))))))

(test camera-starts-from-the-north-pole
  (let ((camera (make-camera)))
    (dolist (aspect '(0.46d0 1d0 2.17d0))
      (multiple-value-bind (x y) (on-screen camera aspect 0d0 0d0 0d0)
        (is (and (= x 0) (= y 0)) "the Sun in the centre"))
      (multiple-value-bind (x y) (on-screen camera aspect 1d0 0d0 0d0)
        (is (< 0 x 1) "the equinox to the right, on screen at ~a" aspect)
        (is (= y 0)))
      (multiple-value-bind (x y) (on-screen camera aspect 0d0 1d0 0d0)
        (is (= x 0))
        (is (< 0 y 1) "+y up, on screen at ~a" aspect)))))

(test camera-matrices-agree
  ;; The view matrix Metal gets does what VIEW-POSITION does.
  (let ((camera (make-camera)))
    (turn-camera camera 0 0.7d0)
    (turn-camera camera 1 -0.3d0)
    (turn-camera camera 2 1.1d0)
    (pan-camera camera 30d0 -12d0 2000d0 0.5d0)
    (zoom-camera camera 2.5d0)
    (let ((m (view-matrix camera 0.5d0)))
      (multiple-value-bind (vx vy vz) (view-position camera 0.5d0 0.3d0 -0.2d0 0.05d0)
        (loop for want in (list vx vy vz)
              for row from 0
              do (is (< (abs (- want (+ (* (aref m row) 0.3d0) (* (aref m (+ 4 row)) -0.2d0)
                                        (* (aref m (+ 8 row)) 0.05d0) (aref m (+ 12 row)))))
                        1d-12)))))))

(test turning-stays-a-rotation
  (let ((camera (make-camera)))
    (dotimes (i 5000)
      (turn-camera camera (mod i 3) (* 0.013d0 (1+ (mod i 7)))))
    (let ((r (solar-system.core::camera-rotation camera)))
      (dotimes (a 3)
        (dotimes (b 3)
          (is (< (abs (- (if (= a b) 1d0 0d0)
                         (loop for k below 3 sum (* (aref r (+ (* 3 a) k)) (aref r (+ (* 3 b) k))))))
                 1d-9)))))))

(test turning-follows-the-finger
  ;; A drag to the right turns the near side of the scene to the right.
  (let ((camera (make-camera)))
    (turn-camera camera 1 0.2d0)
    (multiple-value-bind (x) (view-position camera 1d0 0d0 0d0 1d0)
      (is (plusp x)))))

(test panning-moves-the-scene-with-the-finger
  (let ((camera (make-camera)))
    (turn-camera camera 2 0.8d0)
    (pan-camera camera 100d0 50d0 1000d0 0.5d0)
    (multiple-value-bind (x y) (on-screen camera 0.5d0 0d0 0d0 0d0)
      (is (< (abs (- x (/ 100d0 500d0 0.5d0))) 1d-9) "right by 100 px of 1000 high, at aspect 1/2")
      (is (< (abs (- y (/ 50d0 500d0))) 1d-9)))))

(test planets-lie-on-their-drawn-orbits
  ;; The orbit is sampled from the same elements the position comes from,
  ;; so the planet must sit on the polyline, within a segment's length.
  (let ((tc (centuries-since-j2000 2461301.5d0)))
    (dolist (planet *planets*)
      (let ((points (orbit-points planet tc 256)))
        (multiple-value-bind (x y z) (heliocentric-position planet tc)
          (let ((nearest (loop for k below 257
                               minimize (sqrt (+ (expt (- x (aref points (* 3 k))) 2)
                                                 (expt (- y (aref points (+ 1 (* 3 k)))) 2)
                                                 (expt (- z (aref points (+ 2 (* 3 k)))) 2))))))
            (is (< nearest (/ (* 2 pi (aphelion planet tc)) 256))
                "~a is ~,4f AU from its drawn orbit" (body-name planet) nearest)))))))

(test dwarf-planets-match-horizons
  ;; Two-body motion from the samples either side of the date, blended.
  ;; Ceres, which Jupiter pulls on most, is the worst: 0.4 degree in 1955.
  (loop for (name . rows) in +horizons-dwarfs+
        do (loop for (jd hx hy hz) in rows
                 do (multiple-value-bind (x y z)
                        (heliocentric-position (find-body name) (centuries-since-j2000 jd))
                      (let ((angle (angle-between x y z hx hy hz))
                            (r (sqrt (+ (* x x) (* y y) (* z z))))
                            (hr (sqrt (+ (* hx hx) (* hy hy) (* hz hz)))))
                        (is (< angle 0.5d0) "~a at JD ~a: ~,4f degrees off" name jd angle)
                        (is (< (abs (/ (- r hr) hr)) 0.005d0) "~a at JD ~a: r off" name jd))))))

(test moons-match-horizons
  ;; Each fitted moon within half as much again as the worst error its fit
  ;; saw, and a tenth of a degree; the Moon, from ELP, within 0.05.
  (loop for (name . rows) in +horizons-moons+
        for moon = (find-body name)
        for limit = (let ((fitted (solar-system.core::moon-fit-error moon)))
                      (if fitted (+ 0.1d0 (* 1.5d0 fitted)) 0.05d0))
        do (loop for (jd hx hy hz) in rows
                 do (multiple-value-bind (x y z) (moon-offset moon (centuries-since-j2000 jd))
                      (let ((angle (angle-between x y z hx hy hz))
                            (r (sqrt (+ (* x x) (* y y) (* z z))))
                            (hr (sqrt (+ (* hx hx) (* hy hy) (* hz hz)))))
                        (is (< angle limit) "~a at JD ~a: ~,3f degrees off, allowed ~,2f"
                            name jd angle limit)
                        (is (< (abs (/ (- r hr) hr)) 0.01d0) "~a at JD ~a: r off" name jd))))))

(test moons-lie-on-their-drawn-orbits
  (let ((tc (centuries-since-j2000 2461301.5d0)))
    (dolist (moon *moons*)
      (unless (string= (body-name moon) "Moon")       ; ELP wanders off the mean ellipse
        (let ((points (moon-orbit-points moon tc 256)))
          (multiple-value-bind (x y z) (moon-offset moon tc)
            (let ((r (sqrt (+ (* x x) (* y y) (* z z))))
                  (nearest (loop for k below 257
                                 minimize (sqrt (+ (expt (- x (aref points (* 3 k))) 2)
                                                   (expt (- y (aref points (+ 1 (* 3 k)))) 2)
                                                   (expt (- z (aref points (+ 2 (* 3 k)))) 2))))))
              (is (< nearest (* r 0.03d0)) "~a is off its drawn orbit" (body-name moon)))))))))

(test barycentre-is-near-the-sun
  (multiple-value-bind (x y z) (sun-barycentric-offset (centuries-since-j2000 2461301.5d0))
    (let ((r-solar-radii (/ (* 149597870.7d0 (sqrt (+ (* x x) (* y y) (* z z)))) 695700d0)))
      (is (< 0.01d0 r-solar-radii 2.3d0) "~,3f solar radii" r-solar-radii))))
