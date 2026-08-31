# Grid Conditions Widget — Design QA

## Comparison target

- Source visual truth: `/Users/chandler/.codex/generated_images/01a03a4d-c2aa-7433-ab6d-6f4089958f27/exec-06016d70-d0f0-4e4d-9e11-998d791c46a0.png`
- Implementation screenshot: `/private/tmp/grid-conditions-small.png`
- Secondary responsive evidence: `/private/tmp/grid-conditions-medium.png`
- Viewport: WidgetKit small family, 158 × 158 points, light appearance
- Source pixels: 800 × 800
- Implementation pixels: 632 × 632 at 4× render density
- Density normalization: source downsampled to 632 × 632 at `/private/tmp/grid-reference-632.png`; implementation retained at its native 4× capture. Both normalized artifacts were opened together in one comparison input.
- State: Finland; 34 gCO₂/kWh; cleaner-than-usual emissions; 12-hour renewable timeline; no Now marker. The current user-directed delta removes the forecast explanation sentence and shortens the chart heading.

## Full-view comparison evidence

The implementation preserves the selected composition and hierarchy: country first, carbon intensity as the dominant value, one semantic leaf/status row, and a single supporting High/Avg/Low timeline. Per the latest direction, the redundant renewable explanation is removed and the chart heading is shortened to `RENEWABLES · 12 HOURS`. It uses native San Francisco typography, an SF Symbols `leaf.fill`, system semantic colors, system widget background, and continuous widget clipping.

The chart contains a later Low interval because the realistic 12-hour sample continues through midnight, whereas the source visual ends at 21:00. This is a data-state difference rather than design drift; the chart encoding, levels, transitions, axis treatment, and hierarchy match the source.

## Focused-region comparison evidence

A separate crop was not needed. At 632 × 632, the value/unit baseline, leaf symbol, status label, compact caption, axis labels, colored steps, and time labels were all readable in the normalized full-view comparison.

## Required fidelity surfaces

- Fonts and typography: Native SF system styles and optical weights preserve the source hierarchy. The value uses rounded bold numerals and monospaced digits; secondary and chart text use progressively quieter weights and colors. No truncation remains in the final small or medium render.
- Spacing and layout rhythm: Content remains inside the 158 pt rounded widget bounds. Removing the sentence creates a calmer break between emissions status and the chart. The medium layout balances the value and status on one row without splitting the two data sources into equal cards.
- Colors and visual tokens: Primary text is system foreground; carbon status uses green/orange/red semantic state colors; forecast steps use the same semantic palette at native contrast. Grid rules and labels are deliberately subdued.
- Image quality and asset fidelity: No raster asset substitution is used. The leaf is the native SF Symbol `leaf.fill`; the chart is rendered with SwiftUI vector shapes and remains sharp at device scale.
- Copy and content: Only essential copy remains: `Finland`, carbon intensity and unit, `Cleaner than usual`, and the time-scoped `RENEWABLES` caption. The chart communicates the forecast state directly; the current-time marker remains absent.

## Findings

No actionable P0, P1, or P2 differences remain.

### Accepted constraints

- The source is a conceptual square mock with more whitespace than a real small WidgetKit family. The implementation uses a denser but still ordered layout to retain readable type at 158 pt.
- The operating system supplies the final Home Screen/Desktop background material, mask, shadow, and surrounding wallpaper; the code-rendered comparison captures the widget content and mask only.
- Public Release builds obtain live Fingrid emissions from the fixed project relay without a customer key. A local key is optional and restricted to direct-provider Debug testing.

## Comparison history

1. Initial actual-size render found a P2 density issue: the timeline labels sat too close to the lower mask and the sample timing did not match the selected visual. Fixed by reducing compact vertical metrics, raising the time labels, shortening the compact chart, and aligning the sample high-renewable run to 14:30. Post-fix evidence: `/private/tmp/grid-conditions-small.png`.
2. Responsive check found a P2 medium-family truncation in the renewable summary. Fixed by using two concise supporting lines (`Renewables · Average` and `Higher from 14:30`) and reducing the medium chart height. Post-fix evidence: `/private/tmp/grid-conditions-medium.png`.
3. Final normalized small-family comparison found no actionable P0/P1/P2 mismatch. Evidence: `/private/tmp/grid-reference-632.png` and `/private/tmp/grid-conditions-small.png`, opened together at 632 × 632.
4. The user requested less text. Removed the renewable explanation sentence from small, removed the two-line forecast copy from medium, shortened both chart headings, and used the recovered space for a calmer chart layout. The revised small and medium renders have no clipping or truncation. Post-fix evidence: `/private/tmp/grid-conditions-small.png` and `/private/tmp/grid-conditions-medium.png`.

## Implementation checklist

- [x] Carbon intensity is the primary metric.
- [x] Renewable forecast is one supporting timeline, not a separate card.
- [x] Redundant forecast prose is removed from both families.
- [x] High/Avg/Low levels and forecast time labels remain visible.
- [x] No Now marker is rendered.
- [x] Native SF Symbol and system typography/colors are used.
- [x] Small and medium widget families render without clipping or truncation.
- [x] Live data failure states remain honest.

final result: passed

---

# Master Dashboard — First-Trial Design QA

## Comparison target

- Source visual truth: `/Users/chandler/.codex/generated_images/01a057de-e4ae-7291-a131-57d9ed4e4339/exec-8e13b6ca-6a9a-4062-9d1a-e03e0396575e.png`
- Initial implementation screenshot: `/private/tmp/spotprice-dashboard.png`
- Corrected chart screenshot: `/private/tmp/spotprice-dashboard-v2.png`
- Final implementation screenshot: `/private/tmp/spotprice-dashboard-final-live.png`
- Revised Today state: `/private/tmp/spotprice-dashboard-toggle-today.png`
- Revised Tomorrow empty state: `/private/tmp/spotprice-dashboard-toggle-tomorrow-final.png`
- Reported-versus-fixed comparison: `/private/tmp/spotprice-design-audit-comparison.png`
- Viewport: native macOS window at 1920 × 1080 points in dark appearance; captured at 2× density.
- Data state: live spot price and live relay emissions; today selected because tomorrow prices were not published at the capture time; renewable forecast live; emissions history visibly marked as a Debug preview because no local direct-history credential was available.

## Full-view comparison evidence

The first-trial implementation preserves the approved master-screen hierarchy: one unified live status band, two equally weighted analytical cards, a dense native hourly table, and existing product-management sections below. The price card uses 24 fully rounded native `BarMark`s with the fixed green/orange/red bands, a zero baseline, negative-price headroom, and numeric-only extrema. The grid card avoids a dual-axis or normalized overlay: a fixed Forecast/History selector switches between a green renewable-share `AreaMark` plus `LineMark` and cyan emissions `BarMark`s, each with its own unit and raw-value annotation.

The final capture also verifies the app-specific Fingrid relay path. The main app reads the public relay configuration from its bundled widget extension and displays a live 15 gCO₂/kWh measurement rather than the earlier false unavailable state.

## Required fidelity surfaces

- Fonts and typography: Native San Francisco text styles, rounded monospaced numeric values, hierarchical captions, and semantic secondary labels remain readable at the desktop viewport.
- Spacing and layout rhythm: The dashboard uses a 1420-point content column, 18-point inter-card rhythm, continuous 24-point card corners, and native table density. The analytical cards use matching 520-point minimum widths, fixed 240-point segmented controls, and fixed chart-content heights; they collapse vertically through `ViewThatFits` when the window narrows.
- Colors and visual tokens: Price alone controls green/orange/red price marks. Emissions history uses cyan bars; renewable forecast uses a green area and line. Grid status uses the live Fingrid band color. Materials, dividers, and axes use system semantic styling.
- Chart semantics: Raw gCO₂/kWh and renewable percentage never share an axis. Forecast and History expose their own titles, time scope, unit, scale, selection annotation, and unavailable state.
- Copy and content: Live units, data provenance, update times, price conditions, renewable percentages, recommendations, and the preview-history disclosure remain explicit. Tomorrow remains selectable before publication and shows a time-specific empty state instead of Today’s data.
- Data integrity: Live headline emissions come from the keyless relay. Debug-only synthetic history is confined to the historical emissions bar profile and is visibly labeled; Release builds do not silently substitute that profile.

## Findings and fixes

1. P1: Both native bar series collapsed when `.ratio` mark widths were used with continuous axes. Fixed with explicit point widths; final price and emissions bars are fully visible.
2. P1: The renewable line connected hour 23 back to hour 00 because chronological forecast order wrapped on a local-hour axis. Fixed by sorting plotted points by local hour.
3. P1: The main app reported emissions unavailable even while the widget relay was configured. Fixed by resolving the relay URL from the bundled widget extension when the host app has no duplicate configuration key.
4. P2: Interactive chart selection cleared the initial 18:00 review state. Fixed by retaining 18:00 as the inspection fallback while preserving native chart selection.
5. P1: Tomorrow originally appeared selected while silently rendering Today before publication. Fixed by making both segments selectable and rendering an explicit `Tomorrow isn’t published yet` state with the expected Helsinki publication time.
6. P2: Normalized emissions marks could visually cross the zero baseline. Fixed by clamping the score to 0–100 before rendering.
7. P1: Price bars collided with the trailing y-axis labels. Fixed with explicit plot-dimension end padding; the final bar and the 0/5 tick labels no longer overlap.
8. P1: Equal-width gauge bands misrepresented the actual price range and omitted range endpoints. Fixed by positioning the 4.99 and 8.99 thresholds proportionally inside the live daily range and labeling the numeric Lowest and Highest values.
9. P1: The normalized Grid overlay mixed historical emissions with future renewable share and remained difficult to explain. Fixed by using separate Forecast and History views inside one unified card, with a percentage area/line chart for renewable share and raw gCO₂/kWh bars for emissions.
10. P2: Grid states and day selection changed the analytical-card geometry. Fixed with equal minimum card widths, fixed segmented-control widths, fixed content heights, and reserved axis-label padding.

No actionable P0, P1, or P2 differences remain for the approved first-trial scope.

### Accepted first-trial constraints

- The approved source uses illustrative tomorrow data. The live capture occurred before the provider published tomorrow, so Tomorrow shows the actual pre-publication state rather than fabricated bars.
- The source mock places the day selector in custom window chrome. The first trial keeps native macOS navigation chrome and places the selector inside the price card.
- The source includes additional cheapest/avoid summary strips and a separate grid-signal table column. The first trial expresses the same decision layer through the top best-window status and the table recommendation column; these can be expanded in the next review without changing the chart architecture.
- Historical emissions require a local direct Fingrid credential. Without it, Debug shows a labeled preview profile while the live headline remains real; public Release shows no synthetic history.

## Verification

- [x] Native macOS Debug build succeeds.
- [x] Grid conditions signal tests pass.
- [x] Product maintenance logic tests pass.
- [x] Software update trust tests pass.
- [x] Uninstaller target tests pass.
- [x] Price `BarMark`s are fully visible and rounded.
- [x] Trailing price-axis labels remain clear of the last bar.
- [x] The live range gauge uses proportional thresholds and shows Lowest/Highest endpoints.
- [x] Today and Tomorrow both select correctly; unpublished Tomorrow never falls back to Today.
- [x] Forecast and History use distinct charts and never mix unlike units on one axis.
- [x] Both analytical cards and their controls keep stable widths across state changes.
- [x] Local-hour wrap does not create a false line segment.
- [x] Live app emissions load through the bundled public relay configuration.
- [x] Debug preview history is visibly disclosed.
- [x] Existing software update and danger-zone controls remain below the dashboard.

final result: passed

---

# Electricity Rates Widget — Design QA

## Comparison target

- Small source visual truth: `/Users/chandler/.codex/generated_images/01a03a4d-c2aa-7433-ab6d-6f4089958f27/exec-75157de6-feee-482a-b3df-5a5bc61ac878.png`
- Medium source visual truth: `/Users/chandler/.codex/generated_images/01a03a4d-c2aa-7433-ab6d-6f4089958f27/exec-72c10aaf-5845-41db-ab50-c68185736f38.png`
- Small implementation screenshot: `/private/tmp/electricity-rates-small-delivery.png`
- Medium implementation screenshot: `/private/tmp/electricity-rates-medium-delivery.png`
- Negative-rate implementation screenshot: `/private/tmp/electricity-rates-medium-negative.png`
- Combined comparison inputs: `/private/tmp/electricity-rates-small-comparison.png` and `/private/tmp/electricity-rates-medium-comparison.png`
- Viewports: WidgetKit small at 170 × 170 points and medium at 355 × 178 points, light appearance
- Implementation density: both rendered at 4× (680 × 680 and 1420 × 712 pixels)
- Primary state: Finland; Standard; 8,42 c/kWh; range 3,90–18,1; 24 hourly bars; current hour 15:00
- Negative-rate state: Finland; Off-Peak; −1,50 c/kWh; range −5,00–14,5; visible zero baseline; current hour 15:00

## Full-view comparison evidence

Each QA input places the approved reference and the real SwiftUI render side by side at one normalized size. The implementation preserves the selected hierarchy: a compact Home-style header, the status as the main semantic message, one Weather-style range gauge containing the sole current-price value, and one supporting 24-hour chart. The small family vertically centers the enlarged status beside the gauge. The medium family carries the same typography ratio into an upper-left status block without centering it against the gauge.

The medium chart exposes numeric-only extrema, a subtle current-time marker, and four time ticks. The small chart removes extrema and time labels to protect glanceability. Both use exactly 24 equal-width slots. Positive medium bars use a full semicircular radius across the top while retaining completely square bottom corners. Negative bars extend below a visible zero rule and mirror that shape: flat at zero with a rounded lower end. The final user-directed refinement removes the medium footer entirely.

## Focused-region comparison evidence

Separate crops were not needed. At 4× density, the gauge endpoints, value/unit baseline, status copy, current indicator, extreme labels, 24 individual bars, and time ticks are legible in the combined full-view comparisons.

## Required fidelity surfaces

- Fonts and typography: Native San Francisco styles preserve the approved weight and scale relationships. The unit is visibly below the price inside the gauge, status typography is enlarged, and the central price uses a constrained, slightly smaller monospaced style so a leading minus sign never collides with the arc.
- Spacing and layout rhythm: The small status aligns to the gauge's visual center. The medium status remains upper-left with a clear chart zone below. All content stays inside the system WidgetKit margins and mask.
- Colors and visual tokens: The gauge uses a neutral gray track and black position dot. Price alone determines the semantic state: below 4,99 c/kWh is green, 4,99–8,99 is orange, and above 8,99 is red. Negative rates remain green.
- Image quality and asset fidelity: The bolt is the native SF Symbol `bolt.fill`; the gauge and chart use SwiftUI vector shapes and remain sharp at device scale. No raster asset substitution is used in the implementation.
- Copy and content: The price appears once, inside the gauge. Small keeps only the active band label, its time-scoped detail, and `Now`. Medium adds numeric extrema and compact time ticks without repeating the current price or adding a footer.

## Findings

No actionable P0, P1, or P2 differences remain.

### Accepted constraints

- The reference images are aspirational mockups with non-system outer spacing. The implementation follows the actual WidgetKit family proportions, content margins, material, and clipping mask.
- The operating system supplies the final desktop/Home Screen material, shadow, and surrounding wallpaper.
- `Lowest Now` or `Highest Now` replaces the standalone `Now` label when the current bar is also the day's numeric minimum or maximum.
- Unpublished hours retain their slots but render neutrally so the chart never misrepresents unavailable data.
- The fixed price thresholds supersede the rank-derived colors shown in earlier conceptual references.

## Comparison history

1. The approved source concepts were normalized against actual 170 × 170 and 355 × 178 SwiftUI renders in side-by-side comparison inputs.
2. The implementation corrected the conceptual small card to a true square family and enforced exactly 24 deterministic chart slots.
3. Final comparison confirmed the enlarged status ratio, single price value, gauge alignment, medium extrema labels, and absence of clipping or truncation.
4. The final medium-family refinement increased the top corners to a full semicircular radius while retaining a flat bottom; the compact small-family chart remains unchanged.
5. Removed `Today · hourly avg · incl. VAT` from medium and expanded the chart region into the recovered space.
6. Replaced rank-derived color bands with fixed price thresholds and verified exact boundary behavior at 4,99 and 8,99 c/kWh.
7. Added signed chart geometry. Negative prices render below a zero rule with mirrored rounding; verified at −5,00 and a current price of −1,50 c/kWh.
8. Reduced the central gauge value from 24,5% to 22% of gauge size and constrained it to 66% of the gauge width, preventing negative values from colliding with the arc.

## Implementation checklist

- [x] Small status is vertically centered with the gauge.
- [x] Medium uses the same enlarged status ratio at upper left.
- [x] Current price is shown once, inside the gauge.
- [x] Gauge unit sits below the price and endpoints remain visible.
- [x] Both charts contain exactly 24 slots.
- [x] Medium extrema use numeric-only labels.
- [x] `Now`, `Lowest Now`, and `Highest Now` states are supported.
- [x] Medium bars have fully semicircular tops and completely flat bottoms.
- [x] Medium footer copy is removed.
- [x] Prices below 4,99 are green, including zero and negative values.
- [x] Prices from 4,99 through 8,99 are orange.
- [x] Prices above 8,99 are red.
- [x] Negative rates render below a visible zero baseline without clipping labels or time ticks.
- [x] Negative gauge values retain the minus sign and fit cleanly inside the arc.
- [x] Native SF Symbol, system typography, semantic colors, and WidgetKit backgrounds are used.
- [x] Small and medium render without clipping or truncation.

final result: passed
