"""Mock-up v4 of the Utilities page (ESC menu), rebuilt in the UWM CO-OP theme of invoice_wizard_v6_choice.png:
every invoice is a card like the CO-OP options (icon tile per good, title + detail line, status pill, amount, arrow),
summary cards on top, rounded tab buttons. python -I menu_mockup_v4.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
HERE = os.path.dirname(os.path.abspath(__file__))
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

W, H = 2000, 1125
BG = (36, 37, 35); CARD = (28, 29, 27); SIDE = (20, 21, 19); BAR = (8, 8, 8); TILE = (40, 44, 34)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); TINT = (50, 60, 28)
WHITE = (235, 235, 235); GREY = (170, 170, 165); DIM = (110, 112, 105); LINE = (62, 64, 58); EDGE = (46, 48, 43)
ORANGE = (230, 170, 60); BLUE = (110, 170, 230)

def spaced(d, xy, text, fnt, fill, spacing=3, anchor="l"):
    x, y = xy
    total = sum(d.textlength(c, font=fnt) + spacing for c in text) - spacing
    if anchor == "m":
        x -= total / 2
    elif anchor == "r":
        x -= total
    for c in text:
        d.text((x, y), c, font=fnt, fill=fill, anchor="lm")
        x += d.textlength(c, font=fnt) + spacing
    return total

# goods icons (line style, as the CO-OP option icons)
def ic_slurry(d, cx, cy, c):
    d.polygon([(cx, cy - 16), (cx - 11, cy + 2), (cx + 11, cy + 2)], fill=c)
    d.ellipse([cx - 11, cy - 8, cx + 11, cy + 14], fill=c)
def ic_manure(d, cx, cy, c):
    d.pieslice([cx - 17, cy - 8, cx + 17, cy + 26], 180, 360, fill=c)
    d.line([cx - 17, cy + 9, cx + 17, cy + 9], fill=c, width=3)
def ic_power(d, cx, cy, c):
    d.polygon([(cx + 3, cy - 17), (cx - 10, cy + 2), (cx - 1, cy + 2), (cx - 4, cy + 17), (cx + 10, cy - 3), (cx + 1, cy - 3)], fill=c)
def ic_bulk(d, cx, cy, c):                       # a grain ear
    d.line([cx, cy + 17, cx, cy - 15], fill=c, width=3)
    for k in range(4):
        y = cy - 10 + k * 7
        d.ellipse([cx - 10, y - 3, cx - 1, y + 3], fill=c)
        d.ellipse([cx + 1, y - 3, cx + 10, y + 3], fill=c)
def ic_pallet(d, cx, cy, c):                     # a box on a pallet
    d.rectangle([cx - 13, cy - 15, cx + 13, cy + 5], outline=c, width=3)
    d.line([cx - 17, cy + 9, cx + 17, cy + 9], fill=c, width=3)
    for x in (cx - 15, cx, cx + 15):
        d.line([x, cy + 9, x, cy + 15], fill=c, width=3)
ICONS = {"slurry": ic_slurry, "manure": ic_manure, "power": ic_power, "bulk": ic_bulk, "pallet": ic_pallet}

def pill(d, xr, y, text, col):
    f = font(16, True)
    tw = d.textlength(text, font=f)
    d.rounded_rectangle([xr - tw - 28, y - 15, xr, y + 15], 15, outline=col, width=2)
    d.text((xr - 14, y), text, font=f, fill=col, anchor="rm")

def page(path):
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    icon = Image.open(os.path.join(HERE, "uwm_tabIcon_v1.png")).convert("RGBA")

    # the game's ESC tab column, ours selected
    d.rectangle([0, 0, 130, H], fill=SIDE)
    for i in range(9):
        y = 2 + i * 129
        if i == 2:
            d.rectangle([0, y, 130, y + 126], fill=GREEN)
            d.polygon([(130, y + 50), (146, y + 63), (130, y + 76)], fill=GREEN)
            small = icon.resize((64, 64), Image.LANCZOS)
            im.paste(small, (33, y + 31), small)
        else:
            d.rounded_rectangle([40, y + 34, 90, y + 92], 6, outline=(200, 200, 200), width=3)
        d.line([0, y + 127, 130, y + 127], fill=(40, 41, 38))

    # header
    big = icon.resize((70, 70), Image.LANCZOS)
    d.rounded_rectangle([250, 56, 336, 142], 12, fill=GREEN)
    im.paste(big, (258, 64), big)
    spaced(d, (364, 76), "UWM CO-OP", font(18, True), GREEN_L, 4)
    d.text((364, 114), "Utilities & Waste Management", font=font(38, True), fill=WHITE, anchor="lm")
    d.text((364, 148), "Community Depot  -  owner Farm A  -  you are a member", font=font(17), fill=GREY, anchor="lm")
    d.rounded_rectangle([1520, 62, 1848, 140], 10, fill=CARD, outline=EDGE)
    spaced(d, (1544, 84), "BALANCE", font(14, True), DIM, 3)
    d.text((1824, 112), "242,647 $", font=font(32, True), fill=GREEN_L, anchor="rm")

    # summary cards (what needs you, what's running, what waits at the depot)
    sums = [("WAITING FOR YOU", "2", "invoices to accept", GREEN_L), ("RUNNING", "3", "contracts and deals", BLUE),
            ("AT THE DEPOT FOR YOU", "36,000 l", "to collect", ORANGE), ("YOUR GOODS FOR SALE", "60,000 l", "at the depot", GREY)]
    sw = (1848 - 250 - 3 * 18) / 4
    for i, (t, v, sub, col) in enumerate(sums):
        x0 = 250 + i * (sw + 18)
        d.rounded_rectangle([x0, 176, x0 + sw, 262], 8, fill=CARD, outline=EDGE)
        d.rectangle([x0 + 1, 190, x0 + 4, 248], fill=col)
        spaced(d, (x0 + 22, 198), t, font(13, True), DIM, 3)
        d.text((x0 + 22, 234), v, font=font(28, True), fill=WHITE, anchor="lm")
        d.text((x0 + 26 + d.textlength(v, font=font(28, True)), 238), sub, font=font(16), fill=GREY, anchor="lm")

    # tabs (rounded buttons), with counts
    tabs = [("INCOMING", "2"), ("OUTGOING", "3"), ("STANDING ORDERS", "1")]
    x = 250
    for i, (t, n) in enumerate(tabs):
        tw = spaced(ImageDraw.Draw(Image.new("RGB", (1, 1))), (0, 0), t, font(17, True), WHITE, 3)
        bw = tw + 104
        sel = i == 0
        d.rounded_rectangle([x, 290, x + bw, 338], 24, fill=TINT if sel else CARD, outline=GREEN_L if sel else EDGE, width=2 if sel else 1)
        spaced(d, (x + 30, 314), t, font(17, True), WHITE if sel else GREY, 3)
        d.ellipse([x + bw - 52, 300, x + bw - 24, 328], fill=GREEN if sel else TILE)
        d.text((x + bw - 38, 314), n, font=font(15, True), fill=(28, 34, 12) if sel else GREY, anchor="mm")
        x += bw + 16
    d.line([250, 360, 1848, 360], fill=LINE)

    # invoice cards (as the CO-OP options)
    rows = [
        ("pallet", "Honey  -  10,000 l on pallets", "UWM-014  -  from Farm B  -  Day 41  -  one-off  -  10 % off", ("WAITING FOR YOU", GREEN_L), "297 $"),
        ("power", "Electricity  -  4,123 kWh", "UWM-012  -  from Farm C  -  Day 40  -  every day  -  into Bakery", ("ACTIVE", BLUE), "1,443 $"),
        ("bulk", "Wheat  -  30,000 l", "UWM-011  -  from Farm B  -  Day 39  -  Farma silo pipe", ("30,000 L TO COLLECT", ORANGE), "6,000 $"),
        ("manure", "Manure  -  25,000 l", "UWM-009  -  from Farm B  -  Day 37  -  manure pit", ("6,000 L TO COLLECT", ORANGE), "825 $"),
        ("slurry", "Slurry  -  all in stock", "UWM-004  -  from Farm C  -  Day 30  -  every week", ("DONE", DIM), "2,210 $"),
    ]
    for i, (ic, title, sub, (status, scol), amount) in enumerate(rows):
        y = 380 + i * 116
        sel = i == 0
        x0, x1 = 250, 1848
        d.rounded_rectangle([x0, y, x1, y + 100], 8, fill=TINT if sel else CARD, outline=GREEN_L if sel else EDGE, width=2 if sel else 1)
        d.rounded_rectangle([x0 + 20, y + 20, x0 + 80, y + 80], 8, fill=GREEN if sel else TILE)
        ICONS[ic](d, x0 + 50, y + 50, (28, 34, 12) if sel else GREEN_L)
        d.text((x0 + 104, y + 36), title, font=font(22, True), fill=WHITE, anchor="lm")
        d.text((x0 + 104, y + 68), sub, font=font(17), fill=(205, 205, 200) if sel else GREY, anchor="lm")
        pill(d, 1560, y + 50, status, scol)
        d.text((1740, y + 50), amount, font=font(24, True), fill=WHITE, anchor="rm")
        ax = x1 - 38
        d.line([ax - 6, y + 40, ax + 4, y + 50, ax - 6, y + 60], fill=GREEN_L if sel else DIM, width=3)

    # footer
    d.text((262, 1060), "Depot share: 134 $ a day  -  You are the farm manager", font=font(17), fill=GREY, anchor="lm")

    # key bar
    d.rectangle([0, 1085, W, H], fill=BAR)
    keys = [("X", "DETAILS"), ("ENTER", "ACCEPT AND PAY"), ("C", "DECLINE"), ("SPACE", "NEW"), ("V", "DEPOT"), ("ESC", "BACK")]
    widths = [d.textlength(k, font=font(20, True)) + 30 + 12 + d.textlength(l, font=font(20, True)) + 26 for k, l in keys]
    x = W - sum(widths) - 10
    for (k, l), wdt in zip(keys, widths):
        kw = d.textlength(k, font=font(20, True)) + 30
        d.rounded_rectangle([x, 1089, x + kw, 1121], 5, fill=(30, 40, 30), outline=GREEN_L if k == "SPACE" else None, width=2)
        d.text((x + kw / 2, 1105), k, font=font(20, True), fill=GREEN_L, anchor="mm")
        d.text((x + kw + 12, 1105), l, font=font(20, True), fill=WHITE, anchor="lm")
        x += wdt
        d.line([x - 13, 1095, x - 13, 1115], fill=DIM)
    im.save(path)

page(os.path.join(sys.argv[1], "menu_v4_incoming.png"))
