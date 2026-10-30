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
    # issuer line + table (one item per invoice)
    d.text((77, 650), "Issuer: Farm A", font=font(20, True), fill=GREY, anchor="lm")
    d.text((1159, 650), "Customer: Farm B", font=font(20, True), fill=GREEN_L, anchor="rm")
    d.line([64, 666, 1173, 666], fill=(80, 80, 80))
    xs = [(150, "GOODS"), (300, "PICKUP"), (430, "QTY"), (520, "UNIT"), (640, "PRICE"), (770, "DISCOUNT"), (900, "REPEAT"), (1080, "AMOUNT")]
    for x, t in xs:
        d.text((x, 692), t, font=font(16, True), fill=WHITE, anchor="mm")
    d.line([64, 708, 1173, 708], fill=GREEN, width=2)
    row = ["Slurry", "Depot", "10,000", "l", "33 $ /1,000 l", "10 %", "One-off", "297 $"]
    d.rectangle([64, 718, 1173, 758], fill=(48, 56, 34))
    for (x, _), t in zip(xs, row):
        d.text((x, 738), t, font=font(17), fill=WHITE, anchor="mm")
    # inputs: price, amount, amount in liters (swapped, user 2026-10-28), discount %, repeat
    fields = [(66, 270, "Price per 1,000 liters", "33", True), (288, 492, "Amount", "Set amount", False),
              (510, 714, "Amount in liters", "10000", True), (732, 936, "Discount %", "10", True), (954, 1170, "Repeat", "One-off", False)]
    for x0, x1, lab, val, pen in fields:
        d.text(((x0 + x1) / 2, 1112), lab, font=font(16), fill=GREY, anchor="mm")
        new_ = lab == "Discount %"
        d.rounded_rectangle([x0, 1128, x1, 1158], 4, fill=(26, 26, 26), outline=GREEN if new_ else (110, 110, 110), width=2 if new_ else 1)
        d.text(((x0 + x1) / 2, 1143), val, font=font(17), fill=WHITE, anchor="mm")
        if pen:
            pencil(d, x1 - 16, 1143)
    d.text((66, 1166), "The game's price: 32 $ per 1,000 liters", font=font(15), fill=GREY, anchor="lm")
    # total
    d.rounded_rectangle([64, 1184, 1173, 1314], 8, fill=(22, 22, 22))
    d.text((93, 1249), "Total due:", font=font(28, True), fill=GREY, anchor="lm")
    d.text((1144, 1208), "Subtotal: 330 $", font=font(16), fill=WHITE, anchor="rm")
    d.text((1144, 1228), "Discount 10 %: -33 $", font=font(16), fill=GREEN_L, anchor="rm")
    d.line([986, 1244, 1144, 1244], fill=(90, 90, 90))
    d.text((1144, 1274), "297 $", font=font(32, True), fill=GREEN_L, anchor="rm")
    hints(d, w, 1344, [("⏎", "SEND INVOICE", True), ("ESC", "CANCEL", True)])
    im.save(path)

def details(path):
    w, h = 1300, 560
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    for i, (who, lines) in enumerate([
        ("SELLER (Farm A) - Details", ["Slurry to Farm B, one-off", "Ordered: 10,000 l", "Price: 33 $ per 1,000 l",
                                       "Discount: 10 % (-33 $)", "Buyer pays: 297 $", "", "Notice: Farm B accepted - you get 297 $ (10 % off, -33 $)"]),
        ("BUYER (Farm B) - Details", ["Slurry from Farm A, one-off", "Ordered: 10,000 l", "Price: 33 $ per 1,000 l",
                                      "Discount: 10 % (you save 33 $)", "You pay: 297 $", "", "Incoming list:  Slurry  10,000 l  33 $/1,000 l  -10 %  297 $"])]):
        x0 = 20 + i * 640
        d.rounded_rectangle([x0, 20, x0 + 620, 540], 10, fill=BG)
        d.text((x0 + 310, 60), who, font=font(22, True), fill=WHITE, anchor="mm")
        d.line([x0 + 200, 82, x0 + 420, 82], fill=GREEN, width=2)
        for j, t in enumerate(lines):
            col = GREEN_L if "Discount" in t or "save" in t or "-10 %" in t else (GREY if t.startswith(("Notice", "Incoming")) else WHITE)
            d.text((x0 + 40, 130 + j * 50), t, font=font(19, "Discount" in t), fill=col, anchor="lm")
    im.save(path)

out = sys.argv[1]
choice(os.path.join(out, "invoice_wizard_v1_choice.png")) if False else None
form(os.path.join(out, "invoice_wizard_v3_form_discount.png"))
details(os.path.join(out, "invoice_details_discount_v1.png"))
