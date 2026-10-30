"""Mock-up v4 of the NEW INVOICE form in our own look (user 2026-10-28: drop 01/02/03, make it look like our work).
Same content as goods_pallet_v3_chosen.png (pallet honey example); only the style changes.
python -I invoice_form_style_v4.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
HERE = os.path.dirname(os.path.abspath(__file__))
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

BG = (36, 37, 35); CARD = (28, 29, 27); CARD_HEAD = (33, 35, 31); BAR = (8, 8, 8)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); TINT = (52, 62, 30)
WHITE = (235, 235, 235); GREY = (165, 165, 160); DIM = (110, 112, 105); LINE = (62, 64, 58)

def check(d, x, y, col=GREEN_L):
    d.line([x, y, x + 6, y + 7, x + 18, y - 8], fill=col, width=3)

def pencil(d, x, y):
    d.line([x - 6, y + 6, x + 5, y - 5], fill=GREY, width=4)
    d.polygon([(x - 8, y + 8), (x - 7, y + 3), (x - 3, y + 7)], fill=GREY)

def spaced(d, xy, text, fnt, fill, spacing=2, anchor="l"):
    """letter-spaced caps (our section titles)"""
    x, y = xy
    total = sum(d.textlength(c, font=fnt) + spacing for c in text) - spacing
    if anchor == "m":
        x -= total / 2
    for c in text:
        d.text((x, y), c, font=fnt, fill=fill, anchor="lm")
        x += d.textlength(c, font=fnt) + spacing

def card(d, x0, y0, x1, y1, title):
    d.rounded_rectangle([x0, y0, x1, y1], 6, fill=CARD)
    d.rectangle([x0, y0 + 6, x0 + 4, y1 - 6], fill=GREEN)                 # our green edge (as on the CO-OP cards)
    d.rectangle([x0 + 4, y0, x1, y0 + 46], fill=CARD_HEAD)
    spaced(d, (x0 + 22, y0 + 24), title, font(15, True), GREY, 3)
    d.line([x0 + 4, y0 + 46, x1, y0 + 46], fill=LINE)

def pick_row(d, x0, x1, y, text, right="", selected=False, arrow=False):
    if selected:
        d.rectangle([x0, y - 19, x1, y + 19], fill=TINT)
        d.rectangle([x0, y - 19, x0 + 3, y + 19], fill=GREEN_L)
        check(d, x0 + 14, y)
        col, rcol = WHITE, GREEN_L
    else:
        d.ellipse([x0 + 18, y - 3, x0 + 24, y + 3], fill=DIM)
        col, rcol = (215, 215, 210), GREEN_L
    d.text((x0 + 44, y), text, font=font(18, selected), fill=col, anchor="lm")
    if arrow:
        tx = x0 + 44 + d.textlength(text, font=font(18, selected)) + 10
        d.polygon([(tx, y - 5), (tx + 7, y), (tx, y + 5)], fill=GREY)
    if right:
        d.text((x1 - 12, y), right, font=font(16, True), fill=rcol, anchor="rm")

def form(path):
    w, h = 1240, 1126
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 10, w - 6, 1050], 10, fill=BG)

    # header: our icon + UWM CO-OP over the page title, a full-width line under it (as on the CO-OP page)
    icon = Image.open(os.path.join(HERE, "uwm_tabIcon_v1.png")).convert("RGBA").resize((52, 52), Image.LANCZOS)
    im.paste(icon, (64, 30), icon)
    spaced(d, (130, 44), "UWM CO-OP", font(15, True), GREEN_L, 3)
    d.text((130, 70), "New invoice", font=font(26, True), fill=WHITE, anchor="lm")
    d.text((1173, 44), "Issuer", font=font(14), fill=DIM, anchor="rm")
    d.text((1173, 68), "Farm A", font=font(20, True), fill=WHITE, anchor="rm")
    d.line([40, 102, w - 40, 102], fill=LINE)
    d.line([64, 102, 230, 102], fill=GREEN, width=3)

    cols = [(64, "CUSTOMER"), (440, "GOODS"), (816, "PICKUP")]
    for x, t in cols:
        card(d, x, 124, x + 357, 600, t)

    # customer
    for i, name in enumerate(["Farm A", "Farm B", "Farm C", "Farm D"]):
        pick_row(d, 70, 415, 196 + i * 42, name, selected=(i == 1))
    # goods
    goods = [("Slurry", "8 $ /1,000 l"), ("Manure", "12 $ /1,000 l"), ("Electricity", "180 $ /1,000 kWh"),
             ("Bulk", ""), ("Pallet", "Honey")]
    for i, (g, p) in enumerate(goods):
        pick_row(d, 446, 791, 196 + i * 42, g, p, selected=(i == 4), arrow=(i >= 3))
    # pickup
    d.rectangle([822, 176, 1167, 214], fill=TINT)
    d.rectangle([822, 176, 825, 214], fill=GREEN_L)
    check(d, 836, 195)
    d.text((866, 195), "Utilities Depot", font=font(18, True), fill=WHITE, anchor="lm")
    d.rounded_rectangle([1090, 184, 1158, 206], 11, outline=GREEN_L, width=1)
    d.text((1124, 195), "FIXED", font=font(12, True), fill=GREEN_L, anchor="mm")
    info = [("Owner", "Farm A"), ("Pickup point", "Pallet pad"), ("Your honey on pallets", "546,500 l"),
            ("At the depot for sale", "60,000 l"), ("Free to sell", "486,500 l")]
    for i, (k, v) in enumerate(info):
        y = 246 + i * 34
        d.text((844, y), k, font=font(16), fill=GREY, anchor="lm")
        d.text((1152, y), v, font=font(16, True), fill=GREEN_L if i == 4 else WHITE, anchor="rm")
        if i < 4:
            d.line([844, y + 17, 1152, y + 17], fill=(44, 46, 41))
    d.text((994, 448), "New pallets for the buyer appear on the pallet pad.", font=font(14), fill=DIM, anchor="mm")
    d.rounded_rectangle([880, 474, 1108, 510], 5, fill=(24, 25, 23), outline=GREEN, width=2)
    d.text((994, 492), "Pallet size:  1,000 l", font=font(17), fill=WHITE, anchor="mm")
    d.text((994, 528), "click to switch 1,000 l / 5,000 l", font=font(13), fill=DIM, anchor="mm")

    # the invoice line, in a card of its own
    d.rounded_rectangle([64, 624, 1173, 772], 6, fill=CARD)
    d.rectangle([64, 630, 68, 766], fill=GREEN)
    spaced(d, (86, 648), "INVOICE LINE", font(15, True), GREY, 3)
    d.text((1155, 648), "Customer:  Farm B", font=font(17, True), fill=GREEN_L, anchor="rm")
    d.line([68, 670, 1173, 670], fill=LINE)
    xs = [(150, "GOODS"), (300, "PICKUP"), (430, "QTY"), (520, "UNIT"), (640, "PRICE"), (770, "DISCOUNT"), (900, "REPEAT"), (1080, "AMOUNT")]
    for x, t in xs:
        d.text((x, 692), t, font=font(13, True), fill=DIM, anchor="mm")
    row = ["Honey", "Pallet pad", "10,000", "l", "33 $ /1,000 l", "10 %", "One-off", "297 $"]
    d.rectangle([68, 712, 1173, 752], fill=TINT)
    for (x, _), t in zip(xs, row):
        d.text((x, 732), t, font=font(17, t == "297 $"), fill=WHITE, anchor="mm")

    # inputs
    fields = [(64, 268, "PRICE / 1,000 L", "33", True), (286, 490, "AMOUNT", "Set amount", False),
              (508, 712, "AMOUNT IN LITERS", "10,000", True), (730, 934, "DISCOUNT %", "10", True), (952, 1173, "REPEAT", "One-off", False)]
    for x0, x1, lab, val, pen in fields:
        spaced(d, ((x0 + x1) / 2, 820), lab, font(12, True), DIM, 2, "m")
        d.rounded_rectangle([x0, 836, x1, 870], 5, fill=(24, 25, 23), outline=(80, 82, 76))
        d.text(((x0 + x1) / 2, 853), val, font=font(17), fill=WHITE, anchor="mm")
        if pen:
            pencil(d, x1 - 16, 853)
        else:
            d.polygon([(x1 - 22, 849), (x1 - 12, 849), (x1 - 17, 856)], fill=GREY)
    d.text((64, 884), "The game's price: 32 $ per 1,000 liters", font=font(14), fill=DIM, anchor="lm")

    # total
    d.rounded_rectangle([64, 904, 1173, 1034], 6, fill=(20, 21, 19))
    d.rectangle([64, 910, 68, 1028], fill=GREEN)
    spaced(d, (92, 969), "TOTAL DUE", font(20, True), GREY, 4)
    d.text((1144, 926), "Subtotal   330 $", font=font(16), fill=WHITE, anchor="rm")
    d.text((1144, 948), "Discount 10 %   -33 $", font=font(16), fill=GREEN_L, anchor="rm")
    d.line([960, 964, 1144, 964], fill=LINE)
    d.text((1144, 996), "297 $", font=font(34, True), fill=GREEN_L, anchor="rm")

    # button bar (unchanged)
    def key(x, k, label):
        kw = d.textlength(k, font=font(22, True)) + 36
        d.rounded_rectangle([x, 1064, x + kw, 1104], 6, fill=(30, 40, 30))
        d.text((x + kw / 2, 1084), k, font=font(22, True), fill=GREEN_L, anchor="mm")
        d.text((x + kw + 14, 1084), label, font=font(22, True), fill=WHITE, anchor="lm")
        return x + kw + 14 + d.textlength(label, font=font(22, True))
    x = key(600, "ENTER", "SEND INVOICE")
    d.line([x + 14, 1072, x + 14, 1096], fill=DIM)
    key(x + 30, "ESC", "CANCEL")
    im.save(path)

form(os.path.join(sys.argv[1], "invoice_form_style_v4.png"))
