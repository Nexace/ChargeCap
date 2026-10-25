# ChargeCap

<img src="artwork/chargecap-128.png" width="80" alt="ChargeCap icon">

A small native macOS menu bar app for Apple's built-in battery charge limit.

Click the battery icon to open a frosted panel directly beneath it. The slider snaps to **80%, 85%, 90%, 95%, or 100%**. Releasing the slider saves the selection and reads the setting back from macOS. Arrow keys and accessibility actions adjust it in 5% steps. At 100%, the panel offers the real **Optimized Battery Charging** switch.

Hover over the icon for about half a second to see a rounded frosted card with **ChargeCap**, the current charge limit, and **Click to adjust the charge limit**. It uses Apple’s native frosted-menu material (`NSVisualEffectView`) with ScrollToggle’s three-line layout, fonts, spacing, and 12-point corners. This lighter material replaces the more expensive refractive Liquid Glass effect. The transparent text surface lets the system frosting show through. Leaving the icon or clicking dismisses the card; it also has an eight-second timeout. Hover reads the current macOS limit and never writes it.

Settings opens Battery settings. Click outside, press Escape, or click the icon again to dismiss the panel. The selected limit is stored by macOS and continues to apply after ChargeCap quits.

## Performance

The goal remains **under 10 MB**, in decimal app-process physical footprint. The final native frosted-menu build measured **9.192 MB idle after cleanup** and an **11.126 MB kernel lifetime peak** across 20 hover cards, 20 slider panels, all five visual limit states, and four longer idle pauses. This bounded test meets the idle target but still fails a strict under-10-MB peak target. The previous refractive glass build measured 10.831 MB idle / 13.043 MB peak in the same full stress exercise, and a separate normal installed session reached 13.911 MB current / 16.008 MB peak. See `Verification.log` and `research/Frosted-Menu-Stress.log`. There is one app process; no UI memory is moved into a helper or hidden process.

The app uses Objective-C/AppKit, with no bundled runtime, web view, network requests, privileged helper, or secondary application process. Normal operation has no polling timer or animation loop. It sleeps between native events, reads state on hover/open or setting changes, previews slider dragging locally, and writes only on release.

Small reusable BGRA8 IOSurfaces avoid AppKit’s larger vector-rendering caches. After both panels remain closed for two seconds, the app releases their drawing surfaces, closes their windows, releases the battery client, and makes one allocator pressure-relief request. Fast reopening cancels this cleanup and reuses the existing UI. The slider panel uses native compositor blur. The hover uses the system’s native behind-window menu frosting; its shadow remains disabled, and macOS handles Reduce Transparency. Scoped autorelease pools bound temporary UI allocations. Cleanup also detaches the hidden native effect hierarchy before closing its window. Application measurements include app-owned graphics allocations; shared WindowServer costs are separate.

The final installed app’s 20-second sample averaged **0.00013% of one CPU core**, with 8.389 MB current footprint and an 8.979 MB startup lifetime peak. This sample was taken before a confirmed real interaction on that restarted process; it is not post-use evidence. An earlier installed menu-material build measured 10.339 MB after ordinary use. The full repeated-use result above is from the final source. Raw logs and all rejected cleanup/allocator probes are in `research/Frosted-Menu-CPU.log` and `research/Frosted-Menu-Investigation.md`.

## Build

Requires Apple Silicon, macOS 26.4 or newer, and Apple's command-line developer tools. The verified machine is a MacBook Air M5 running macOS 27.0.1.

```sh
./build.sh
./test.sh
open ChargeCap.app
```

The build generates the icon from native drawing code and signs the bundle locally. The installed login item on this Mac points to `~/Applications/ChargeCap.app`. After quitting the running app, refresh that copy with `ditto ChargeCap.app "$HOME/Applications/ChargeCap.app"` and open it again; keep the same path to preserve the login item. Its native icon resource includes crisp menu/Finder sizes up to 128 physical pixels to keep startup decoding small. The app has no Dock icon. macOS can manage automatic startup through System Settings → General → Login Items.

```sh
./ChargeCap.app/Contents/MacOS/ChargeCap --diagnose
```

`--diagnose` reads settings without changing them. `--profile` opens the panel for a read-only observation. `CHARGECAP_PROFILE_KEY=1` gives the slider focus; `CHARGECAP_PROFILE_CYCLES=1` exercises five reopenings. `--verify` first exercises the hover card, temporarily changes the five limits and optimized charging, restores the recorded originals, waits for idle cleanup, and exits nonzero if functionality or the under-10-MB lifetime-peak goal fails. The current build passes its functional checks but reports FAIL for that peak goal; do not interpret the failure as a failed battery restoration. Run live verification when no other battery utility is changing settings. Unit checks include an environment-specific private-framework capability assertion.

For a read-only repeated UI exercise, run `./research/run-stress.sh /absolute/path/UI-Stress.log`. It shows temporary panels and all five visual limit states without sending any charging writes. Quit ChargeCap first to avoid a second status icon during this check.

Memory uses decimal MB from `TASK_VM_INFO.phys_footprint`; the kernel's lifetime ledger peak includes transient allocations. No memory polling timer is needed. CPU can be measured separately on a normal running instance:

```sh
xcrun clang -Os -Wall -Wextra -Werror research/cpu-measure.c -o /tmp/chargecap-cpu
/tmp/chargecap-cpu PID 15
```

## Compatibility and verification

Charge writes validate the available options, guard the inspected arm64 method signatures, and check independent readback. Tests cover rejected writes, unavailable controls, native ABI mismatches, slider snapping, preview isolation, keyboard and accessibility actions, the conditional optimized switch, and restoration of the original settings.

Battery control uses private PowerUI interfaces; the backdrop also uses a private macOS API. OS updates or unsupported hardware can make either unavailable. Physical charging behavior, other Mac models, actual logout/login, and display transitions are separate from software readback checks and have not all been physically verified.

`Preview.png`, `Preview-100.png`, and `Preview-Hover.png` show earlier layout renders; they do not capture live desktop blur or the current native hover material. Physical pointer hover and the earlier Liquid Glass card were confirmed by the user after relaunch. The lighter menu-material card was installed for visual feedback; that feedback was still pending when the measurements were recorded. The icon is generated by `artwork/draw-icon.m`. Graphify's source graph and report are retained locally in `graphify-out/`, with all extracted relationships preserved. The graph maps Objective-C class, method, and import structure; static C helpers are checked in the source and tests.
