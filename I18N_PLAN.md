# Kétnyelvűsítés (EN + HU) — felmérés és terv

_Készült: 2026-10-09 · alap: v1.30.1 · státusz: **még nem kezdődött el**, csak terv._

Cél: az app angol és magyar nyelven fusson; a nyelv a **Setup** oldalon váltható, azonnal (újraindítás nélkül), és megmarad az újraindítás után.

## Felmérés (mennyi munka)

- 132 Dart fájl, ~29 800 sor. Nincs `MaterialApp.locale`, nincs `flutter_localizations`/`intl`, nincs `l10n.yaml`. A beállításokhoz van `shared_preferences`.
- Felhasználói szöveg: kb. **600–700 szöveg** (317 `Text('…')` literál + címkék, tooltipek, hintek, SnackBar-ok, dialógusok). Nagy része `lib/features`-ben:
  | Terület | ~szöveg |
  |---|---|
  | scenes | 102 |
  | fixtures | 101 |
  | banks | 90 |
  | core/widgets | 81 |
  | chases | 75 |
  | settings | 40 |
  | layers | 26 |
  | files, dashboard | 17–17 |
  | manual_control, shell | 8, 8 (nav címkék) |
- **Logikában élő szöveg (~190 hely):** `models/`, `state/`, `core/` — enum `label` getterek (pl. `BeatRate`, `FlashColorMode`), és olyan függvények, amik hibaüzenetet `String`-ként adnak vissza a UI-nak (`runBankOnLayer` → `String? error`, `setEnabled` hibái, MIDI/OSC/mikrofon státuszok). Ezek nem kapnak `BuildContext`-et → külön megoldás kell (lásd lent).
- **Már most kevert nyelvű:** magyar szövegek vannak a `layers/dropout_controls.dart`, `dimmer_dropout_card.dart`, `layers_screen.dart`, `layer_picker_sheet.dart`, `smart_program_editor_screen.dart`, `chase_editor_screen.dart`, `pan_tilt_pad.dart`, `control_panel.dart`, `control_dock.dart` fájlokban (~35 sor). Ezeket **angolra is le kell fordítani** (az angol lesz az alap/kulcs-forrás).
- **Nem fordítandó, de ne rontsuk el:**
  - `core/widgets/wheel_looks.dart` és `models/fixture_channel.dart`: a fixture-csatornák neveit felismerő kulcsszó-listák (EN+HU kulcsszavak). Ezek *bemenet-felismerés*, nem UI szöveg → maradnak.
  - Fixture-könyvtár (`assets/fixtures/`) neve/csatornanevei gyártói adatok → maradnak.
  - Felhasználó által adott nevek (jelenet, bank, chase, csoport, szín) → maradnak. **Alapértelmezett nevek** (új bank „Bank 1”, „Beat Flash”, „Scene …”) viszont a *létrehozáskor* lokalizálódnak és onnantól sima adat.
  - Zenei/DMX szakkifejezések (Hold, Fade, Beat Sync, Art-Net, DMX, Smart Program) — **döntés kell**: a magyar fordításban maradjanak-e angolul (a színpadi szakzsargon magyarul is így megy). Javaslat: maradnak.
- Tesztek: ~10 widget-teszt `find.text('…')`-tel angol szövegre keres. A teszt-locale legyen mindig `en` → ezek nem törnek, ha az `en` az alapértelmezett és a tesztek explicit `Locale('en')`-t kapnak.

**Becslés:** ~2–3 munkanap fejlesztői munka, mert a mechanikus kinyerés + a ~190 logikai szöveg átvezetése a lassú rész; a fordítás maga (EN→HU ~700 sor) gyors. Kockázat: alacsony, additív változás; a legnagyobb a sok fájl érintése (merge-konfliktus-veszély → kis, területenkénti PR-ok).

## Megközelítés

**Flutter hivatalos `gen_l10n` (ARB fájlok)** — nincs külső lib-függés a `flutter_localizations` + `intl` mellett.

1. `pubspec.yaml`: `flutter_localizations` (sdk: flutter), `intl`, `flutter: generate: true`; `l10n.yaml` (`arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-localization-file: app_localizations.dart`, `nullable-getter: false`).
2. `lib/l10n/app_en.arb` (sablon, angol) + `app_hu.arb`. Kulcsok terület-prefixszel: `banksEditSlots`, `dropoutFadeOut`, `settingsLanguage`… Paraméteres/többes számú szövegek ICU-val (`{count, plural, …}`: pl. „N step(s)”, „N/M scenes”, „N active”). A magyarban a ragozás miatt a mondatokat ne összefűzéssel, hanem teljes mondatként paraméterezve kezeljük.
3. `lib/app.dart`: `MaterialApp` kap `localizationsDelegates`, `supportedLocales: [en, hu]`, `locale:` a nyelv-providerből.
4. **Nyelv-provider:** `localeProvider` (`StateNotifier<Locale?>`), `SharedPreferences`-ben mentve (`app_locale`: `en`/`hu`/`system`). Alapértelmezés: **rendszernyelv, ha hu vagy en, különben en**. Appon belüli váltáskor azonnal újraépül (MaterialApp.locale).
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
5. **Chases + Smart Program + core/widgets** (dock, panelek, pickerek, dropout).
6. **Logikai szövegek** (enum label-ek, hibaüzenetek típusosítása) — külön PR, mert a modell/állapot réteget érinti.
7. **Átfutás:** `grep` rá a maradék hardcode-olt `Text('`/`label:`/`tooltip:` literálokra; opcionális lint (`flutter_lints` + egyedi ellenőrző szkript CI-ben), hogy új szöveg ne szivárogjon be; HU szöveg-átnézés a felhasználóval; vizuális ellenőrzés Tab S6 Lite-on és P20 Pro-n (a magyar szövegek hosszabbak → elrendezés/overflow a kis kijelzőn, főleg a nav-sávon és a SegmentedButton-okon).

## Döntések (2026-10-09, felhasználó)

- Szakkifejezések (Hold, Fade, Beat Sync, Bank, Chase, Scene, Layer, Art-Net, DMX, Smart Program stb.) **angolul maradnak** a magyar felületen is.
- Első indításkor az app **követi a rendszernyelvet** (hu → magyar, minden más → angol); a Setup-ban felülbírálható.
- A fejlesztés **egyelőre nem indul**, a terv várakozik.

## Nyitott döntések (a felhasználótól)

- Exportált fájlok (bank/chase export, projekt) tartalma nyelvfüggetlen marad (igen — csak adat).

## Hogyan vegyük elő

Ez a fájl a forrás. Indításkor: olvasd el a `DECISIONS.md`-t is, majd az 1. lépéssel kezdj; minden lépés után frissítsd az itt lévő státuszt.
