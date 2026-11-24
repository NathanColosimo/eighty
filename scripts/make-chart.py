#!/usr/bin/env python3
"""Draws docs/battery-wear.svg, the README chart. Standard library only.

Data: Battery University, BU-808 "How to Prolong Lithium-based Batteries",
Table 3 (capacity after a year of storage) and Table 4 (cycles by charge
voltage limit; 4.20 V = 100%, 4.13 V ~ 90%, 4.06 V ~ 81%).
"""
from pathlib import Path

W, H = 1600, 900
SURFACE, INK, INK_2, INK_3, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#8a8984", "#e6e5e1"
NEUTRAL, HOT, GOOD = "#c9c8c2", "#eb6834", "#1baf7a"
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"

heat = [  # label, % capacity left after a year at full charge, colour
    ("Cool  0 °C", 94, NEUTRAL),
    ("Room  25 °C", 80, NEUTRAL),
    ("Warm  40 °C", 65, HOT),
]
ceiling = [  # label, cycles low, cycles high, colour
    ("100%", 300, 500, NEUTRAL),
    ("~90%", 400, 700, NEUTRAL),
    ("~80%", 600, 1000, GOOD),
]

out = []
def text(x, y, s, size, color=INK, weight=400, anchor="start"):
    out.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{s}</text>')

def bar(x, y, w, h, color):
    # Square at the baseline, 4px rounded at the data end.
    r = 4
    out.append(
        f'<path d="M{x},{y} H{x + w - r} Q{x + w},{y} {x + w},{y + r} V{y + h - r} '
        f'Q{x + w},{y + h} {x + w - r},{y + h} H{x} Z" fill="{color}"/>')

def range_bar(x0, x1, y, h, color):
    out.append(f'<rect x="{x0}" y="{y}" width="{x1 - x0}" height="{h}" rx="4" fill="{color}"/>')

def panel(x, title, subtitle, note):
    text(x, 300, title, 34, weight=700)
    text(x, 340, subtitle, 22, INK_2)
    text(x, 770, note, 24, INK, weight=600)

# Header
text(80, 120, "Plugged in all day? Two things wear out your battery.", 52, weight=750)
text(80, 172, "Eighty fixes both, for free: it stops charging at 80% and pauses charging while the battery is hot.", 26, INK_2)

# Panel 1: heat, capacity left after a year kept full
px, label_w, plot_w = 80, 170, 480
panel(px, "1. Heat", "Capacity left after a year kept at 100%", "Heat nearly doubles the loss: 20% → 35% a year.")
x0 = px + label_w
for tick in (0, 25, 50, 75, 100):
    gx = x0 + plot_w * tick / 100
    out.append(f'<line x1="{gx}" y1="380" x2="{gx}" y2="690" stroke="{GRID}" stroke-width="1"/>')
    text(gx, 718, f"{tick}%", 18, INK_3, anchor="middle")
for i, (label, value, color) in enumerate(heat):
    y = 400 + i * 98
    text(px, y + 38, label, 24, INK_2)
    bar(x0, y, plot_w * value / 100, 56, color)
    text(x0 + plot_w * value / 100 + 12, y + 38, f"{value}%", 24, INK, weight=650)

# Panel 2: charge ceiling, cycles before wear-out
px2, label_w2, plot_w2, max_cycles = 860, 110, 470, 1000
panel(px2, "2. Charging to 100%", "Charge cycles before the battery is worn, by where charging stops",
      "Stopping at ~80% roughly doubles battery life.")
x0 = px2 + label_w2
for tick in (0, 250, 500, 750, 1000):
    gx = x0 + plot_w2 * tick / max_cycles
    out.append(f'<line x1="{gx}" y1="380" x2="{gx}" y2="690" stroke="{GRID}" stroke-width="1"/>')
    text(gx, 718, f"{tick:,}", 18, INK_3, anchor="middle")
for i, (label, low, high, color) in enumerate(ceiling):
    y = 400 + i * 98
    text(px2, y + 38, label, 24, INK_2)
    range_bar(x0 + plot_w2 * low / max_cycles, x0 + plot_w2 * high / max_cycles, y, 56, color)
    text(x0 + plot_w2 * high / max_cycles + 12, y + 38, f"{low:,}–{high:,}", 24, INK, weight=650)
text(x0 + plot_w2 * 600 / max_cycles, 400 + 2 * 98 + 56 + 30, "Eighty’s default", 20, INK_2, weight=600)

# Footer
out.append(f'<line x1="80" y1="815" x2="{W - 80}" y2="815" stroke="{GRID}" stroke-width="1"/>')
text(W - 80, 855, "github.com/NathanColosimo/eighty", 20, INK_2, weight=600, anchor="end")

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
       f'font-family="{FONT}" role="img" aria-label="Battery wear: heat and charging to 100%">'
       f'<rect width="{W}" height="{H}" fill="{SURFACE}"/>' + "".join(out) + "</svg>\n")
path = Path(__file__).resolve().parent.parent / "docs" / "battery-wear.svg"
path.parent.mkdir(exist_ok=True)
path.write_text(svg)
print(path)
