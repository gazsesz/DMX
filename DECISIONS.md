# SmART DMX — döntések és állapot

Élő napló az új sessionöknek. **Minden session elején olvasd el, a végén frissítsd** (új döntés, állapotváltozás, lezárt/nyitott tétel). Ami a kódból vagy a git logból kiolvasható, azt ne ide írd — csak a *miért*-et és a nem nyilvánvaló állapotot.

_Utolsó frissítés: 2026-10-12 · app verzió: v1.37.0 (branch claude/movement-fx, az 1.32.x-et is tartalmazza)_

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
- Dropout fade out (v1.30) + fade in (v1.31, `fadeInMs`, alap 0, a sötét után ugyanígy visszahalkít): `fadeOutMs` (alap 0 = kemény vágás) a sötét előtt lineárisan halkít; a `dimChannels` hook gain-t ad csatornánként, a 30 Hz refresh rajzolja a lépcsőket. A köz-számításba beleszámít.
- Bank "Edit slots" (v1.30): a hosszú nyomás húzást (LongPressDraggable→DragTarget, `moveSlot`) indít a jelenet-szerkesztő helyett; a szerkesztés a mód kikapcsolásakor marad a hosszú nyomás.
- Jelenet duplikálás a slot menüben két módon (v1.31.1): következő szabad slotba (`placeAfter`), vagy közvetlenül a következő lépésre (`insertAfter`): a többi eggyel odébb tolódik az első üres slotig, üres hely híján a bank nő eggyel; a lépés időzítése vele megy.
- v1.32.0: (1) mozgófej XY pad rácsra ugrás (`PadSnap`: Free/1/½/¼ a 45°-os rácscellából, csak coarse módban, a rács a mozgástartomány közepéhez horgonyzott); (2) üres köztes slot törölhető (`removeEmptySlot`, csak üres, az utolsó slot marad); (3) bank másolásnál kérdés: jelenetek klónozása (alap) vagy közös használata (`duplicateBankAsking`); (4) dropout távvezérlő végpont: `/dropout?on=1/0`, a Wear OS menüben és a `/status`-ban is.
- Bank képernyő Stop (v1.32.1): a bankot minden rétegről leállítja (`stopEverywhere`), nem csak a Layer 1-ről; a gomb Stop, ha a bank bármelyik rétegen fut.
- Fixture-csoportok **projekt-szintűek** (`ProjectData`), nem app-szintű pref, mert a fixture id csak egy patch-en belül értelmes.
- Mentett színek: `SavedColor {name, rgb}`, a név mindig opcionális (hex a fallback), átnevezés csak hosszú nyomásra — ezt megígértük a felhasználónak.
- Beat forrás: v1.29.0-tól rkbx_link OSC Wi-Fi-n (`core/audio/osc_beat_source.dart`).

## Folyamatban / nyitott
- **Kétnyelvűsítés (EN+HU, nyelvváltó a Setup oldalon):** felmérés és terv kész, a kivitelezés még nem indult — lásd [I18N_PLAN.md](I18N_PLAN.md) (döntések rögzítve; a fejlesztés a felhasználó jelzésére indul).
- **Csoportok + mentett színek:** a szerkesztői fázis kész (2026-09-20; csak lista alapú csoportválasztó, a layout/lasso szándékosan kimaradt). **A fázis 2 hiányzik:** élő Csoport×Szín gyorsalkalmazó sáv (Control panel / `trigger_actions.dart` / `momentary_fx_providers.dart`). A felhasználó sorrendje: előbb szerkesztés, aztán élő sáv.
- Vizuálisan Claude nem ellenőrizte; smoke teszt: `flutter run -d windows`.
- A tervezési indoklás és mockupok: `DMX Piackép.html` (repo gyökér; menetközben használt mockup-fájl, nem piackutatás).

## Verifikáció (utolsó ismert)
- `flutter analyze` tiszta, `flutter test` 176/176 (a csoport/szín munka idején; azóta új teszt: `osc_beat_source_test.dart`).

## Movement FX (v1.33.0, branch `claude/movement-fx`)
- A mozgás **paraméteres, élő számolású bank** (`Bank.fx`, `models/movement_fx.dart`), nem jelenet-sorozat: alak, méret, sebesség (szabad vagy beat-hez kötött), irány, fázis-szórás, cél csoport/fixture. Terv és indoklás: [MOVEMENT_FX_PLAN.md](MOVEMENT_FX_PLAN.md).
- Lejátszás a `ChasePlayer`-ben (`_runFx`, 25 ms tick, csak pan/tilt csatornákat ír), ezért chase, smart chase, dashboard, layer picker változtatás nélkül használja. A számolás `core/movement/movement_engine.dart` (tiszta függvények, tesztelt).
- Döntések a felhasználótól: (1) FX közben nem nyúlunk a pan/tilt speed csatornához, legfeljebb blackoutnál (még nincs megvalósítva); (2) FX lépések közt a fázis **folytonos**, chase-lépésenként átállítható „Start the lap from the top” (`ChaseStep.fxRestart`).
- Idő: önállóan futtatott FX-bank és Smart Program célpont **hold = 0 = végtelen**; chase-lépésben a hold a futási idő (alap 8 s), a fade a „glide” a pályára. Szerkesztés élő: a futó bank a `liveBanks`-ből veszi az új paramétert.
- Nyitott: a régi Generate Program mozgás-effektjeinek kivezetése/átkötése; blackout-kori speed csatorna; valós fejeken tesztelni (Tab S6 Lite, P20 Pro) — a gépen csak unit/widget teszt futott.
- **Look (v1.34.0):** egy FX-bankhoz opcionálisan jelenet-bank rendelhető (`MovementFx.lookBankId`): szín/gobo/dimmer stb. fut a pálya mellett ugyanazon a rétegen, a pan/tilt-jét a pálya által mozgatott fejeknél eldobjuk. Időzítés: alapból a dock Hold/Fade + Beat Sync (½× kivételével 1 beat = 1 lépés; 2×/Flash itt 1×-ként viselkedik), vagy „Own timing” (saját hold/fade). Külön rétegen futó, csak színes bank továbbra is megy (rétegek függetlenek).
- **DMX channel map (v1.35.0):** Settings → „DMX channel map”: univerzumonként 32×16-os rács a patch csatornakiosztásával (fixture-ök összefüggő blokkként, átfedés pirosan, első szabad cím, koppintásra a fixture csatornalistája). Csak olvasható nézet, nem szerkeszt patch-et.
- **Movement FX bővítés (v1.36.0):** új alakok: Random (sima kóborlás), Random jumps (ugrálás, 1/8 lap), Hold (középen marad); új „Fan” paraméter (fok/fej pan/tilt térben, méter/fej stage térben). A fejenkénti eltolás egyetlen függvényben számolódik (`movementOffset`), ezt használja a lejátszó és az **élő előnézet** is (mozgó pontok farokkal, fejenként egy szín, max 6 fej, beat-lock 120 BPM-en mutatva). Light Rider kereke (ikonok alapján, nem megerősítve): hiányzott a dobókocka=Random, célkereszt=Center/Hold, FAN gomb; a belső kerék jelentése ismeretlen.
- **Movement strip (v1.37.0):** élő Size / Speed / Shift / Smooth gombok a futó Movement FX-re (`MovementLive`, `movementLiveProvider`), a shellben a tartalom alatt, a Live Stage csík fölött; Settings kapcsoló + app-bar gomb (alap: BE, `dock.movementBar`). A bankot nem módosítják: Size/Speed szorzó, Shift hozzáadódik a „wave across heads”-hez, Smooth = a fejek késleltetett követése (0–1,5 s; élesre vágott mozgást kerekít, ugrást siklássá tesz). **Nem mentődnek** (se app, se projekt), „Reset” gomb és címkén dupla koppintás állít vissza; bankváltáskor NEM nullázódnak. Beat-locked FX-nél Speed≠1 esetén a beat csak a tempót frissíti, a fázist nem húzza vissza a rácsra. Remote: `/fx?size=&speed=&shift=&smooth=` (bármely részhalmaz), `/fx?reset=1`, a `/status`-ban `movement`, a Wear menüben „Movement” csoport fix lépésekkel. A Light Rider Fade gomb jelentése bizonytalan — a „Smooth” a legvalószínűbb megfelelője.
