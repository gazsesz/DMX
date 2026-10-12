# Movement FX – javaslat (csak terv, kódhoz nem nyúltunk)

> **Állapot (2026-10-12, v1.33.0, branch `claude/movement-fx`):** az 1–6. lépés megvalósult (engine, modell+mentés, lejátszás a `ChasePlayer`-ben, FX-bank szerkesztő + presetek, chase- és Smart Program-integráció). A megvalósítás eltért a 3.1 „új MovementPlayer” ötlettől: a `ChasePlayer` futtatja az FX lépést, így nem kellett külön lejátszót bekötni. Nyitott: Generate Program kivezetése, blackout-kori speed csatorna, valós fejes teszt.

Cél: swim, circle, sweep, float, light rider stb. mozgások **paraméterekkel** (nem lépésekkel) beállítható „FX bankként”, amelyet a **Chase** és a **Smart Program** is ugyanúgy használhat, mint egy sima bankot.

## 1. Miért nem jó a mostani megoldás

A `Banks → Generate Program` (`core/generator/program_generator.dart`) a mozgást **N darab jelenetté** sütögeti ki (`_moveShape` mintavételezi a pályát, jelenetenként 1 pont, a lejátszó pedig crossfade-el köztük). Következmények:

- A mozgás minősége a lépésszámtól és a fade-től függ (kevés lépés → szögletes „circle”, sok lépés → nagy bank).
- Sebesség/méret/irány/fázis módosításához **újra kell generálni** az egészet, nem lehet élőben állítani.
- Nincs benne a stage-plan/aim tudás (`core/positions/aim.dart`), csak nyers 0..255 pan/tilt – ezért a fejek tükrözése, invertje, kalibrációja, 16 bites csatornák nem érvényesülnek (valószínűleg ez az oka, hogy élőben néhány generált program „nem csinált semmit” – lásd a memóriában a TODO-t).
- Beat-szinkron csak a lépések szintjén lehetséges, a pálya fázisához nem kötődik.

## 2. Alapötlet: a mozgás egy *generátor*, nem tárolt lépéssorozat

Egy **MovementFx** egy matematikai pálya + paraméterek. A lejátszó **folyamatosan** (kb. 25–40 Hz-en) kiszámolja a pozíciót az idő/fázis függvényében, és kiírja a pan/tilt csatornákra. Nincs jelenet-lépés, nincs fade – a simaságot a mintavételezési frekvencia adja.

### 2.1 Adatmodell (`models/movement_fx.dart`)

```
enum MovementShape { circle, panSweep, tiltSweep, sweep(triangle), swim(figure-8),
                     float(wander), lightRider(bounce), square, diamond, random(walk), custom }

class MovementFx {
  id, name
  shape
  // --- pálya ---
  double sizePan, sizeTilt        // 0..1, a mozgástartomány fele (fokban/arányban)
  double centerPan, centerTilt    // középpont (PanTilt, vagy stage-pont)
  double rotationDeg              // pálya elforgatása (ellipszis/8-as dőlése)
  // --- idő ---
  double speedHz  | beatsPerCycle // szabad futás VAGY beathez kötött ciklushossz (1,2,4,8,16 beat)
  bool   beatLocked               // true → fázis a beat-ből, nem az óráról
  MovementDirection direction     // forward / reverse / pingpong
  double phaseOffsetPerFixture    // fixture-ek közti eltolás (hullám/„fan” hatás), 0..1 ciklus
  FxPhaseSpread spread            // all-same | offsetPerFixture | mirrorHalves | groupsAlternate
  // --- célok ---
  Set<String> groupIds / fixtureIds   // melyik mozgó fejek (üres = mind, ami mover)
  // --- kimenet módja ---
  MovementSpace space             // panTilt (nyers) | stage (spot a színpadon → aimAt)
  double aimZ                     // stage módban a pálya síkja (pl. padló, 0 m)
  // --- finomítás ---
  double smoothing                // 0..1 (lowpass, hogy a fej ne rángasson)
  double intensityEnvelope        // opcionális: fade-in/out a start/stop-nál
}
```

Mentés: `project_data.dart`-ba új lista (`movementFx`), JSON migráció nélkül (hiányzó lista = üres), mint ahogy a `slotTimings` is opcionális.

### 2.2 Pálya-számítás (`core/movement/movement_engine.dart`)

Tiszta függvény, könnyen tesztelhető:

```
Offset2 shapeAt(MovementShape s, double phase01)   // -1..1 normált (a mostani _moveShape ide költözik)
PanTilt resolve(MovementFx fx, fixtureIndex, count, phase, previousPanTilt)
```

- `space == panTilt`: normált (x,y) → `center + size * rot(shape)` → `PanTilt` (16 bit).
- `space == stage`: a normált pálya a **színpadi síkon** (méterben) rajzolódik, majd `aimAt(rig, tx, ty, tz, previous: …)` számolja a fejenkénti pan/tilt-et. Előny: a „circle” tényleg kör a padlón, minden fejről nézve, a mounting/invert/offset kezelve. A `previous` paraméter már most megoldja a 540°-os pan „rossz irányba tekeredés” problémát.
- Fixture-enkénti fázis: `phase + i * phaseOffsetPerFixture` → hullámzó, „swim”-szerű hatás.

## 3. Hogyan illeszkedik a bankok/chase/smart chase világába

Ma: `Bank` = jelenet-slotok; `ChaseStep` = `sceneId` **vagy** `bankId`; `ProgramTarget` = `chaseId` **vagy** `bankId`. A legkisebb beavatkozás az, ha az FX egy **új típusú elem** ezeken a pontokon:

| Hely | Változás |
|---|---|
| `Bank` | új mező: `BankKind kind` (`scenes` alapértelmezett / `movementFx`) + `MovementFx? fx` **vagy** `fxId`. Az `fx` típusú banknak nincs `sceneSlots`-a (vagy üres), a szerkesztője a paraméter-panel. |
| `ChaseStep` | változatlan marad: `bankId` mutathat FX-bankra is. Az FX-bank lépése = „indítsd/tartsd az FX-et `hold` ideig”, a `fade` = az FX be-/kifutási burkolója (envelope). |
| `ProgramTarget` | változatlan: `bankId` → FX-bank. A Smart Program zónánként (base/faster/slower) más FX-bankot is kioszthat → pl. lassú `float` base-en, gyors `circle` gyors zónában. |
| `Layer` | az FX a saját rétegén fut (pl. „Movement” réteg), a szín/dimmer chase egy másikon – **ez ma is így működik** (rétegek függetlenek), tehát a „csak mozgás” FX nem veszi át a színt. |

Fontos: a **megosztott csatornák arbitrációja** (DECISIONS: rétegek közti arbitráció) a pan/tilt csatornákra is vonatkozik. Az FX csak a pan/tilt (+ opcionálisan pan/tilt speed) csatornákat írja, a többit békén hagyja – ugyanúgy, ahogy a jelenet `fixtureValues` is csak a megadott offseteket tartalmazza.

### 3.1 Lejátszó oldal

Két lehetőség:

**A) Új `MovementPlayer` a `ChasePlayer` mellett (ajánlott).**
- Rétegenként 0..1 FX fut; `playerFor(layerId)`-hoz hasonló `movementFor(layerId)`.
- Ha egy chase-lépés/zóna/bank FX-bankra mutat, a `ChasePlayer` (vagy a `SmartProgramPlayer._playZone`) nem jelenetet cross-fade-el, hanem `movementPlayer.start(fx, layerId, hold)`-ot hív, a lépés lejártakor `stop`/következő lépés.
- Egy `Ticker`/`Timer.periodic` (~30 Hz) számol, és **egy Art-Net csomagot** küld universe-enként (ahogy a ChasePlayer is teszi; a `_minStepDuration` tanulsága: ne lehessen 0 ms-es hurok).
- Az FX a layer-puffer pan/tilt csatornáiba ír, így a Freeze/Strobe/Dropout „output effektek” (`momentary_fx.dart`, `dimmer_dropout.dart`) változtatás nélkül működnek rajta (a Freeze pl. megfogja a mozgást).

**B) FX-et kiégetni futás közben jelenetekké** – elvetve: pont a mostani gyengeségeket örökölné.

### 3.2 Beat-szinkron

- `beatLocked`: a fázis = `(beatCounter + beatFraction) / beatsPerCycle`. A `ChasePlayer`/`SmartProgramPlayer` már kap beat eseményeket + `BeatRate` (½×, 1×, 2×, Flash) – az FX a **BPM-ből számolt ciklusidőt** használja, a beat-ek csak fázis-újraszinkronra kellenek (drift ellen), nem lépést léptetnek.
- Nincs beat → szabad futás `speedHz`-en (mint a dropout „beat nélkül az időzítőre esik vissza” elve).
- Smart Program zónaváltásnál: az FX **fázist megőrizve** vált paramétert/sebességet (különben a fej ugrik); az `updateProgram`/`replayCurrentZone` logikájához kell majd egy „ne indítsd újra az FX-et, csak módosítsd” út.

### 3.3 Átmenetek

- Indításkor a fej a jelenlegi pozíciójából **fut be** a pályára (envelope 0→1 a pályasugárra / vagy lineáris interpoláció a pályapontra `fade` idő alatt), ne ugorjon.
- Leállításkor: marad ott, ahol van (mint a Stop a chase-nél), vagy opcionálisan „vissza a középre” (`homeOnStop`).

## 4. Felület

1. **Banks képernyő**: új bank létrehozásakor választó: *Scenes bank* | *Movement FX bank*.
2. **FX-bank szerkesztő** (a jelenet-rács helyett):
   - Alak-választó csempék (Circle, Pan sweep, Tilt sweep, Sweep, Swim, Float, Light Rider, Square, Random).
   - Csúszkák: Size (pan/tilt külön), Speed (Hz) **vagy** Beats/ciklus (1·2·4·8·16), Fan / Phase offset, Smoothing.
   - Irány (→ ← ↔), Center = a meglévő XY pad / stage nézet (`group_positions`, `PositionMode.pad/stage`) újrahasznosítva a középpont megadásához.
   - Cél: csoport/fixture választó (a meglévő csoport-választó).
   - **Élő előnézet**: kis stage-nézet, ahol a pálya + a fejek célpontjai animálva látszanak, és egy „Test” gomb, ami a valódi fejeken is lejátssza (a hibakeresés is egyszerűbb: látszik, mit számol az engine).
3. **Chase szerkesztő**: az FX-bank ugyanúgy választható lépésnek, vizuálisan megkülönböztetve (ikon: 〰). A lépés hold/fade értelmezése: lásd 3. szakasz.
4. **Smart Program**: a bank-választóban az FX-bankok is megjelennek; zónánként választható.
5. **Gyors preset-ek**: „Swim”, „Circle”, „Light Rider”, „Float”, „Fan Sweep” egy koppintással létrehozott, értelmes alapparaméterű FX-bank (a mostani Generate Program presetek helyett/mellett).
6. **Dashboard trigger**: az FX-bank pad ugyanúgy indítható, mint a bank (a trigger a bank id-ját ismeri, nem kell új típus).

## 5. Mi legyen a mostani `Generate Program` mozgás-részével

- Az új FX-bank rendszer kész után a `panSweep/tiltSweep/sweep/swim/float/center/lightRider/circle` effektek a generátorban **„Convert to Movement FX bank”**-ra cserélhetők (vagy a lista a generátorból eltűnik, mert az FX-bank szerkesztő a jobb hely).
- `_moveShape` újrahasznosítható az engine-ben (ott a helye), a lépés-sütés (`panNorm` → 0..255) viszont megszűnik.
- Régi, már legenerált bankok maradnak érvényes jelenet-bankok – nincs migráció.

## 6. Megvalósítási sorrend (javasolt, kis lépésekben)

1. **Engine + tesztek** (`shapeAt`, `resolve`, panTilt és stage mód, fázis/fan) – UI nélkül, tisztán unit teszttel (a meglévő `aim` tesztek mintájára).
2. **MovementFx modell + project mentés/betöltés** (opcionális mezők, visszafelé kompatibilis).
3. **MovementPlayer** (egy réteg, szabad futás) + „Test” gomb egy minimális szerkesztőből – ezen már a valódi fejeken kipróbálható (ez a kritikus pont, mert a mostani generátor itt bukott el).
4. **FX-bank szerkesztő UI** + presetek.
5. **Chase integráció** (`bankId` → FX-bank, hold/fade/envelope).
6. **Smart Program integráció** (zónánkénti FX, fázismegőrző váltás).
7. **Beat-lock** finomhangolás + preview a stage nézetben.
8. Generator mozgás-effektek kivezetése / átkötése.

## 7. Kockázatok / nyitott kérdések

- **Pan/tilt csatorna-azonosítás** valós profilokon: a generátor hibájának gyanúja (rosszul típusozott „Pan/Tilt speed”, 16 bites fine csatornák). Az 1–3. lépésnél először ezt kell valós profilokkal ellenőrizni (a `PanTilt` és az aim kód már 16 bitet kezel – arra kell építeni).
- **Pan/tilt speed csatorna**: sok mozgófej „speed” csatornája lassítja a mozgást; FX közben fixen gyorsra (0) kell tenni, különben a fej lemarad a pályától. Kell-e profil-szintű jelölés („FX közben ennyi legyen”)?
- **Terhelés**: 30 Hz × univerzumonként 1 csomag olcsó, de a tablet (Tab S6 Lite) és P20 Pro-n kell mérni, főleg ha több réteg is FX-et futtat.
- **Hold/fade jelentése FX-lépésnél**: javaslat – `hold` = meddig fusson az FX a lépésben, `fade` = be-/kifutási envelope. Elfogadható?
- **Egy chase-ben több FX lépés ugyanazon a rétegen**: a váltásnál fázis-folytonosság vagy újraindítás? (Javaslat: alapból folytonos pozíció, a paraméterek `fade` alatt interpolálnak.)
- **Custom pálya** (rajzolt/pontlistás): későbbi bővítés, első körben kihagyható.
- **Pan/tilt „fine” csatornák és DMX felbontás**: lassú mozgásnál a 8 bites lépcsőzés látszik; 16 bit kötelező, ahol a profil támogatja.

## 8. Összefoglaló ajánlás

Az **FX-bank = paraméteres, élő számolású generátor** legyen, ne jelenet-sorozat; a meglévő bank/chase/smart program struktúra **változatlanul hivatkozhat rá** (`bankId`), így a chase és a smart chase külön „FX támogatás” nélkül, csak a lejátszó (`MovementPlayer`) bővítésével használni tudja. A kritikus első lépés az engine + valós fejeken való tesztelés, hogy a korábbi „néhány program nem csinált semmit” hiba okát kizárjuk, mielőtt UI épül rá.
