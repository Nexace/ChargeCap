# Backdrop renderer investigation

The slider panel uses native per-window compositor blur with a translucent rounded surface and highlight rim. The current hover card instead uses Apple’s regular NSGlassEffectView material, matching ScrollToggle. It resolves `SLSMainConnectionID` and `SLSSetWindowBackgroundBlurRadius` dynamically, checks the result, and falls back to NSVisualEffectView if unavailable. Reduce Transparency uses an opaque background. No additional application process or renderer is started.

The initial NSVisualEffectView hierarchy allocated approximately 88 MB of app-owned graphics memory in one focused-panel test. See `Before-Graphics.txt`. A read-only compositor-blur observation avoided that allocation; see `After-Graphics.txt`. This observation was not a permanent memory guarantee: later full-redraw tests reproduced substantial graphics allocations.

Independent probes isolated another expensive combination: `canDrawSubviewsIntoLayer=YES` with a gradient slider peaked at 74.761 MB, while ordinary layers with the same gradient peaked at 9.569 MB. The final renderer avoids consolidated layer drawing, gradients and Gaussian shadows in its controls. A flat thumb retains its translucent highlight rim. The complete flat UI in one read-only probe peaked at 9.733 MB. Full redraws still caused roughly 59 MB peaks with that vector-rendering path. It was replaced with CPU drawing into reusable native IOSurfaces for the panel, slider, and small controls. Layers reference those BGRA8 surfaces directly, avoiding bitmap copy/decompression buffers. Drawing occurs only on UI changes and uses the window backing scale for crisp text. The final compact 256 × 200 panel peaked at 10.126 MB during full verification through normal macOS LaunchServices startup. A direct executable launch previously peaked at 9.831 MB; the normal-launch measurement is the release figure.

The application footprint includes its owned graphics allocations. WindowServer is macOS's shared compositor; its CPU and RAM are separate from these application-process measurements. These results do not claim a system-wide cost below 10 MB.

The same blur interface is used by the primary [winit project](https://github.com/rust-windowing/winit/blob/master/winit/src/lib.rs) behind its private-apple-apis feature. Battery controls separately use guarded private PowerUI interfaces. These private APIs can change with macOS updates.

The surface allocator checks allocation, dimensions, and lock failures. Unit checks inspect actual surface pixels for rounded transparency and the white slider thumb. One surface per control keeps memory small; additional buffering would be appropriate if visible tearing is observed. macOS resource usage can vary with system and display state, so a bounded test does not impose a permanent OS memory ceiling.

The final build omits an unrequested in-app login toggle and ServiceManagement queries. Native icon resources are capped at 128 physical pixels to keep decoding small; larger original artwork remains reproducible from its vector drawing source. The app uses process-local MallocSpaceEfficient=1, MallocMaxMagazines=1, MallocNanoZone=0 and MallocMediumZone=0. No system-wide allocator defaults are changed.


## Hover card and RAM follow-up — 2026-10-25

The hover card follows ScrollToggle’s 12-point corners/padding and 13-point bold title, 13-point status, and 12-point secondary action. It uses the same CPU-to-IOSurface renderer and native compositor blur as the slider panel, avoiding a second UI process. Hosted status-item mouse-enter/exit tracking schedules one half-second show, cancels on exit/click, and has an eight-second dismissal timeout. There is no pointer polling.

Matched read-only 20-hover/20-slider stress runs differed only in the hover window’s native shadow: enabled retained 10.290 MB after cleanup; disabled retained 8.996 MB. Peaks were 11.060 and 11.076 MB respectively. Disabling the shadow was retained for its idle saving; the lifetime-peak target still fails. Panels and their surfaces are released after a two-second quiet period rather than during fast reopening. No cleanup is performed while either panel is visible.

Other experiments were rejected: combining all control drawing into one panel surface reached 11.191 MB without hover and 13.911 MB in an early hover/reallocation candidate. Matched eight-cycle read-only probes measured original text/icon rendering at 11.633 MB peak, CoreText at 12.453 MB, and a CPU-created status image at 11.650 MB. An allocator retained-region flag reached 11.257 MB in that small probe but did not improve the actual hover candidate and was removed. The existing allocator flags remain process-local.

Native PowerUISmartChargeClient lifecycle metadata and dealloc inspection showed that releasing the client already invalidates its NSXPCConnection. No extra private lifecycle calls were added. The current client is released during idle cleanup and recreated when needed.

`research/stress-ui.m` imports the actual product UI and locally selects visual states without calling charging-change actions. `run-stress.sh` builds a temporary signed app and starts it through LaunchServices. Its 40 visual steps include longer pauses to exercise resource disposal and recreation. The final product’s normal-launch functional verification independently writes and reads back the real options, then restores the saved originals.

The hover layout was inspected in light/dark CPU renders. Native computer-use capture timed out, so these renders are not evidence of live desktop blur or a physical pointer-enter test. Automated checks cover the delayed event-handler path, cancellation, fresh reads for all five limits, unavailable state, zero hover writes, surface pixels, and cleanup/recreation. The installed version still needs a human pointer-hover check on the hosted icon.


## Native hover material follow-up

The user reported no card from the old running instance. A temporary diagnostic build of the same event handling recorded real pointer ENTER, delayed SHOW, visible panel, and EXIT; the user confirmed it appeared. The normal installed app was then relaunched and the user confirmed its hover appears. No speculative event-handler change was made; the original stale-running/hosted state was not conclusively diagnosed.

The user found the compositor-only card insufficiently frosted. ScrollToggle uses NSGlassEffectViewStyleRegular with 12-point corners, whereas ChargeCap had painted a 76%-opaque gray body over a uniform blur. The hover now uses that same native glass wrapper with a transparent CPU-rendered text surface. Its extra private blur and painted body/rim were removed, avoiding duplicate effects. The shadow remains off and the wrapper is released with the window after the existing idle grace period.

The updated read-only 20-hover/20-panel stress run measured 10.831 MB idle after cleanup and 13.043 MB kernel lifetime peak, compared with the old compositor-only 8.996 / 11.076 MB. The native material therefore improves the requested appearance at a measurable memory cost and misses the 10 MB goal. Tests assert the actual native material, regular style, 12-point radius, and text ownership. The installed card's physical hover and improved frosting were confirmed by the user; no live desktop screenshot is claimed.
