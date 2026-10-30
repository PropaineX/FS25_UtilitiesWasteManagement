"""Mock-up of the new invoice screens (choice dialog + NEW INVOICE form) with our goods.
python -I invoice_wizard_mockup_v1.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

def check(d, x, y):
    d.line([x, y, x + 6, y + 7, x + 18, y - 8], fill=(20, 20, 20), width=3)

def pencil(d, x, y):
    d.line([x - 6, y + 6, x + 5, y - 5], fill=GREY, width=4)
    d.polygon([(x - 8, y + 8), (x - 7, y + 3), (x - 3, y + 7)], fill=GREY)

def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)

BG = (38, 38, 38); PANEL = (30, 30, 30); ROW = (33, 33, 33); BAR = (8, 8, 8)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); WHITE = (235, 235, 235); GREY = (170, 170, 170); DIM = (110, 110, 110)

def keyhint(d, x, y, key, label, active=True):
    kw = d.textlength(key, font=font(22, True)) + 36
    d.rounded_rectangle([x, y, x + kw, y + 40], 6, fill=(30, 40, 30))
    d.text((x + kw / 2, y + 20), key, font=sym(22) if len(key) == 1 and ord(key) > 255 else font(22, True), fill=GREEN_L if active else DIM, anchor="mm")
    d.text((x + kw + 14, y + 20), label, font=font(22, True), fill=WHITE if active else GREY, anchor="lm")
    return x + kw + 14 + d.textlength(label, font=font(22, True)) + 24

def hints(d, w, y, items):
    tot = 0
    for k, l, a in items:
        tot += d.textlength(k, font=font(22, True)) + 36 + 14 + d.textlength(l, font=font(22, True)) + 24
    x = w - tot - 10
    for i, (k, l, a) in enumerate(items):
        x = keyhint(d, x, y, k, l, a)
        if i < len(items) - 1:
            d.line([x - 12, y + 8, x - 12, y + 32], fill=DIM, width=1)

def choice(path):
    w, h = 1030, 608
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([14, 28, w - 14, 532], 10, fill=BG)
    d.ellipse([466, 82, 572, 188], outline=GREEN, width=4)
    d.text((519, 133), "?", font=font(60), fill=GREEN_L, anchor="mm")
    d.text((519, 222), "What do you want to do?", font=font(24, True), fill=WHITE, anchor="mm")
    d.line([382, 246, 656, 246], fill=GREEN, width=2)
    for y, t, s in [(278, "INVOICE A FARM", "You sell slurry, manure or electricity. The selected farm pays when it accepts."),
                    (380, "REQUEST AN INVOICE", "You ask to buy. The selected farm must approve it. You pay after approval.")]:
        d.rectangle([52, y, 986, y + 80], fill=ROW); d.rectangle([52, y, 57, y + 80], fill=GREEN)
        d.text((108, y + 26), t, font=font(22, True), fill=WHITE, anchor="lm")
        d.text((108, y + 54), s, font=font(19), fill=GREY, anchor="lm")
    hints(d, w, 550, [("\u23ce", "INVOICE", True), ("SPACE", "REQUEST INVOICE", True), ("ESC", "CANCEL", True)])
    im.save(path)

def form(path):
    w, h = 1240, 1406
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([6, 10, w - 6, 1330], 10, fill=BG)
    d.text((618, 42), "NEW INVOICE", font=font(26, True), fill=WHITE, anchor="mm")
    d.line([528, 68, 708, 68], fill=GREEN, width=2)
    cols = [(64, "01", "Customer"), (440, "02", "Goods"), (816, "03", "Pickup")]
    for x, n, t in cols:
        d.rounded_rectangle([x, 92, x + 357, 602], 8, fill=PANEL)
        d.rounded_rectangle([x + 16, 112, x + 56, 138], 13, fill=GREEN_L)
        d.text((x + 36, 125), n, font=font(16, True), fill=(30, 30, 30), anchor="mm")
        d.text((x + 69, 125), t, font=font(22, True), fill=WHITE, anchor="lm")
    # customers (placeholder names)
    for i, name in enumerate(["Farm A", "Farm B", "Farm C", "Farm D"]):
        y = 188 + i * 43
        if i == 1:
            d.rectangle([77, y - 21, 408, y + 21], fill=GREEN)
            check(d, 90, y)
            d.text((125, y), name, font=font(19), fill=(40, 50, 20), anchor="lm")
        else:
            d.text((98, y), "\u00b7", font=font(19), fill=GREY, anchor="mm")
            d.text((125, y), name, font=font(19), fill=WHITE, anchor="lm")
    # goods: only ours
    goods = [("Slurry", "8 $ /1,000 l"), ("Manure", "12 $ /1,000 l"), ("Electricity", "180 $ /1,000 kWh")]
    for i, (g, p) in enumerate(goods):
        y = 172 + i * 43
        if i == 0:
            d.rectangle([453, y - 21, 784, y + 21], fill=GREEN)
            check(d, 466, y)
            d.text((501, y), g, font=font(19), fill=(40, 50, 20), anchor="lm")
            d.text((768, y), p, font=font(18, True), fill=(40, 50, 20), anchor="rm")
        else:
            d.text((474, y), "\u00b7", font=font(19), fill=GREY, anchor="mm")
            d.text((501, y), g, font=font(19), fill=WHITE, anchor="lm")
            d.text((768, y), p, font=font(18, True), fill=GREEN_L, anchor="rm")
    # storages with stock
    # the one depot on the map, always the pickup
    y = 172
    d.rectangle([829, y - 21, 1160, y + 21], fill=GREEN)
    check(d, 842, y)
    d.text((872, y), "Utilities Depot", font=font(18, True), fill=(40, 50, 20), anchor="lm")
    d.text((1148, y), "Fixed", font=font(17, True), fill=(40, 50, 20), anchor="rm")
    info = [("Owner", "Farm A"), ("Pickup point", "Slurry lane (tank)"), ("Your slurry stock", "546,500 l"),
            ("Already reserved", "60,000 l"), ("Free to sell", "486,500 l")]
    for i, (k, v) in enumerate(info):
        y = 232 + i * 36
        d.text((850, y), k, font=font(17), fill=GREY, anchor="lm")
        d.text((1148, y), v, font=font(17, True), fill=GREEN_L if i == 4 else WHITE, anchor="rm")
    d.line([846, 214, 1144, 214], fill=(60, 60, 60))
    d.multiline_text((994, 530), "The buyer collects at the depot.\nThe liters come from your farm's stock.\nElectricity: delivered directly, no pickup.",
                     font=font(15), fill=DIM, anchor="mm", align="center", spacing=6)
    # issuer line + table
    d.text((77, 650), "Issuer: Farm A", font=font(20, True), fill=GREY, anchor="lm")
    d.text((1159, 650), "Customer: Farm B", font=font(20, True), fill=GREEN_L, anchor="rm")
    d.line([64, 666, 1173, 666], fill=(80, 80, 80))
    heads = [(90, "DESCRIPTION", "l"), (400, "PICKUP", "l"), (640, "QTY", "m"), (735, "UNIT", "m"),
             (840, "PRICE", "m"), (950, "REPEAT", "m"), (1146, "AMOUNT", "r")]
    for x, t, a in heads:
        d.text((x, 692), t, font=font(16, True), fill=WHITE, anchor=a + "m")
    d.line([64, 708, 1173, 708], fill=GREEN, width=2)
    rows = [("Slurry", "Depot - slurry lane", "50,000", "l", "8 $ /1,000 l", "Weekly x4", "1,600 $"),
            ("Electricity", "Direct", "200,000", "kWh", "180 $ /1,000 kWh", "Once", "36,000 $")]
    for i, r in enumerate(rows):
        y = 738 + i * 44
        if i == 0:
            d.rectangle([64, y - 20, 1173, y + 20], fill=(48, 56, 34))
        xs = [(90, "l"), (400, "l"), (640, "m"), (735, "m"), (840, "m"), (950, "m"), (1146, "r")]
        for (x, a), t in zip(xs, r):
            d.text((x, y), t, font=font(17), fill=WHITE, anchor=a + "m")
    # inputs
    fields = [(66, 474, "Notes:", "Add a note or reference"), (502, 696, "Price", "8"), (718, 912, "Qty", "50,000"),
              (934, 1042, "Repeat", "Weekly"), (1062, 1170, "Times", "4")]
    for x0, x1, lab, val in fields:
        d.text(((x0 + x1) / 2, 1112), lab, font=font(16), fill=GREY, anchor="mm")
        d.rounded_rectangle([x0, 1128, x1, 1158], 4, fill=(26, 26, 26), outline=GREY if lab == "Notes:" else (70, 70, 70))
        d.text(((x0 + x1) / 2, 1143), val, font=font(16), fill=GREY if lab == "Notes:" else WHITE, anchor="mm")
        pencil(d, x1 - 16, 1143)
    # total
    d.rounded_rectangle([64, 1170, 1173, 1302], 8, fill=(22, 22, 22))
    d.text((93, 1236), "Total Due:", font=font(28, True), fill=GREY, anchor="lm")
    d.text((1144, 1201), "Per delivery: 400 $ + 36,000 $", font=font(16), fill=WHITE, anchor="rm")
    d.text((1144, 1220), "Deliveries: 4 + 1", font=font(16), fill=WHITE, anchor="rm")
    d.line([986, 1236, 1144, 1236], fill=(90, 90, 90))
    d.text((1144, 1260), "37,600 $", font=font(32, True), fill=GREEN_L, anchor="rm")
    hints(d, w, 1344, [("\u23ce", "SEND INVOICE", True), ("\u21a4", "REMOVE", True), ("X", "EDIT LINE", True), ("ESC", "CANCEL", True)])
    im.save(path)

out = sys.argv[1]
choice(os.path.join(out, "invoice_wizard_v1_choice.png")) if False else None
form(os.path.join(out, "invoice_wizard_v2_form.png"))
