---
name: pine-charts
description: >-
  Use when building SVG-first, unstyled, accessible charts in pocopine with line, area, bar, scatter, pie, or custom layered visualizations
---

# Pine Charts

## What This Is

Pine Charts is the SVG-first charting layer for the pocopine framework. It provides unstyled, accessible chart primitives (line, area, bar, scatter, pie, radial, and custom layered charts) where the Rust crate owns geometry, scales, interaction, and data validation while your application owns styling, layout, and domain-specific behavior.

## When to Use

- Building dashboards or analytics dashboards with multiple chart types
- Composing custom Cartesian charts (mixing bars, lines, areas, and scatter with shared axes)
- Implementing interactive charts with hover, selection, and keyboard navigation
- Needing legend filtering, responsive sizing, or reference lines/annotations
- Layering custom SVG elements with automatic coordinate transformation
- Rendering pie/donut/half-pie charts or radial progress rings

**Not recommended for:** static image export, very large datasets (100k+ points), or canvas-based rendering.

## Key API / Syntax

### Preset Charts
- `pine-line-chart` – single or multi-line charts from `Vec<ChartPoint>` or `Vec<ChartLineSeries>`
- `pine-area-chart` – area fills from `Vec<ChartAreaSeries>`
- `pine-bar-chart` – categorical bars from `Vec<ChartBarSeries>`
- `pine-scatter-chart` – point clouds from `Vec<ChartScatterSeries>`
- `pine-pie-chart` – pie/donut/half-pie from `Vec<ChartPieSlice>`
- `pine-radial-bar-chart` – progress rings from `Vec<ChartRadialBar>`

### Cartesian Composition (Combo Charts)
- `pine-cartesian-chart` – compound root for mixed series and shared axes
  - `pine-chart-grid`, `pine-x-axis`, `pine-y-axis` – guides
  - `pine-bar-series`, `pine-line-series`, `pine-area-series`, `pine-scatter-series` – data layers
  - `pine-cartesian-reference-line`, `pine-cartesian-reference-dot`, `pine-cartesian-reference-label` – annotations

### Layered Charts (Custom SVG)
- `pine-layer-chart` – custom SVG composition with automatic layer ordering
  - `pine-chart-layer` – named layer (e.g. "grid", "series", "annotations")
  - `pine-chart-line`, `pine-chart-marker`, `pine-chart-guide`, `pine-chart-icon`, `pine-chart-label`, `pine-chart-reference-dot`

### Data Types
- `ChartPoint::new(x, y)` – single (x, y) coordinate
- `ChartLineSeries::new(label, vec![points])` – multi-series with label
- `ChartBar::new(label, value)` – categorical bar
- `ChartAreaSeries::new(label, vec![points])` – stacked area
- `ChartPieSlice::new(label, value)` – pie segment
- `ChartLayerPoint::new(x, y)` – absolute SVG coordinates for layered charts

### Foundation Layer (Pure Rust, No Browser)
- `ChartMargins::new(top, right, bottom, left)` – reserved space
- `ChartRect::from_outer(width, height, margins)?` – plot rectangle
- `LinearScale::new((domain_start, domain_end), (range_start, range_end))?` – numeric mapping
- `BandScale` – categorical index-to-position mapping
- `line_path(points)?`, `area_path(points)?` – SVG path builders
- `Tick { value, position }` – scale tick generation

### Legend & Visibility
- `line_legend_items(&series)` – derive `Vec<LegendItem>` from series
- `area_legend_items`, `bar_legend_items`, `scatter_legend_items`, `pie_legend_items`, `radial_bar_legend_items`
- `set_line_series_visible(&mut series, &key, active)` – toggle series visibility
- Matching helpers: `set_area_series_visible`, `set_bar_series_visible`, `set_scatter_series_visible`, `set_pie_slice_visible`, `set_radial_bar_visible`

### Interaction & Events
- `pp:chart:hover` / `pp:chart:hover-end` – pointer movement over plot
- `pp:chart:select` / `pp:chart:select-end` – click or keyboard selection
- `pp:chart:legend-toggle` – legend item clicked
- `ChartHover::from_event_value(event)` – parse hover payload
- `ChartSelection::from_event_value(event)` – parse selection payload
- `LegendToggle::from_event_value(event)` – parse legend toggle payload

### Responsive Container
- `pine-chart-responsive` – measures parent, writes concrete width/height to child
  - `width="100%"` (default) – CSS width
  - `aspect_ratio="2"` (default) – width / height ratio
  - `min_width`, `min_height` – CSS pixel floors after aspect sizing

### Styling Hooks (CSS Classes & Data Attributes)
- `.pine-chart-root`, `.pine-line-chart`, `.pine-area-chart`, `.pine-bar-chart`, `.pine-scatter-chart`, `.pine-pie-chart`
- `.pine-chart-grid`, `.pine-chart-axis`, `.pine-chart-axis-x`, `.pine-chart-axis-y`
- `.pine-chart-legend`, `.pine-chart-legend-item`, `.pine-chart-legend-marker`
- `.pine-chart-tooltip`, `.pine-chart-crosshair`, `.pine-chart-hover-marker`
- `data-hover`, `data-selected`, `data-focused`, `data-series`, `data-key`
- CSS variables: `--pine-chart-tooltip-x`, `--pine-chart-tooltip-y`, `--pine-chart-animation-duration`, `--pine-chart-animation-easing`

## Examples

### Line Chart with Multi-Series
```rust
// /home/zempare-mambisi/RustProjects/pocopine/crates/pine-charts/src/line/mod.rs
use pine_charts::{line_legend_items, ChartLineSeries, ChartPoint};

let series = vec![
    ChartLineSeries::new(
        "Actual",
        vec![ChartPoint::new(0.0, 12.0), ChartPoint::new(1.0, 18.0)],
    ),
    ChartLineSeries::new(
        "Target",
        vec![ChartPoint::new(0.0, 10.0), ChartPoint::new(1.0, 20.0)],
    ),
];
let legend_items = line_legend_items(&series);
```

```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/charts/src/ChartDemo.poco (lines 49–101) -->
<pine-line-chart
  label="Revenue"
  pp-bind:series="series"
  x_label="Week"
  y_label="Revenue"
  width="640"
  height="320"></pine-line-chart>

<pine-chart-legend
  label="Revenue legend"
  pp-bind:items="legend_items"></pine-chart-legend>
```

### Cartesian Combo Chart (Bars + Lines + Areas + Scatter + References)
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/charts/src/ChartDemo.poco (lines 24–81) -->
<pine-chart-responsive class="chart-panel" aspect_ratio="3.2" min_height="190">
  <pine-cartesian-chart label="Weekly metric combo"
                        animate="true"
                        animation_duration="180">
    <pine-chart-grid></pine-chart-grid>
    <pine-x-axis label="Week"></pine-x-axis>
    <pine-y-axis label="Revenue"></pine-y-axis>
    
    <pine-bar-series key="actual"
                     label="Actual"
                     pp-bind:data="combo_bar_data"></pine-bar-series>
    
    <pine-cartesian-reference-line key="goal"
                                   label="Goal"
                                   pp-bind:y="combo_goal"
                                   stroke_dasharray="4 4"></pine-cartesian-reference-line>
    
    <pine-area-series key="band"
                      label="Trend band"
                      pp-bind:points="combo_area_points"></pine-area-series>
    
    <pine-line-series key="target"
                      label="Target"
                      show_markers="true"
                      pp-bind:data="combo_line_data"></pine-line-series>
    
    <pine-scatter-series key="samples"
                         label="Samples"
                         pp-bind:points="combo_scatter_points"></pine-scatter-series>
  </pine-cartesian-chart>
</pine-chart-responsive>
```

### Layered Chart with Guides, Lines, and Markers
```html
<!-- /home/zempare-mambisi/RustProjects/pocopine/examples/charts/src/ChartDemo.poco (lines 87–145) -->
<pine-layer-chart label="Metro layer order" animate="true">
  <pine-chart-layer name="grid">
    <pine-chart-guide key="grid-h" x1="80" y1="120" x2="820" y2="120"></pine-chart-guide>
  </pine-chart-layer>
  
  <pine-chart-layer name="series">
    <pine-chart-line key="line-a" label="Line A" color="#19a974" 
                     stroke_width="14" pp-bind:points="metro_line_a"></pine-chart-line>
  </pine-chart-layer>
  
  <pine-chart-layer name="markers">
    <pine-chart-marker key="a1" label="A1" x="100" y="120" 
                       radius="8.5" fill="#19a974"></pine-chart-marker>
  </pine-chart-layer>
  
  <pine-chart-layer name="labels">
    <pine-chart-label key="label" text="Station" x="100" y="120" 
                      dx="8" dy="-24" font_weight="700"></pine-chart-label>
  </pine-chart-layer>
</pine-layer-chart>
```

### Interactive Legend with Selection Handling
```rust
// /home/zempare-mambski/RustProjects/pocopine/examples/charts/src/lib.rs (simplified)
use pine_charts::LegendToggle;
use pocopine::prelude::JsValue;

pub fn toggle_area_series(&mut self, event: JsValue) {
    let Some(toggle) = LegendToggle::from_event_value(event) else {
        return;
    };
    
    if set_area_series_visible(&mut self.area_series, &toggle.key, toggle.active) {
        self.area_legend = area_legend_items(&self.area_series);
    }
}
```

## Gotchas

1. **All numbers must be finite**: `ChartPoint`, `ChartBar`, scale domains, and margins reject NaN, Inf, or non-positive sizes. Validate data before passing to charts.

2. **Domains must not be flat**: `LinearScale::new((5.0, 5.0), ...)` will error. Use `optional_domain()` to auto-expand single-point charts.

3. **No built-in styling**: Pine Charts ships no CSS. You must provide colors, strokes, fonts, and spacing via application CSS targeting the semantic classes.

4. **SVG `preserveAspectRatio="none"`**: Charts stretch non-uniformly to fill their container. Use `pine-chart-responsive` for aspect-ratio preservation.

5. **Categorical x-axis requires matching labels**: In combo charts, all categorical series (`pine-bar-series`, categorical `pine-line-series`) must use identical category labels in the same order.

6. **Layered chart coordinates are absolute**: `pine-layer-chart` uses raw SVG (x, y) with no automatic scaling. Use `pine-cartesian-chart` when you need shared data-space scales.

7. **Legend filtering is app-owned**: Toggling `interactive="true"` emits events and updates `data-active` but does not filter the chart. You must call visibility helpers and re-render.

8. **Tooltip by default, custom with `tooltip="none"`**: Default tooltips render as HTML. Set `tooltip="none"` and listen to `pp:chart:hover` events to render a custom tooltip; the app is then responsible for `aria-live` regions.

9. **Hover detection differs by chart type**:
   - Line/area/scatter: nearest point by SVG distance
   - Bar: painted SVG rect under pointer
   - Pie/donut: hovered slice
   - Radial: hovered ring

10. **No canvas rendering**: Canvas is intentionally out of scope. Use SVG or migrate to a separate canvas crate if you need to handle 100k+ points.

## References

- **Crate**: `/home/zempare-mambisi/RustProjects/pocopine/crates/pine-charts/`
- **Module hierarchy**: `lib.rs` exports all; internal modules `cartesian`, `line`, `area`, `bar`, `scatter`, `pie`, `radial`, `layered`, `legend`, `responsive`, `scale`, `path`, `geometry`, `events`, `visibility`
- **Examples**: `/home/zempare-mambisi/RustProjects/pocopine/examples/charts/src/`
  - `lib.rs` – component state and data helpers
  - `ChartDemo.poco` – template with combo, scatter, area, bar, pie, radial, and layered charts
- **Documentation**: `/home/zempare-mambski/RustProjects/pocopine/docs/charts/`
  - `README.md` – design model and styling contract
  - `foundation.md` – geometry, scales, and paths
  - `components.md` – preset charts API
  - `cartesian.md` – compound Cartesian root and child composition
  - `axes-grid.md` – guide styling hooks
  - `interaction.md` – hover, selection, keyboard, legend filtering
  - `legend.md` – legend component and visibility control
  - `responsive.md` – `PineChartResponsive` sizing
  - `layered.md`, `layers.md` – custom SVG composition
  - `events.md` – interaction payloads
  - `cookbook.md` – common patterns
- **Registration**: Call `pine_charts::register_all()` in your app's `main()` or explicitly register individual components.
