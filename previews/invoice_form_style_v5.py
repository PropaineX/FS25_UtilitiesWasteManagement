"""Mock-up v5 of the NEW INVOICE form in the full UWM CO-OP theme (as menu_v4_incoming.png and
invoice_wizard_v6_choice.png): outlined cards (no left strips), icon tiles on goods and the depot, the selection =
green outline + soft fill + solid tile, status pills, arrows on Bulk / Pallet. Same content as v4.
python -I invoice_form_style_v5.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
HERE = os.path.dirname(os.path.abspath(__file__))
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)

BG = (36, 37, 35); CARD = (28, 29, 27); BAR = (8, 8, 8); TILE = (40, 44, 34); FIELD = (24, 25, 23)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); TINT = (50, 60, 28); DARKG = (28, 34, 12)
WHITE = (235, 235, 235); GREY = (170, 170, 165); DIM = (110, 112, 105); LINE = (62, 64, 58); EDGE = (46, 48, 43)

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

# icons (same drawings as the Utilities page), scale s
def ic_slurry(d, cx, cy, c, s=1):
    d.polygon([(cx, cy - 16 * s), (cx - 11 * s, cy + 2 * s), (cx + 11 * s, cy + 2 * s)], fill=c)
    d.ellipse([cx - 11 * s, cy - 8 * s, cx + 11 * s, cy + 14 * s], fill=c)
def ic_manure(d, cx, cy, c, s=1):
    d.pieslice([cx - 17 * s, cy - 8 * s, cx + 17 * s, cy + 26 * s], 180, 360, fill=c)
def ic_power(d, cx, cy, c, s=1):
    d.polygon([(cx + 3 * s, cy - 17 * s), (cx - 10 * s, cy + 2 * s), (cx - 1 * s, cy + 2 * s), (cx - 4 * s, cy + 17 * s),
               (cx + 10 * s, cy - 3 * s), (cx + 1 * s, cy - 3 * s)], fill=c)
def ic_bulk(d, cx, cy, c, s=1):
    d.line([cx, cy + 17 * s, cx, cy - 15 * s], fill=c, width=max(2, int(3 * s)))
    for k in range(4):
        y = cy + (-10 + k * 7) * s
        d.ellipse([cx - 10 * s, y - 3 * s, cx - 1 * s, y + 3 * s], fill=c)
        d.ellipse([cx + 1 * s, y - 3 * s, cx + 10 * s, y + 3 * s], fill=c)
def ic_pallet(d, cx, cy, c, s=1):
    w = max(2, int(3 * s))
    d.rectangle([cx - 13 * s, cy - 15 * s, cx + 13 * s, cy + 5 * s], outline=c, width=w)
    d.line([cx - 17 * s, cy + 9 * s, cx + 17 * s, cy + 9 * s], fill=c, width=w)
    for x in (cx - 15 * s, cx, cx + 15 * s):
        d.line([x, cy + 9 * s, x, cy + 15 * s], fill=c, width=w)
def ic_farm(d, cx, cy, c, s=1):                  # a barn
    d.polygon([(cx - 15 * s, cy - 2 * s), (cx, cy - 15 * s), (cx + 15 * s, cy - 2 * s)], fill=c)
    d.rectangle([cx - 12 * s, cy - 2 * s, cx + 12 * s, cy + 14 * s], fill=c)
    d.rectangle([cx - 4 * s, cy + 4 * s, cx + 4 * s, cy + 14 * s], fill=DARKG if c != DARKG else GREEN)
def ic_depot(d, cx, cy, c, s=1):                 # a silo + tank
    d.rounded_rectangle([cx - 15 * s, cy - 12 * s, cx - 3 * s, cy + 15 * s], 4, fill=c)
    d.rectangle([cx + 1 * s, cy - 2 * s, cx + 16 * s, cy + 15 * s], fill=c)

def tile(d, x, y, size, sel, icon, s):
    d.rounded_rectangle([x, y, x + size, y + size], 7, fill=GREEN if sel else TILE)
    icon(d, x + size / 2, y + size / 2, DARKG if sel else GREEN_L, s)

def card(d, x0, y0, x1, y1, title=None, right=None):
    d.rounded_rectangle([x0, y0, x1, y1], 8, fill=CARD, outline=EDGE)
    if title:
        spaced(d, (x0 + 20, y0 + 26), title, font(14, True), DIM, 3)
        if right:
            d.text((x1 - 18, y0 + 26), right[0], font=font(16, True), fill=right[1], anchor="rm")
        d.line([x0 + 1, y0 + 50, x1 - 1, y0 + 50], fill=LINE)

def pick(d, x0, x1, y, text, right, sel, icon, arrow=False):
    h = 46
    if sel:
        d.rounded_rectangle([x0, y - h / 2, x1, y + h / 2], 7, fill=TINT, outline=GREEN_L, width=2)
    tile(d, x0 + 8, y - 17, 34, sel, icon, 0.62)
    d.text((x0 + 54, y), text, font=font(18, sel), fill=WHITE if sel else (215, 215, 210), anchor="lm")
    rx = x1 - 12
    if arrow:
        d.line([rx - 8, y - 7, rx, y, rx - 8, y + 7], fill=GREEN_L if sel else DIM, width=3)
        rx -= 22
    if right:
        d.text((rx, y), right, font=font(16, True), fill=GREEN_L, anchor="rm")

def pill(d, xr, y, text, col):
    f = font(13, True)
    tw = d.textlength(text, font=f)
    d.rounded_rectangle([xr - tw - 22, y - 12, xr, y + 12], 12, outline=col, width=2)
    d.text((xr - 11, y), text, font=f, fill=col, anchor="rm")

def form(path):
    w, h = 1240, 1140
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 10, w - 6, 1062], 10, fill=BG)

    # header: green icon tile, UWM CO-OP, title, issuer card
    icon = Image.open(os.path.join(HERE, "uwm_tabIcon_v1.png")).convert("RGBA").resize((50, 50), Image.LANCZOS)
    d.rounded_rectangle([40, 30, 104, 94], 10, fill=GREEN)
    im.paste(icon, (47, 37), icon)
    spaced(d, (124, 46), "UWM CO-OP", font(15, True), GREEN_L, 4)
    d.text((124, 76), "New invoice", font=font(28, True), fill=WHITE, anchor="lm")
    d.rounded_rectangle([1000, 34, 1200, 90], 8, fill=CARD, outline=EDGE)
    spaced(d, (1018, 50), "ISSUER", font(12, True), DIM, 3)
    d.text((1184, 72), "Farm A", font=font(20, True), fill=WHITE, anchor="rm")
    d.line([40, 112, w - 40, 112], fill=LINE)

    # three columns
    cols = [(40, 412), (430, 802), (820, 1200)]
    for (x0, x1), t in zip(cols, ["CUSTOMER", "GOODS", "PICKUP"]):
        card(d, x0, 132, x1, 612, t)
    for i, name in enumerate(["Farm A", "Farm B", "Farm C", "Farm D"]):
        pick(d, 52, 400, 214 + i * 54, name, "", i == 1, ic_farm)
    goods = [("Slurry", "8 $ /1,000 l", ic_slurry, False), ("Manure", "12 $ /1,000 l", ic_manure, False),
             ("Electricity", "180 $ /1,000 kWh", ic_power, False), ("Bulk", "", ic_bulk, True), ("Pallet", "Honey", ic_pallet, True)]
    for i, (g, p, ic, arrow) in enumerate(goods):
        pick(d, 442, 790, 214 + i * 54, g, p, i == 4, ic, arrow)
    # pickup: the depot as a selected item with a FIXED pill
    d.rounded_rectangle([832, 191, 1188, 237], 7, fill=TINT, outline=GREEN_L, width=2)
    tile(d, 840, 197, 34, True, ic_depot, 0.62)
    d.text((886, 214), "Utilities Depot", font=font(18, True), fill=WHITE, anchor="lm")
    pill(d, 1176, 214, "FIXED", GREEN_L)
    info = [("Owner", "Farm A"), ("Pickup point", "Pallet pad"), ("Your honey on pallets", "546,500 l"),
            ("At the depot for sale", "60,000 l"), ("Free to sell", "486,500 l")]
    for i, (k, v) in enumerate(info):
        y = 268 + i * 36
        d.text((846, y), k, font=font(16), fill=GREY, anchor="lm")
        d.text((1176, y), v, font=font(16, True), fill=GREEN_L if i == 4 else WHITE, anchor="rm")
        if i < 4:
            d.line([846, y + 18, 1176, y + 18], fill=(42, 44, 40))
    d.text((1010, 466), "New pallets for the buyer appear on the pallet pad.", font=font(14), fill=DIM, anchor="mm")
    # pallet size: a rounded button with a tile, like a CO-OP option
    d.rounded_rectangle([846, 492, 1176, 548], 8, fill=FIELD, outline=GREEN_L, width=2)
    tile(d, 856, 502, 36, False, ic_pallet, 0.65)
    spaced(d, (904, 510), "PALLET SIZE", font(12, True), DIM, 3)
    d.text((904, 532), "1,000 l", font=font(18, True), fill=WHITE, anchor="lm")
    d.text((1160, 520), "1,000 / 5,000", font=font(13), fill=DIM, anchor="rm")
    d.line([1166 - 128, 510, 1166 - 128, 530], fill=EDGE)

    # the invoice line
    card(d, 40, 632, 1200, 784, "INVOICE LINE", ("Customer:  Farm B", GREEN_L))
    xs = [(150, "GOODS"), (300, "PICKUP"), (430, "QTY"), (520, "UNIT"), (650, "PRICE"), (785, "DISCOUNT"), (915, "REPEAT"), (1090, "AMOUNT")]
    for x, t in xs:
        spaced(d, (x, 702), t, font(12, True), DIM, 2, "m")
    d.rounded_rectangle([52, 722, 1188, 770], 7, fill=TINT, outline=GREEN_L, width=2)
    tile(d, 60, 729, 34, True, ic_pallet, 0.62)
    row = ["Honey", "Pallet pad", "10,000", "l", "33 $ /1,000 l", "10 %", "One-off", "297 $"]
    for (x, _), t in zip(xs, row):
        d.text((x + (14 if t == "Honey" else 0), 746), t, font=font(17, t == "297 $"), fill=WHITE, anchor="mm")

    # inputs: outlined fields, the choices with a little arrow
    fields = [(40, 252, "PRICE / 1,000 L", "33", "pen"), (268, 480, "AMOUNT", "Set amount", "drop"),
              (496, 708, "AMOUNT IN LITERS", "10,000", "pen"), (724, 936, "DISCOUNT %", "10", "pen"), (952, 1200, "REPEAT", "One-off", "drop")]
    for x0, x1, lab, val, kind in fields:
        spaced(d, ((x0 + x1) / 2, 812), lab, font(12, True), DIM, 2, "m")
        d.rounded_rectangle([x0, 828, x1, 866], 8, fill=FIELD, outline=EDGE)
        d.text(((x0 + x1) / 2, 847), val, font=font(17), fill=WHITE, anchor="mm")
        if kind == "pen":
            d.line([x1 - 22, 853, x1 - 11, 842], fill=GREY, width=4)
        else:
            d.line([x1 - 24, 843, x1 - 17, 850, x1 - 10, 843], fill=GREEN_L, width=3)
    d.text((40, 882), "The game's price: 32 $ per 1,000 liters", font=font(14), fill=DIM, anchor="lm")

    # total
    d.rounded_rectangle([40, 902, 1200, 1040], 8, fill=(22, 23, 21), outline=EDGE)
    spaced(d, (64, 946), "TOTAL DUE", font(14, True), DIM, 3)
    d.text((64, 990), "297 $", font=font(40, True), fill=GREEN_L, anchor="lm")
    pill(d, 290, 992, "10 % OFF", GREEN_L)
    d.text((1176, 940), "Subtotal", font=font(15), fill=GREY, anchor="rm")
    d.text((1176, 964), "330 $", font=font(19, True), fill=WHITE, anchor="rm")
    d.text((1176, 996), "Discount 10 %", font=font(15), fill=GREY, anchor="rm")
    d.text((1176, 1020), "-33 $", font=font(19, True), fill=GREEN_L, anchor="rm")
    d.line([1010, 980, 1176, 980], fill=EDGE)

    # key bar
    def key(x, k, label):
        kw = d.textlength(k, font=font(22, True)) + 36
        d.rounded_rectangle([x, 1078, x + kw, 1118], 6, fill=(30, 40, 30))
        d.text((x + kw / 2, 1098), k, font=font(22, True), fill=GREEN_L, anchor="mm")
        d.text((x + kw + 14, 1098), label, font=font(22, True), fill=WHITE, anchor="lm")
        return x + kw + 14 + d.textlength(label, font=font(22, True))
    x = key(640, "ENTER", "SEND INVOICE")
    d.line([x + 14, 1086, x + 14, 1110], fill=DIM)
    key(x + 30, "ESC", "CANCEL")
    im.save(path)

form(os.path.join(sys.argv[1], "invoice_form_style_v5.png"))
