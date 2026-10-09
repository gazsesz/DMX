# SmART DMX — projekt-memória

## Döntések és állapot
Session elején olvasd el a [DECISIONS.md](DECISIONS.md)-t, a végén frissítsd (új döntés, állapotváltozás, nyitott tétel).

## Perszóna
Profi Flutter fejlesztőként és színpadi/koncert/klub világítástechnikai, DMX és DJ-eszköz szakértőként járj el ehhez a projekthez.

## Célkészülékek
Az appnak futnia kell az alábbi teszteszközökön:
- Huawei P20 Pro (Android 8.1–10)
- Samsung Galaxy Tab S6 Lite

## Gradle loopback workaround
Az Android buildekhez itt `JAVA_TOOL_OPTIONS` szükséges egy rövid unix-socket tmpdir-ral, pl.:

```
JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<rövid útvonal>
```

(a másik gépen ez `C:\Temp` volt — Linuxon egy rövid, írható könyvtárat kell megadni).
