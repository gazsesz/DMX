# SmART DMX — döntések és állapot

Élő napló az új sessionöknek. **Minden session elején olvasd el, a végén frissítsd** (új döntés, állapotváltozás, lezárt/nyitott tétel). Ami a kódból vagy a git logból kiolvasható, azt ne ide írd — csak a *miért*-et és a nem nyilvánvaló állapotot.

_Utolsó frissítés: 2026-10-09 · app verzió: v1.29.0 (main: a815562)_

## Munkamód (állandó szabályok)
- Chat magyarul, minden státuszsor is; kód, komment, commit angolul.
- Minden Windows/tablet kiszállítás előtt emeld a `app/pubspec.yaml` verzióját (név + build szám), commitold a munkával, és említsd a jelentésben.
- Valódi eszközre (Tab S6 Lite, P20 Pro) telepítés előtt **figyelmeztesd a felhasználót**: az uninstall–reinstall (applicationId/aláírás eltérés) letörli az app adatait, és a tablet valódi showkon fut. Előbb Files → Export mentés. (Előzmény: az `applicationId` átnevezése `com.energiaborze…` → `com.gazsesz…` egyszer adatvesztést okozott.)
- Munka mindig a GitHubon lévő legfrissebb `main`-ből induljon (`git fetch`, majd fast-forward).
- Android build: `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<rövid útvonal>` (Windows-on `C:\Temp`).
- Célkészülékek: Huawei P20 Pro (Android 8.1–10), Samsung Galaxy Tab S6 Lite.

## Termékelvek
- **Egyszerű kezelés** a fő szempont: minden új felület legyen additív (ha nem használják, semmi nem változik). A felhasználó aggódott a bonyolultság miatt.
- Két használati eset: (1) csak DJ, élő operátor nélkül → gyorsabb előre szerkesztés; (2) külön fénytechnikus → gyors élő váltás.
- Érintőképernyős konzol: nincs hover, a neveknek láthatónak kell lenniük (nem csak tooltip).

## Architektúra-döntések
- Jelenetek csatornákat szelektíven vezérelnek, nem a teljes fixture-t.
- Lejátszási rétegek (layers) egymástól függetlenek; megosztott csatornákon arbitráció van. Chase vagy Smart Program indítása minden réteget átvesz (amihez nincs tartalma, elcsendesedik) — v1.25.0.
- Réteg-időzítés chase-ben és Smart Programban: follow dock / on beat / free-running (v1.23–1.24).
- Dimmer dropout réteg (v1.27–1.28): sötét villanások kiválasztott rétegekre/fixture-ökre, projekttel mentve.
- Fixture-csoportok **projekt-szintűek** (`ProjectData`), nem app-szintű pref, mert a fixture id csak egy patch-en belül értelmes.
- Mentett színek: `SavedColor {name, rgb}`, a név mindig opcionális (hex a fallback), átnevezés csak hosszú nyomásra — ezt megígértük a felhasználónak.
- Beat forrás: v1.29.0-tól rkbx_link OSC Wi-Fi-n (`core/audio/osc_beat_source.dart`).

## Folyamatban / nyitott
- **Csoportok + mentett színek:** a szerkesztői fázis kész (2026-09-20; csak lista alapú csoportválasztó, a layout/lasso szándékosan kimaradt). **A fázis 2 hiányzik:** élő Csoport×Szín gyorsalkalmazó sáv (Control panel / `trigger_actions.dart` / `momentary_fx_providers.dart`). A felhasználó sorrendje: előbb szerkesztés, aztán élő sáv.
- Vizuálisan Claude nem ellenőrizte; smoke teszt: `flutter run -d windows`.
- A tervezési indoklás és mockupok: `DMX Piackép.html` (repo gyökér; menetközben használt mockup-fájl, nem piackutatás).

## Verifikáció (utolsó ismert)
- `flutter analyze` tiszta, `flutter test` 176/176 (a csoport/szín munka idején; azóta új teszt: `osc_beat_source_test.dart`).
