"""Mock-up of the tabbed Utilities page (user, 2026-10-24: "menu driven" like an invoicing page, not copied).
Usage: python -I previews\\menu_mockup_v1.py <outDir>   -> menu_v1_<view>.png"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 2000, 1125
BG = (35, 35, 35)
SIDE = (20, 20, 20)
GREEN = (126, 163, 24)
GREEN_TXT = (150, 196, 30)
WHITE = (235, 235, 235)
GREY = (150, 150, 150)
LINE = (70, 70, 70)
ROW_ALT = (42, 42, 42)
AMBER = (232, 176, 32)
BAR = (8, 8, 8)

F = "C:/Windows/Fonts/"
def font(size, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), size)


def centered(d, x, y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text((x - w / 2, y), text, font=f, fill=fill)


def sidebar(d):
    d.rectangle([0, 0, 130, H], fill=SIDE)
    for i in range(9):
        y = i * 129
        d.line([0, y, 130, y], fill=(45, 45, 45), width=2)
        active = i == 2
        if active:
            d.rectangle([0, y + 2, 130, y + 127], fill=GREEN)
            d.polygon([(130, y + 52), (146, y + 64), (130, y + 76)], fill=GREEN)
        # simple outline glyphs (placeholders for the game's own menu icons)
        cx, cy = 65, y + 64
        c = (20, 20, 20) if active else (200, 200, 200)
        d.rounded_rectangle([cx - 26, cy - 30, cx + 26, cy + 30], 6, outline=c, width=3)
        if active:  # our tab: the same drop + bolt as the page icon
            d.ellipse([cx - 14, cy - 4, cx + 14, cy + 24], fill=c)
            d.polygon([(cx, cy - 24), (cx - 13, cy + 3), (cx + 13, cy + 3)], fill=c)
            d.line([(cx + 3, cy - 6), (cx - 4, cy + 8), (cx + 4, cy + 8), (cx - 3, cy + 20)], fill=GREEN, width=3)


def header(d, balance):
    d.rounded_rectangle([288, 88, 358, 158], 18, fill=GREEN)
    cx, cy = 323, 123
    # icon: a drop with a bolt inside
    d.ellipse([cx - 16, cy - 6, cx + 16, cy + 26], fill=(25, 25, 25))
    d.polygon([(cx, cy - 28), (cx - 15, cy + 2), (cx + 15, cy + 2)], fill=(25, 25, 25))
    d.line([(cx + 3, cy - 8), (cx - 5, cy + 8), (cx + 5, cy + 8), (cx - 3, cy + 22)], fill=GREEN, width=4)
    d.text((378, 98), "UTILITIES & WASTE", font=font(44), fill=WHITE)
    d.text((380, 156), "Depot member: your share of the upkeep is $134 a day", font=font(19), fill=GREY)
    d.rounded_rectangle([1494, 87, 1814, 159], 22, fill=(18, 18, 18))
    f = font(30)
    label = "BALANCE:"
    value = balance
    total = d.textlength(label + "  ", font=f) + d.textlength(value, font=font(30, True))
    x = 1654 - total / 2
    d.text((x, 104), label, font=f, fill=WHITE)
    d.text((x + d.textlength(label + "  ", font=f), 104), value, font=font(30, True), fill=GREEN_TXT)


def tabs(d, y, names, active, left=None):
    f = font(21, True)
    widths = [d.textlength(n, font=f) + 44 for n in names]
    total = sum(widths) + 12 * (len(names) - 1)
    x = 1070 - total / 2
    d.ellipse([x - 92, y + 4, x - 48, y + 48], fill=(55, 55, 55))
    d.polygon([(x - 74, y + 26), (x - 64, y + 20), (x - 64, y + 32)], fill=WHITE)
    for i, n in enumerate(names):
        w = widths[i]
        if i == active:
            d.rounded_rectangle([x, y - 2, x + w, y + 54], 6, fill=GREEN)
            d.rectangle([x, y + 30, x + w, y + 54], fill=GREEN)
        centered(d, x + w / 2, y + 10, n, f, (20, 20, 20) if i == active else WHITE)
        x += w + 12
    x += 36
    d.ellipse([x, y + 4, x + 44, y + 48], fill=(55, 55, 55))
    d.polygon([(x + 18, y + 20), (x + 28, y + 26), (x + 18, y + 32)], fill=WHITE)
    d.line([252, y + 54, 1848, y + 54], fill=GREEN, width=2)


def table(d, y, columns, rows, empty=None, selected=0, colors=None):
    f = font(19, True)
    for name, cx, _ in columns:
        centered(d, cx, y, name, f, WHITE)
    d.line([252, y + 36, 1848, y + 36], fill=LINE, width=2)
    ry = y + 44
    rf = font(18)
    if not rows and empty:
        centered(d, 1070, y + 190, empty, font(20), GREY)
    for r, row in enumerate(rows):
        if r == selected:
            for k in range(40):  # soft ends like a game highlight
                a = min(k / 40, 1)
                c = tuple(int(BG[i] + (GREEN[i] - BG[i]) * a) for i in range(3))
                d.line([252 + k, ry, 252 + k, ry + 32], fill=c)
                d.line([1848 - k, ry, 1848 - k, ry + 32], fill=c)
            d.rectangle([292, ry, 1808, ry + 32], fill=GREEN)
        elif r % 2:
            d.rectangle([272, ry, 1828, ry + 32], fill=ROW_ALT)
        for c, (_, cx, _) in enumerate(columns):
            text = row[c]
            fill = (20, 20, 20) if r == selected else WHITE
            if colors and r != selected and colors.get((r, c)):
                fill = colors[(r, c)]
            centered(d, cx, ry + 4, text, rf if c != len(columns) - 1 else font(18, True), fill)
        ry += 34


def buttons(d, items):
    d.rectangle([0, 1084, W, H], fill=BAR)
    f = font(19, True)
    x = W - 14
    for key, label, enabled in reversed(items):
        lw = d.textlength(label, font=f)
        kw = max(d.textlength(key, font=f) + 22, 40)
        x -= lw
        d.text((x, 1094), label, font=f, fill=WHITE if enabled else (110, 110, 110))
        x -= 12 + kw
        d.rounded_rectangle([x, 1090, x + kw, 1120], 4, fill=(30, 40, 10))
        centered(d, x + kw / 2, 1094, key, f, GREEN_TXT if enabled else (90, 110, 40))
        x -= 24
        d.line([x + 10, 1094, x + 10, 1116], fill=(60, 60, 60), width=2)


def page():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    sidebar(d)
    header(d, "242,647 $")
    return img, d


MAIN_TABS = ["INCOMING", "OUTGOING", "STANDING ORDERS"]
BOARD_TABS = ["MARKET", "MY ORDERS", "MY DEALS"]
INV_COLS = [("INVOICE #", 340, 0), ("DAY", 470, 0), ("FARM", 660, 0), ("DESCRIPTION", 1010, 0), ("REPEATS", 1290, 0),
            ("STATUS", 1480, 0), ("AMOUNT", 1730, 0)]


def view_incoming(out):
    img, d = page()
    tabs(d, 184, MAIN_TABS, 0)
    rows = [
        ["UWM-014", "Day 41", "Green Acres", "Slurry, 10,000 l", "One-off", "Waiting for you", "330 $"],
        ["UWM-012", "Day 40", "Riverside Farm", "Electricity, 4,123 kWh", "Every day", "Active", "1,443 $"],
        ["UWM-009", "Day 37", "Green Acres", "Manure, 25,000 l", "One-off", "6,000 l to collect", "825 $"],
        ["UWM-004", "Day 30", "Riverside Farm", "Slurry, all in stock", "Every week", "Done", "2,210 $"],
    ]
    colors = {(1, 5): GREEN_TXT, (2, 5): AMBER, (3, 5): GREY}
    table(d, 280, INV_COLS, rows, colors=colors)
    d.line([252, 1014, 1848, 1014], fill=LINE, width=2)
    buttons(d, [("X", "DETAILS", True), ("ENTER", "ACCEPT AND PAY", True), ("C", "DECLINE", True),
                ("SPACE", "NEW INVOICE", True), ("V", "DEPOT", True), ("ESC", "BACK", True)])
    img.save(out / "menu_v1_incoming.png")


def view_outgoing(out):
    img, d = page()
    tabs(d, 184, MAIN_TABS, 1)
    rows = [
        ["UWM-015", "Day 41", "Riverside Farm", "Manure, 12,000 l", "One-off", "Waiting", "480 $"],
        ["UWM-011", "Day 39", "Green Acres", "Slurry, 50,000 l", "One-off", "Active", "500 $"],
    ]
    table(d, 280, INV_COLS, rows, colors={(1, 5): GREEN_TXT})
    d.line([252, 1014, 1848, 1014], fill=LINE, width=2)
    buttons(d, [("X", "DETAILS", True), ("C", "WITHDRAW", True), ("SPACE", "NEW INVOICE", True),
                ("V", "DEPOT", True), ("ESC", "BACK", True)])
    img.save(out / "menu_v1_outgoing.png")


BOARD_COLS = [("FARM", 400, 0), ("TYPE", 640, 0), ("PRODUCT", 840, 0), ("LEFT", 1060, 0), ("OF", 1260, 0),
              ("PRICE / 1,000 L", 1500, 0), ("HELD", 1740, 0)]


def view_market(out, empty=False):
    img, d = page()
    tabs(d, 184, MAIN_TABS, 2)
    tabs(d, 316, BOARD_TABS, 0)
    rows = [] if empty else [
        ["Green Acres", "For sale", "Slurry", "850,000 l", "1,000,000 l", "10 $", "Stock"],
        ["Riverside Farm", "Wanted", "Manure", "40,000 l", "60,000 l", "35 $", "Money"],
        ["Riverside Farm", "For sale", "Electricity", "12,500 kWh", "20,000 kWh", "350 $ / 1,000 kWh", "Stock"],
    ]
    table(d, 400, BOARD_COLS, rows, empty="No standing orders from other farms right now.",
          colors={(1, 1): AMBER, (0, 1): GREEN_TXT, (2, 1): GREEN_TXT})
    # lower panel, like a summary block
    d.line([236, 776, 1864, 776], fill=GREEN, width=2)
    d.text((248, 790), "YOUR DEALS ON STANDING ORDERS (THIS MONTH)", font=font(21, True), fill=WHITE)
    d.line([236, 830, 1864, 830], fill=LINE, width=2)
    cols = [("FARM", 520, 0), ("PRODUCT", 860, 0), ("VOLUME", 1160, 0), ("AMOUNT", 1420, 0), ("TO COLLECT", 1680, 0)]
    f = font(19, True)
    for n, cx, _ in cols:
        centered(d, cx, 846, n, f, WHITE)
    d.line([236, 880, 1864, 880], fill=LINE, width=2)
    if not empty:
        for c, (_, cx, _) in enumerate(cols):
            centered(d, cx, 890, ["Green Acres", "Slurry", "50,000 l", "500 $", "50,000 l"][c], font(18), WHITE)
    label = "BUY" if not empty else "BUY"
    buttons(d, [("ENTER", "BUY / SELL TO THEM", not empty), ("X", "DETAILS", not empty), ("SPACE", "NEW STANDING ORDER", True),
                ("V", "DEPOT", True), ("ESC", "BACK", True)])
    img.save(out / ("menu_v1_market_empty.png" if empty else "menu_v1_market.png"))


def view_myorders(out):
    img, d = page()
    tabs(d, 184, MAIN_TABS, 2)
    tabs(d, 316, BOARD_TABS, 1)
    cols = [("ORDER #", 340, 0), ("TYPE", 520, 0), ("PRODUCT", 700, 0), ("LEFT", 900, 0), ("OF", 1100, 0), ("DEALS", 1260, 0),
            ("PRICE / 1,000 L", 1450, 0), ("STATUS", 1700, 0)]
    rows = [
        ["SO-003", "For sale", "Slurry", "850,000 l", "1,000,000 l", "2", "10 $", "Open"],
        ["SO-002", "Wanted", "Electricity", "0 kWh", "20,000 kWh", "4", "300 $", "Complete"],
        ["SO-001", "For sale", "Manure", "3,000 l", "4,000 l", "1", "40 $", "Withdrawn"],
    ]
    table(d, 400, cols, rows, colors={(1, 7): GREY, (2, 7): AMBER})
    d.line([252, 1014, 1848, 1014], fill=LINE, width=2)
    buttons(d, [("X", "DETAILS", True), ("C", "WITHDRAW", True), ("SPACE", "NEW STANDING ORDER", True),
                ("V", "DEPOT", True), ("ESC", "BACK", True)])
    img.save(out / "menu_v1_myorders.png")


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    view_incoming(out)
    view_outgoing(out)
    view_market(out)
    view_market(out, empty=True)
    view_myorders(out)
    print("done")
