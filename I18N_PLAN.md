# Kétnyelvűsítés (EN + HU) — felmérés és terv

_Készült: 2026-10-09 · alap: v1.30.1 · **frissítve: 2026-11-09, alap: v1.44.8** · státusz: **1–3. lépés kész** (v1.45.1, ág: `claude/i18n-foundation`), a 4. lépés (Scenes + Fixtures) következik._

Cél: az app angol és magyar nyelven fusson; a nyelv a **Setup** oldalon váltható, azonnal (újraindítás nélkül), és megmarad az újraindítás után.

## Felmérés (mennyi munka)

- **175 Dart fájl, ~39 200 sor** (v1.30.1-kor 132 / ~29 800). Továbbra sincs `MaterialApp.locale`, `flutter_localizations`/`intl`, `l10n.yaml`. A beállításokhoz van `shared_preferences`, és a `main.dart` már az első frame előtt betölti a prefeket és `ProviderScope` override-dal adja át → a nyelvet is így töltjük be (nincs „angol villanás” induláskor).
- Felhasználói szöveg: kb. **800–900 szöveg** (2026-11-09-i durva számlálás: `Text`/`label`/`tooltip`/`title`/`hint` literálok). Új terület a v1.30 óta: **Song Show** (`features/songs`, ~93) és a Movement FX szerkesztő/sáv (`banks/movement_fx_editor.dart`, `core/widgets/movement_live_bar.dart`).
  | Terület | ~szöveg |
  |---|---|
  | scenes | 99 |
  | fixtures | 97 |
  | banks (+ Movement FX szerkesztő) | 93 |
  | **songs (Song Show) — új** | 93 |
  | core/widgets | 82 |
  | chases | 62 |
  | settings | 37 |
  | layers | 23 |
  | files, dashboard | 17, 9 |
  | manual_control, shell | 7, 8 (nav címkék) |
- **Logikában élő szöveg (~200+ hely):** `models/`, `state/`, `core/` — **25 enum `label`/`title` getter** (pl. `BeatRate`, `FlashColorMode`, `MovementShape`, `FixtureMounting`, `OutputProtocol`, `GroupPosition`), a `core/song/` elemzés/generálás státuszai, és olyan függvények, amik hibaüzenetet `String`-ként adnak vissza a UI-nak (`runBankOnLayer` → `String? error`, `setEnabled` hibái, MIDI/OSC/mikrofon státuszok). Ezek nem kapnak `BuildContext`-et → külön megoldás kell (lásd lent).
- **Már most kevert nyelvű:** magyar szövegek ~47 sorban, 17 fájlban (a korábbiak mellett új: `stage_aim_view.dart`, `fixture_layout_screen.dart`, `movement_fx_editor.dart`, `chases_screen.dart`, `song_analysis.dart`, `chase_player.dart`, `trigger_actions.dart`, `movement_live_bar.dart`). Ezeket **angolra is le kell fordítani** (az angol lesz az alap/kulcs-forrás).
- **Nem fordítandó, de ne rontsuk el:**
  - `core/widgets/wheel_looks.dart` és `models/fixture_channel.dart`: a fixture-csatornák neveit felismerő kulcsszó-listák (EN+HU kulcsszavak). Ezek *bemenet-felismerés*, nem UI szöveg → maradnak.
  - **Távvezérlő API** (`core/remote/`, Wear OS óra): a végpontok neve és a JSON-válasz gépi protokoll → angol marad; csak az óra által *kiírt* emberi üzeneteket kell majd megnézni (az óra-app nincs ebben a repóban).
  - **Android natív szövegek** (`RemoteControlService.kt` értesítés: „Remote control”, „Listening for remote triggers”; manifest `android:label`): ezeket nem az ARB fordítja. Opcionális: `res/values-hu/strings.xml` — a rendszernyelvet követik, nem az appon belüli választást. Alacsony prioritás.
  - Fixture-könyvtár (`assets/fixtures/`) neve/csatornanevei gyártói adatok → maradnak.
  - Felhasználó által adott nevek (jelenet, bank, chase, csoport, szín) → maradnak. **Alapértelmezett nevek** (új bank „Bank 1”, „Beat Flash”, „Scene …”) viszont a *létrehozáskor* lokalizálódnak és onnantól sima adat.
  - Zenei/DMX szakkifejezések (Hold, Fade, Beat Sync, Art-Net, DMX, Smart Program) — **döntés kell**: a magyar fordításban maradjanak-e angolul (a színpadi szakzsargon magyarul is így megy). Javaslat: maradnak.
- Tesztek: 79 tesztfájl, ebből ~20 widget-teszt `find.text('…')`-tel angol szövegre keres. A teszt-locale legyen mindig `en` → ezek nem törnek, ha az `en` az alapértelmezett és a tesztek explicit `Locale('en')`-t kapnak.

**Becslés:** ~3–4 munkanap fejlesztői munka (a Song Show miatt nőtt), mert a mechanikus kinyerés + a ~190 logikai szöveg átvezetése a lassú rész; a fordítás maga (EN→HU ~700 sor) gyors. Kockázat: alacsony, additív változás; a legnagyobb a sok fájl érintése (merge-konfliktus-veszély → kis, területenkénti PR-ok).

## Megközelítés

**Flutter hivatalos `gen_l10n` (ARB fájlok)** — nincs külső lib-függés a `flutter_localizations` + `intl` mellett.

1. `pubspec.yaml`: `flutter_localizations` (sdk: flutter), `intl`, `flutter: generate: true`; `l10n.yaml` (`arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-localization-file: app_localizations.dart`, `nullable-getter: false`).
2. `lib/l10n/app_en.arb` (sablon, angol) + `app_hu.arb`. Kulcsok terület-prefixszel: `banksEditSlots`, `dropoutFadeOut`, `settingsLanguage`… Paraméteres/többes számú szövegek ICU-val (`{count, plural, …}`: pl. „N step(s)”, „N/M scenes”, „N active”). A magyarban a ragozás miatt a mondatokat ne összefűzéssel, hanem teljes mondatként paraméterezve kezeljük.
3. `lib/app.dart`: a `DmxControllerApp` `ConsumerWidget` lesz, a `MaterialApp` kap `localizationsDelegates`, `supportedLocales: [en, hu]`, `locale:` a nyelv-providerből.
4. **Nyelv-provider:** `appLanguageProvider` (`StateNotifier<AppLanguage>`, `AppLanguage { system, en, hu }`), `SharedPreferences`-ben mentve (`app.language`: `system`/`en`/`hu`), a `main.dart` az első frame előtt tölti be (mint a többi prefet). Alapértelmezés: **rendszernyelv, ha hu vagy en, különben en**. Appon belüli váltáskor azonnal újraépül (MaterialApp.locale).
5. **Setup oldal:** új „Language / Nyelv” szekció az `settings_screen.dart` elején vagy az „About” előtt: `SegmentedButton`: *System · English · Magyar*. A szekció címkéje mindkét nyelven látszik („Language / Nyelv”), hogy rossz nyelv esetén is megtalálható legyen.
6. **Logikai szövegek (nincs BuildContext):** két szabály:
   - Állapot/hiba, amit a UI jelenít meg → a függvény **típusos eredményt/enumot** adjon vissza (pl. `BankRunError.noFixtures`), a UI fordítja `l10n`-nel. Ez a tiszta megoldás, de több átírás.
   - Enum `label` getterek → `extension on BeatRate { String label(AppLocalizations l) … }`.
   - Gyors átmenet (ha idő szűk): a provider-ek `AppLocalizations`-t olvashatnak egy `l10nProvider`-ből (a `localeProvider`-ből `lookupAppLocalizations(locale)`), de ezt csak a ritka, UI-n kívüli státuszoknál használjuk.
7. Dátum/szám formázás: ahol most `toStringAsFixed`/kézi formázás van, a tizedes elválasztó (`,` vs `.`) HU-ban eltér — csak a megjelenített időértékeknél (`0.50s`) érdemes `NumberFormat`-ra váltani; DMX-értékeknél nem.

## Lépések (javasolt PR-sorrend)

1. **Alap:** függőségek, `l10n.yaml`, üres `app_en/hu.arb`, `MaterialApp` bekötés, `localeProvider`, Setup nyelvválasztó (még csak a saját szövegeivel). Tesztek `en` locale-lal. → kis PR, itt dől el a váltás működése.
2. **Shell + Setup + Dashboard + Files + Manual control** (nav címkék, ~90 szöveg).
3. **Banks + Layers** (a meglévő magyar szövegeket itt tesszük át en/hu párra).
4. **Scenes + Fixtures** (~200 szöveg, a legtöbb).
5. **Chases + Smart Program + core/widgets** (dock, panelek, pickerek, dropout, Movement sáv).
5b. **Song Show** (`features/songs` + `core/song` státuszok, ~100 szöveg) — új lépés.
6. **Logikai szövegek** (enum label-ek, hibaüzenetek típusosítása) — külön PR, mert a modell/állapot réteget érinti.
7. **Átfutás:** `grep` rá a maradék hardcode-olt `Text('`/`label:`/`tooltip:` literálokra; opcionális lint (`flutter_lints` + egyedi ellenőrző szkript CI-ben), hogy új szöveg ne szivárogjon be; HU szöveg-átnézés a felhasználóval; vizuális ellenőrzés Tab S6 Lite-on és P20 Pro-n (a magyar szövegek hosszabbak → elrendezés/overflow a kis kijelzőn, főleg a nav-sávon és a SegmentedButton-okon).

## Döntések (2026-10-09, felhasználó)

- Szakkifejezések (Hold, Fade, Beat Sync, Bank, Chase, Scene, Layer, Art-Net, DMX, Smart Program stb.) **angolul maradnak** a magyar felületen is.
- Első indításkor az app **követi a rendszernyelvet** (hu → magyar, minden más → angol); a Setup-ban felülbírálható.
- ~~A fejlesztés egyelőre nem indul~~ → **2026-11-09: a felhasználó kérte az indítást.**

## Nyitott döntések (a felhasználótól)

- Exportált fájlok (bank/chase export, projekt) tartalma nyelvfüggetlen marad (igen — csak adat).

## Állapot (lépésenként)

| # | Lépés | Állapot |
|---|---|---|
| 1 | Alap + Setup nyelvválasztó | kész (2026-11-09, v1.45.0) |
| 2 | Shell, Setup, Dashboard, Files, Manual, DMX térkép | kész (2026-11-09, v1.45.0) — az enum-címkék (pl. `OutputProtocol`, `BeatSourceKind`, `ControlDockPosition`) és a `zoneLabel` még angolok, ezek a 6. lépésben jönnek |
| 3 | Banks + Layers (+ Movement FX szerkesztő, Program generátor) | kész (2026-11-09, v1.45.1) — a Layers korábbi beégetett magyar szövegei most angolul is megvannak |
| 4 | Scenes + Fixtures | — |
| 5 | Chases, Smart Program, core/widgets | — |
| 5b | Song Show | — |
| 6 | Logikai szövegek | — |
| 7 | Átfutás, lint, eszközös ellenőrzés | — |

## Megvalósítási megjegyzések (2026-11-09)

- Generált kód: `app/lib/l10n/generated/` (gitignore-olva, a `flutter pub get`/build újragenerálja; kézzel: `flutter gen-l10n`).
- Használat: `import '…/l10n/l10n.dart';` majd `context.l10n.kulcs`. Az extension **angolra esik vissza**, ha nincs delegate (pl. tesztben csupasz `MaterialApp`) — ezért a meglévő tesztek változtatás nélkül futnak, és nem kell mindenhol delegate-et bekötni.
- Kulcsnév: terület-prefix (`nav…`, `settings…`, `dash…`, `files…`, `manual…`, `dmxMap…`, `stage…`), közös gombok: `common…` (Cancel, Save, Done, Empty, All, Blackout, No music, Name, Port).
- Többes szám ICU-val (`dashChaseSteps`, `dashCueCount`); magyarban nincs többes alak a szám után.
- A `DmxControllerApp` kapott egy `home` paramétert (alapból `SplashScreen`), hogy a teszt a valódi lokalizációs bekötéssel tudja pumpálni a shellt.
- Teszt: `test/language_switch_test.dart` (rendszernyelv-feloldás, azonnali váltás + mentés, Setup magyarul 360 px és 1340 px széles kijelzőn overflow nélkül).

## Hogyan vegyük elő

Ez a fájl a forrás. Indításkor: olvasd el a `DECISIONS.md`-t is, majd az 1. lépéssel kezdj; minden lépés után frissítsd az itt lévő státuszt.
