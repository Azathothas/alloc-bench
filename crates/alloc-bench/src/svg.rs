use crate::rank::Row;

fn esc(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Colour-blind-safe, and the control is deliberately grey so the eye does not
/// read it as another candidate.
const BAR: &str = "#3b7dd8";
const BAR_SLOW: &str = "#d1495b";
const BAR_BASE: &str = "#8a8f98";
const BAR_TIE: &str = "#9aa7b4";
const FG: &str = "#1b1f24";
const MUTED: &str = "#5b636d";
const GRID: &str = "#d8dce1";
const AXIS: &str = "#aeb4bb";

/// Which way is good on this chart's axis.
///
///  There is no `Unknown`. A chart whose author cannot say which direction is
/// better is a chart a reader cannot act on, and every quantity this project
/// plots has an answer.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Better {
    Lower,
    Higher,
}

impl Better {
    fn pill(self) -> (&'static str, &'static str) {
        match self {
            // The arrow points along the axis toward the good end, and the
            // words are there because an arrow alone is a convention a reader
            // may not share.
            Better::Lower => ("◀ shorter bar is BETTER", "#1f7a4d"),
            Better::Higher => ("▶ longer bar is BETTER", "#1f7a4d"),
        }
    }
}

/// One bar.
pub struct Bar {
    pub label: String,
    pub value: f64,
    pub is_baseline: bool,
    /// The value as a human reads it, e.g. `0.595× (40.5% faster)`.
    pub note: String,
    /// ± this many axis units, drawn as a whisker. `None` where the quantity
    /// has no repeat measurement (binary size is one number, not a sample).
    pub err: Option<f64>,
    /// True when this row's difference from the reference is smaller than its
    /// own error bar.  §9's rule, made visible: such a row is drawn in the
    /// tie colour rather than the faster/slower ones, because calling it faster
    /// is exactly the claim the rule forbids.
    pub within_noise: bool,
}

pub struct Chart<'a> {
    pub title: &'a str,
    pub subtitle: &'a str,
    pub unit: &'a str,
    pub bars: Vec<Bar>,
    /// Drawn as a dashed reference line, e.g. 1.0 for a ratio chart.
    pub reference: Option<f64>,
    /// What the reference line means, in words, e.g. `control = 1.000×`.
    pub reference_label: &'a str,
    pub better: Better,
    /// Axis unit suffix for the tick labels, e.g. `×` or ` MiB`.
    pub tick_suffix: &'a str,
}

/// A round step that yields roughly `want` ticks over `span`.
fn nice_step(span: f64, want: f64) -> f64 {
    if span <= 0.0 || !span.is_finite() {
        return 1.0;
    }
    let raw = span / want.max(1.0);
    let mag = 10f64.powf(raw.log10().floor());
    let norm = raw / mag;
    //  The bucket edges are 1.5/3/7 rather than the textbook 1/2/5, and the
    // difference is visible on the charts this project actually draws. A ratio
    // axis topping out near 1.28 gives norm ≈ 2.13; under the textbook edges
    // that rounds UP to a step of 0.5 and the chart gets three gridlines. Under
    // these it takes 0.2 and gets seven.
    let mult = if norm <= 1.5 {
        1.0
    } else if norm <= 3.0 {
        2.0
    } else if norm <= 7.0 {
        5.0
    } else {
        10.0
    };
    mult * mag
}

fn tick_label(v: f64, suffix: &str) -> String {
    let s = if v.abs() >= 10.0 || (v - v.round()).abs() < 1e-9 {
        format!("{:.0}", v)
    } else {
        format!("{:.1}", v)
    };
    format!("{}{}", s, suffix)
}

pub fn bar_chart(c: &Chart) -> String {
    let n = c.bars.len().max(1);
    let row_h = 26.0;
    //  Three text rows live above the plot now - title, subtitle, and the
    // direction pill with its colour legend - plus the axis strip.
    let pad_top = 104.0;
    let pad_bottom = 52.0;
    let label_w = 260.0;
    let plot_w = 460.0;
    let width = label_w + plot_w + 110.0;
    let height = pad_top + row_h * n as f64 + pad_bottom;

    let max = c
        .bars
        .iter()
        .map(|b| b.value + b.err.unwrap_or(0.0))
        .fold(c.reference.unwrap_or(0.0), f64::max)
        .max(f64::MIN_POSITIVE);
    let top = max * 1.08;
    let scale = |v: f64| (v / top) * plot_w;

    let mut s = String::new();
    let (pill_text, pill_fill) = c.better.pill();
    s.push_str(&format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0}" height="{h:.0}" viewBox="0 0 {w:.0} {h:.0}" font-family="ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif" role="img" aria-label="{title} - {pill}">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="16" y="26" font-size="15" font-weight="600" fill="{fg}">{title}</text>
<text x="16" y="45" font-size="11" fill="{muted}">{sub}</text>
<rect x="16" y="54" width="188" height="19" rx="9.5" fill="{pf}" opacity="0.12"/>
<text x="110" y="67.5" font-size="10.5" font-weight="600" fill="{pf}" text-anchor="middle">{pill}</text>
"##,
        w = width,
        h = height,
        fg = FG,
        muted = MUTED,
        title = esc(c.title),
        sub = esc(c.subtitle),
        pf = pill_fill,
        pill = esc(pill_text)
    ));

    // ------------------------------------------------------------- the legend
    //
    //  The three bar colours were unexplained for as long as they existed. A
    // reader who does not know that grey is the control reads six candidates
    // where there are five and a baseline.
    let mut lx = 214.0;
    let mut legend = |swatch: &str, text: &str, s: &mut String| {
        s.push_str(&format!(
            r##"<rect x="{x:.1}" y="58" width="10" height="10" rx="2" fill="{c}"/>
<text x="{tx:.1}" y="67" font-size="10" fill="{muted}">{t}</text>
"##,
            x = lx,
            c = swatch,
            tx = lx + 14.0,
            muted = MUTED,
            t = esc(text)
        ));
        lx += 16.0 + text.len() as f64 * 5.4;
    };
    legend(BAR_BASE, "control", &mut s);
    if c.reference.is_some() {
        legend(BAR, "better than control", &mut s);
        legend(BAR_SLOW, "worse than control", &mut s);
        legend(BAR_TIE, "inside its own noise", &mut s);
    }

    // --------------------------------------------------------------- the axis
    let plot_bottom = pad_top + row_h * n as f64;
    let step = nice_step(top, 6.0);
    let mut t = 0.0;
    while t <= top + step * 0.001 {
        let x = label_w + scale(t);
        s.push_str(&format!(
            r##"<line x1="{x:.1}" y1="{y0:.1}" x2="{x:.1}" y2="{y1:.1}" stroke="{g}" stroke-width="1"/>
<text x="{x:.1}" y="{ty:.1}" font-size="9.5" fill="{muted}" text-anchor="middle">{lab}</text>
"##,
            x = x,
            y0 = pad_top - 6.0,
            y1 = plot_bottom,
            g = GRID,
            ty = pad_top - 11.0,
            muted = MUTED,
            lab = esc(&tick_label(t, c.tick_suffix))
        ));
        t += step;
    }
    s.push_str(&format!(
        r##"<line x1="{x0:.1}" y1="{y:.1}" x2="{x1:.1}" y2="{y:.1}" stroke="{a}" stroke-width="1"/>
"##,
        x0 = label_w,
        x1 = label_w + plot_w,
        y = plot_bottom,
        a = AXIS
    ));

    if let Some(r) = c.reference {
        let x = label_w + scale(r);
        s.push_str(&format!(
            r##"<line x1="{x:.1}" y1="{y0:.1}" x2="{x:.1}" y2="{y1:.1}" stroke="{fg}" stroke-width="1.2" stroke-dasharray="4 3"/>
<text x="{x:.1}" y="{ty:.1}" font-size="10" font-weight="600" fill="{fg}" text-anchor="middle">{lab}</text>
"##,
            x = x,
            y0 = pad_top - 6.0,
            y1 = plot_bottom + 4.0,
            ty = plot_bottom + 16.0,
            fg = FG,
            lab = esc(c.reference_label)
        ));
    }

    // ---------------------------------------------------------------- the bars
    for (i, b) in c.bars.iter().enumerate() {
        let y = pad_top + row_h * i as f64;
        let bw = scale(b.value).max(1.0);
        let colour = if b.is_baseline {
            BAR_BASE
        } else if b.within_noise {
            BAR_TIE
        } else {
            let worse = match c.better {
                Better::Lower => c.reference.map(|r| b.value > r).unwrap_or(false),
                Better::Higher => c.reference.map(|r| b.value < r).unwrap_or(false),
            };
            if worse {
                BAR_SLOW
            } else {
                BAR
            }
        };
        s.push_str(&format!(
            r##"<text x="{lx}" y="{ty:.1}" font-size="11" fill="{fg}" text-anchor="end">{label}</text>
<rect x="{bx}" y="{by:.1}" width="{bw:.1}" height="{bh}" rx="2" fill="{c}"/>
"##,
            lx = label_w - 10.0,
            ty = y + row_h * 0.68,
            fg = FG,
            label = esc(&b.label),
            bx = label_w,
            by = y + 5.0,
            bw = bw,
            bh = row_h - 11.0,
            c = colour,
        ));

        //  The whisker is the run's own spread. A bar drawn without it invites
        // exactly the reading docs/history/todo/RULES.md §4 warns against: a 5% lead read as
        // a result when the cell's own samples move by 6%.
        let mut note_x = label_w + bw + 6.0;
        if let Some(e) = b.err {
            if e > 0.0 {
                let lo = label_w + scale((b.value - e).max(0.0));
                let hi = label_w + scale(b.value + e);
                let cy = y + row_h * 0.5;
                s.push_str(&format!(
                    r##"<line x1="{lo:.1}" y1="{cy:.1}" x2="{hi:.1}" y2="{cy:.1}" stroke="{fg}" stroke-width="1" opacity="0.55"/>
<line x1="{lo:.1}" y1="{t:.1}" x2="{lo:.1}" y2="{b2:.1}" stroke="{fg}" stroke-width="1" opacity="0.55"/>
<line x1="{hi:.1}" y1="{t:.1}" x2="{hi:.1}" y2="{b2:.1}" stroke="{fg}" stroke-width="1" opacity="0.55"/>
"##,
                    lo = lo,
                    hi = hi,
                    cy = cy,
                    t = cy - 4.0,
                    b2 = cy + 4.0,
                    fg = FG
                ));
                note_x = hi + 6.0;
            }
        }
        s.push_str(&format!(
            r##"<text x="{vx:.1}" y="{ty:.1}" font-size="10.5" fill="{muted}">{val}</text>
"##,
            vx = note_x,
            ty = y + row_h * 0.68,
            muted = MUTED,
            val = esc(&b.note)
        ));
    }

    s.push_str(&format!(
        r##"<text x="16" y="{y:.1}" font-size="10" fill="{muted}">{unit}</text></svg>"##,
        y = height - 12.0,
        muted = MUTED,
        unit = esc(c.unit)
    ));
    s
}

pub fn direction_note(b: Better) -> &'static str {
    match b {
        Better::Lower => "lower is better",
        Better::Higher => "higher is better",
    }
}

/// `0.595` -> `40.5% faster`; `1.138` -> `13.8% slower`.
///
///  This is the form a reader acts on. A ratio is exact and a percentage is
/// legible, so both are printed and neither replaces the other.
pub fn rel_phrase(rel: f64, better_word: &str, worse_word: &str) -> String {
    let d = (rel - 1.0) * 100.0;
    if d.abs() < 0.05 {
        "same as control".into()
    } else if d < 0.0 {
        format!("{:.1}% {}", -d, better_word)
    } else {
        format!("{:.1}% {}", d, worse_word)
    }
}

fn label_of(r: &Row) -> String {
    let base = if r.variant == crate::model::DEFAULT_VARIANT {
        r.allocator.clone()
    } else {
        format!("{} {}", r.allocator, r.variant)
    };
    if r.integration == "baseline" {
        format!("{} (control)", base)
    } else {
        format!("{} / {}", base, r.integration)
    }
}

/// Is this row's distance from the control smaller than its own spread?
pub fn tie_with_control(rel: f64, rel_mad: Option<f64>) -> bool {
    match rel_mad {
        Some(mad) if mad.is_finite() && mad > 0.0 => (rel - 1.0).abs() < mad,
        _ => false,
    }
}

/// Relative execution time for one comparison group.
pub fn relative_time_chart(group: &str, rows: &[Row], workload: &str) -> Option<String> {
    let bars: Vec<Bar> = rows
        .iter()
        .filter_map(|r| {
            let rel = r.rel_time?;
            let tie = !r.is_baseline && tie_with_control(rel, r.rel_mad);
            //  THE LABEL AND THE COLOUR MUST AGREE. A bar drawn in the tie
            // colour beside the words "8.2% slower" tells the reader two
            // different things and invites them to believe the more specific
            // one -- which is the claim §9 forbids. Caught by regenerating a
            // real report and reading the picture, not by reading the code.
            let phrase = if tie {
                " inside its own noise".to_string()
            } else {
                rel_phrase(rel, "faster", "slower")
            };
            let note = match r.time_s {
                Some(t) => format!("{:.3}×  {}  ({:.3} s)", rel, phrase, t),
                None => format!("{:.3}×  {}", rel, phrase),
            };
            Some(Bar {
                label: label_of(r),
                value: rel,
                is_baseline: r.is_baseline,
                note,
                err: r.rel_mad.map(|m| m * rel),
                within_noise: tie,
            })
        })
        .collect();
    if bars.len() < 2 {
        return None;
    }
    Some(bar_chart(&Chart {
        title: &format!("Execution time relative to the control - {}", group),
        subtitle: &format!(
            "workload `{}`; median of the run's samples; whiskers are that cell's own relative MAD",
            workload
        ),
        unit: "Generated by `alloc-bench report`. Ratios are within one image, architecture, profile and toolchain - no ratio crosses a group.",
        bars,
        reference: Some(1.0),
        reference_label: "control = 1.000×",
        better: Better::Lower,
        tick_suffix: "×",
    }))
}

/// Peak RSS for one comparison group.
pub fn relative_rss_chart(group: &str, rows: &[Row], workload: &str) -> Option<String> {
    let bars: Vec<Bar> = rows
        .iter()
        .filter_map(|r| {
            let rel = r.rel_rss?;
            let note = match r.rss_kb {
                Some(v) => format!(
                    "{:.3}×  {}  ({:.1} MiB)",
                    rel,
                    rel_phrase(rel, "less memory", "more memory"),
                    v / 1024.0
                ),
                None => format!(
                    "{:.3}×  {}",
                    rel,
                    rel_phrase(rel, "less memory", "more memory")
                ),
            };
            Some(Bar {
                label: label_of(r),
                value: rel,
                is_baseline: r.is_baseline,
                note,
                //  No whisker: peak RSS is reported here as the median of the
                // samples' `ru_maxrss` and this project does not carry a
                // separate spread for it. Drawing the TIME spread on a memory
                // bar would be a fabricated error bar.
                err: None,
                within_noise: false,
            })
        })
        .collect();
    if bars.len() < 2 {
        return None;
    }
    Some(bar_chart(&Chart {
        title: &format!("Peak resident set relative to the control - {}", group),
        subtitle: &format!(
            "workload `{}`; `ru_maxrss` from `wait4`, median of the run's samples",
            workload
        ),
        unit: "Peak RSS is what sets a container's memory limit.  It is not the allocator's own idea of heap size, and it does NOT transfer between machines (docs/AGENTS.md).",
        bars,
        reference: Some(1.0),
        reference_label: "control = 1.000×",
        better: Better::Lower,
        tick_suffix: "×",
    }))
}

/// Binary size, absolute. A ratio chart would hide that every row is within a
/// few per cent of the same handful of megabytes.
pub fn size_chart(group: &str, rows: &[Row]) -> Option<String> {
    let base_mib = rows
        .iter()
        .find(|r| r.is_baseline)
        .and_then(|r| r.size_bytes)
        .map(|b| b as f64 / (1024.0 * 1024.0));
    let bars: Vec<Bar> = rows
        .iter()
        .filter_map(|r| {
            let b = r.size_bytes?;
            let mib = b as f64 / (1024.0 * 1024.0);
            let note = match base_mib {
                Some(base) if base > 0.0 && !r.is_baseline => format!(
                    "{:.2} MiB  {}",
                    mib,
                    rel_phrase(mib / base, "smaller", "larger")
                ),
                _ => format!("{:.2} MiB", mib),
            };
            Some(Bar {
                label: label_of(r),
                value: mib,
                is_baseline: r.is_baseline,
                note,
                err: None,
                within_noise: false,
            })
        })
        .collect();
    if bars.len() < 2 {
        return None;
    }
    Some(bar_chart(&Chart {
        title: &format!("Binary size - {}", group),
        subtitle: "unstripped, with symbols retained so the identity oracle can read the binary",
        unit:
            " These binaries keep `.symtab` on purpose; a shipped build would strip and be smaller. Size is the smallest of the three costs and the composite weights it 0.10.",
        bars,
        reference: base_mib,
        reference_label: "control",
        better: Better::Lower,
        tick_suffix: " MiB",
    }))
}
