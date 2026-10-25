# Native hover material memory probes

All numbers are decimal MB of app-process physical footprint, including kernel lifetime peak. Temporary apps ran through LaunchServices. Every candidate uses one app process, the existing IOSurface text renderer, shadow disabled, and the two-second idle cleanup. No charging-change actions were sent. Short probes ran five hover/panel pairs with a longer idle pause and final cleanup. The short harness omits its usual outer autorelease pool so native presentation is closer to the production callback path.

| Short probe | Idle after cleanup | Lifetime peak |
|---|---:|---:|
| Regular NSGlassEffectView, unchanged | 11.027 | 13.321 |
| Full UI/teardown autorelease pools | 11.093 | 12.993 |
| Explicit glass hierarchy detachment | 11.011 | 13.174 |
| Both cleanup changes | 10.913 | 13.272 |
| NSVisualEffectView toolTip material | 9.274 | 11.240 |
| NSVisualEffectView menu material | 9.209 | 10.945 |

The cleanup probes did not make a material difference and were not integrated. The native menu material was selected for a full test; it keeps system-provided behind-window frosting rather than a painted opaque tint. The effect differs from newer refractive Liquid Glass, so the user was asked to check the installed appearance.

Final unchanged production stress harness: 20 hover/panel pairs, all five visual limit states and four idle pauses: 9.127 MB idle after cleanup, 11.060 MB lifetime peak. It meets 10 MB idle in that bounded run; the lifetime peak remains above 10 MB.

The menu-material follow-up also tested the existing allocator configuration against Nano enabled and one retained recirculation region. Neither improved the short menu probe: Nano 9.209 MB idle / 11.175 MB peak; retained-region flag 9.291 / 11.191. Original app-local allocator flags were retained.

Scoped UI/teardown autorelease pools plus explicit hidden-panel content detachment measured 9.045 MB idle / 10.749 MB peak in the short menu probe. These keep temporary native objects scoped to their callbacks and drop the effect hierarchy before window disposal. The final refinement keeps this cleanup with the menu material. It does not change settings, timers, process count, or hover placement.

Full final build with scoped allocations: 9.192 MB idle after cleanup, 11.126 MB lifetime peak. This is close to the menu-only full test (9.127 / 11.060), rather than evidence of a large additional saving from scoped allocations. The installed final process measured 8.389 MB current / 8.979 MB lifetime peak in a 20-second pre-interaction sample, averaging 0.00013% of one CPU core. Do not present that startup sample as post-use memory. An earlier installed menu-only sample after ordinary use measured 10.339 MB current / 10.847 MB lifetime peak. Visual confirmation of the lighter material was requested from the user and was still pending when these results were recorded.
