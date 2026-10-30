"""Mock-up v3 of the Utilities page in the ESC menu, in the UWM CO-OP theme (CO-OP page v6, form v4):
spaced-caps labels, dark cards with a thin outline, green tint + outline for the selection, our icon in the header.
python -I menu_mockup_v3.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
HERE = os.path.dirname(os.path.abspath(__file__))
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

W, H = 2000, 1125
BG = (36, 37, 35); CARD = (28, 29, 27); SIDE = (20, 21, 19); BAR = (8, 8, 8)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); TINT = (50, 60, 28)
WHITE = (235, 235, 235); GREY = (170, 170, 165); DIM = (110, 112, 105); LINE = (62, 64, 58); EDGE = (46, 48, 43)
ORANGE = (230, 170, 60)

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

def page(path, tab):
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    icon = Image.open(os.path.join(HERE, "uwm_tabIcon_v1.png")).convert("RGBA")

    # the game's ESC tab column (other tabs as plain squares), ours selected
    d.rectangle([0, 0, 130, H], fill=SIDE)
    for i in range(9):
        y = 2 + i * 129
        if i == 2:
            d.rectangle([0, y, 130, y + 126], fill=GREEN)
            d.polygon([(130, y + 50), (146, y + 63), (130, y + 76)], fill=GREEN)
            im.paste(icon.resize((64, 64), Image.LANCZOS), (33, y + 31), icon.resize((64, 64), Image.LANCZOS))
        else:
            d.rounded_rectangle([40, y + 34, 90, y + 92], 6, outline=(200, 200, 200), width=3)
        d.line([0, y + 127, 130, y + 127], fill=(40, 41, 38))

    # header: our icon, UWM CO-OP over the page name, balance on the right
    big = icon.resize((76, 76), Image.LANCZOS)
    d.rounded_rectangle([250, 70, 342, 162], 12, fill=GREEN)
    im.paste(big, (258, 78), big)
    spaced(d, (370, 90), "UWM CO-OP", font(18, True), GREEN_L, 4)
    d.text((370, 130), "Utilities & Waste Management", font=font(40, True), fill=WHITE, anchor="lm")
    d.rounded_rectangle([1490, 78, 1848, 154], 10, fill=CARD, outline=EDGE)
    spaced(d, (1514, 100), "BALANCE", font(14, True), DIM, 3)
    d.text((1824, 128), "242,647 $", font=font(32, True), fill=GREEN_L, anchor="rm")
    d.line([250, 190, 1848, 190], fill=LINE)
    d.line([250, 190, 470, 190], fill=GREEN, width=3)

    # tabs: pill buttons in the theme, the open one tinted with an outline
    tabs = ["INCOMING", "OUTGOING", "STANDING ORDERS"]
    x = 250
    for i, t in enumerate(tabs):
        tw = spaced(ImageDraw.Draw(Image.new("RGB", (1, 1))), (0, 0), t, font(17, True), WHITE, 3)
        bw = tw + 64
        sel = i == tab
        d.rounded_rectangle([x, 214, x + bw, 262], 24, fill=TINT if sel else CARD, outline=GREEN_L if sel else EDGE, width=2 if sel else 1)
        spaced(d, (x + 32, 238), t, font(17, True), WHITE if sel else GREY, 3)
        x += bw + 16
    # Q / E hints for the tabs
    d.text((1848, 238), "Q / E  switch tabs", font=font(15), fill=DIM, anchor="rm")

    # the list in one card
    cx0, cx1, cy0, cy1 = 250, 1848, 290, 1000
    d.rounded_rectangle([cx0, cy0, cx1, cy1], 8, fill=CARD, outline=EDGE)
    cols = [(330, "INVOICE"), (470, "DAY"), (660, "FARM"), (1000, "GOODS"), (1300, "REPEATS"), (1520, "STATUS"), (1760, "AMOUNT")]
    for x, t in cols:
        spaced(d, (x, 326), t, font(14, True), DIM, 3, "m")
    d.line([cx0, 350, cx1, 350], fill=LINE)
    rows = [
        ("UWM-014", "Day 41", "Farm B", "Honey, 10,000 l  (pallets, -10 %)", "One-off", ("Waiting for you", GREEN_L), "297 $"),
        ("UWM-012", "Day 40", "Farm C", "Electricity, 4,123 kWh", "Every day", ("Active", GREEN_L), "1,443 $"),
        ("UWM-011", "Day 39", "Farm B", "Wheat, 30,000 l", "One-off", ("30,000 l at the depot", ORANGE), "6,000 $"),
        ("UWM-009", "Day 37", "Farm B", "Manure, 25,000 l", "One-off", ("6,000 l to collect", ORANGE), "825 $"),
        ("UWM-004", "Day 30", "Farm C", "Slurry, all in stock", "Every week", ("Done", DIM), "2,210 $"),
    ]
    for i, r in enumerate(rows):
        y = 380 + i * 52
        if i == 0:
            d.rounded_rectangle([cx0 + 12, y - 22, cx1 - 12, y + 22], 6, fill=TINT, outline=GREEN_L, width=2)
        elif i % 2 == 0:
            d.rectangle([cx0 + 12, y - 22, cx1 - 12, y + 22], fill=(31, 32, 30))
        for (x, _), val in zip(cols, r):
            text, col = (val if isinstance(val, tuple) else (val, WHITE))
            bold = x == 1760 or i == 0 and x == 330
            d.text((x, y), text, font=font(19, bold), fill=col, anchor="mm")
    # footer inside the page
    d.line([250, 1024, 1848, 1024], fill=LINE)
    d.text((262, 1052), "Depot member: your share of the upkeep is 134 $ a day", font=font(17), fill=GREY, anchor="lm")
    d.text((1836, 1052), "You are the farm manager", font=font(17), fill=GREY, anchor="rm")

    # the game's key bar (NEW opens the UWM CO-OP page)
    d.rectangle([0, 1085, W, H], fill=BAR)
    keys = [("X", "DETAILS"), ("ENTER", "ACCEPT AND PAY"), ("C", "DECLINE"), ("SPACE", "NEW"), ("V", "DEPOT"), ("ESC", "BACK")]
    widths = []
    for k, l in keys:
        widths.append(d.textlength(k, font=font(20, True)) + 30 + 12 + d.textlength(l, font=font(20, True)) + 26)
    x = W - sum(widths) - 10
    for (k, l), wdt in zip(keys, widths):
        kw = d.textlength(k, font=font(20, True)) + 30
        d.rounded_rectangle([x, 1089, x + kw, 1121], 5, fill=(30, 40, 30), outline=GREEN_L if k == "SPACE" else None, width=2)
        d.text((x + kw / 2, 1105), k, font=font(20, True), fill=GREEN_L, anchor="mm")
        d.text((x + kw + 12, 1105), l, font=font(20, True), fill=WHITE, anchor="lm")
        x += wdt
        d.line([x - 13, 1095, x - 13, 1115], fill=DIM)
    im.save(path)

page(os.path.join(sys.argv[1], "menu_v3_incoming.png"), 0)
