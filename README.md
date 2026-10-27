# Rebel Base — retro sci-fi vector watch face for Garmin

Three styles, switchable on the watch:

- **Orbit tracker** — a gas giant curves in from the left edge, with a day/night line that follows the real sunrise and sunset at your location. Each hour a hollow wireframe moon, marked with tonight's actual moon phase, crosses the planet's face from the far left toward a range marker just past the planet's edge; IN RANGE counts the minutes until it has fully cleared the edge (accent color in the last 5). During minute :00 it sits locked on the marker as a filled disc with a cross and the countdown reads NOW. A "+" field scans one column per second. Time, date, weather and your three data fields sit on the right.
- **Targeting** — a wireframe trench rushing toward a reticle. The countdown under it is **steps left to your daily goal**; at zero a pulsing burst surrounds the reticle and it reads TARGET LOCKED. Side scales show step progress (left) and battery (right).
- **Radar** — a sweep turns once a minute. The hour is a blip on the inner ring, the minute an accent blip on the outer ring, and each unread notification appears as a contact that brightens when the sweep passes it.

In targeting and radar, the 60 bezel ticks light up as you approach your step goal.

**Press and hold to open:** press and hold a readout for about a second (heart rate, Body Battery, weather, steps, notifications…) to open the matching watch widget. Distance has no widget, so it does nothing.

**Always-on:** thin digits plus faint outlines of the current style (planet edge and moon, trench edges, or radar rings), shifted a few pixels each minute to protect the AMOLED screen.

`preview.png` shows each style, the goal burst, and the three always-on modes.

**Languages:** English and Polish. The face, the on-watch Customize menu and the phone settings follow the watch's language. Text lives in `resources/strings/strings.xml` (English) and `resources-pol/strings/strings.xml` (Polish); to add a language, copy the English file into `resources-<code>/strings/` (for example `resources-deu` for German), translate it, and add `<iq:language>` to `manifest.xml`.

## Build and run

1. Install the **Connect IQ SDK Manager** from developer.garmin.com/connect-iq, download the latest SDK and the **Forerunner 965** device.
2. Install **VS Code** and the **Monkey C** extension (by Garmin).
3. In VS Code: Command Palette → **Monkey C: Generate a Developer Key** (once).
4. Open this folder (`VectorRun`) in VS Code.
5. Try it in the simulator: **Run → Run Without Debugging**, pick `fr965`.
   - **Settings → Low Power Mode** toggles always-on mode.
   - **Simulation → Activity Data** fakes steps, heart rate, etc.
   - The simulator's weather settings let you try different conditions.
   - **Settings → Language → Polish** shows the Polish text.
   - Press and hold a readout to test opening its widget (Garmin watch faces get touch-and-hold, not quick taps).

## Put it on the watch

1. Command Palette → **Monkey C: Build for Device** → `fr965`. This produces `VectorRun.prg`.
2. Connect the watch by USB. On Windows it appears as a drive; on a Mac use OpenMTP (the 965 uses MTP).
3. Copy `VectorRun.prg` into `GARMIN/APPS/` on the watch and unplug.
4. On the watch: hold **UP** (or long-press the watch face) → **Watch Face** → scroll to **Rebel Base**.

Weather, sunrise/sunset and Body Battery come from the watch itself; weather needs the phone connected to Garmin Connect now and then. Until the watch has a location, day/night uses 06:00–18:00.

## Settings

On the watch: long-press the face → **Watch Face** → Rebel Base → **Customize**. Each item opens a list.

| Setting | Choices | Default |
|---|---|---|
| Style | Orbit tracker, Targeting, Radar | Orbit tracker |
| Main color | 10 colors — time, text, lines | Green |
| Accent color | 10 colors — markers and warnings | Red |
| Planet color | 10 colors — gas giant, auto-shaded | Red |
| Field 1 / 2 / 3 | Heart rate, Battery, Body Battery, Stress, Calories, Distance, Floors, Notifications, Steps, None | HR / Battery / Steps |

Where the fields appear: in orbit tracker, fields 1 and 2 share a line and field 3 is below. In targeting and radar, fields 1 and 2 are left and right, field 3 is lower left, and weather is lower right.

Phone settings through the Connect IQ app only work for store installs.

## Code map

- `source/VectorRunView.mc` — all drawing, data reading and tap hit-testing. Seven-segment digits are drawn with lines (`drawDigit`), so no custom font is needed. Layout values are for 454 px and pass through `s()` to scale.
- `source/VectorRunDelegate.mc` — tap handling (opens widgets via Complications).
- `source/VectorSettings.mc` — on-watch settings menu and list picker.
- `source/Fields.mc` — field types, names, defaults, widget mapping.
- `source/Palette.mc` — colors and the `shade()` helper.
- `source/VectorRunApp.mc` — app entry point and `getProp` helper.
- `resources/settings/` — the properties and phone-settings lists.

Permissions in `manifest.xml`: **SensorHistory** (Body Battery, stress) and **ComplicationSubscriber** (press-and-hold to open widgets).

To add a color or field type, append it to the list in `Palette.mc` / `Fields.mc` and to the matching lists in `resources/settings/settings.xml` (stored values are list positions, so always add at the end).

If you compile with an older SDK (before 7.x) and get errors on the `[Views] or [Views, InputDelegates]` return types, change them to `as Array<Views or InputDelegates>`.
