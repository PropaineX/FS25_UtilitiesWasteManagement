"""Mock-up v2 of the "What do you want to do?" dialog: 4 choices incl. standing orders.
python -I invoice_choice_mockup_v2.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

BG = (38, 38, 38); ROW = (33, 33, 33); BAR = (8, 8, 8)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); WHITE = (235, 235, 235); GREY = (170, 170, 170); DIM = (110, 110, 110)

def hints(d, w, y, items):
    def kf(k): return sym(22) if len(k) == 1 and ord(k) > 255 else font(22, True)
    widths = [d.textlength(k, font=kf(k)) + 36 + 14 + d.textlength(l, font=font(22, True)) + 24 for k, l in items]
    x = w - sum(widths) - 10
    for i, (k, l) in enumerate(items):
        kw = d.textlength(k, font=kf(k)) + 36
        d.rounded_rectangle([x, y, x + kw, y + 40], 6, fill=(30, 40, 30))
        d.text((x + kw / 2, y + 20), k, font=kf(k), fill=GREEN_L, anchor="mm")
        d.text((x + kw + 14, y + 20), l, font=font(22, True), fill=WHITE, anchor="lm")
        x += widths[i]
        if i < len(items) - 1:
            d.line([x - 12, y + 8, x - 12, y + 32], fill=DIM, width=1)

def choice(path):
    opts = [("INVOICE A FARM", "You sell slurry, manure or electricity. The selected farm pays when it accepts."),
            ("REQUEST AN INVOICE", "You ask to buy. The selected farm must approve it. You pay after approval."),
            ("CREATE A STANDING BUY ORDER", "Post on the market what you want to buy and your price. Any farm can sell to you."),
            ("CREATE A STANDING SELL ORDER", "Post on the market what you have for sale and your price. Any farm can buy from you.")]
    w = 1030; top = 278; step = 102
    panel_b = top + step * len(opts) + 50
    h = panel_b + 76
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([14, 28, w - 14, panel_b], 10, fill=BG)
    d.ellipse([466, 82, 572, 188], outline=GREEN, width=4)
    d.text((519, 133), "?", font=font(60), fill=GREEN_L, anchor="mm")
    d.text((519, 222), "What do you want to do?", font=font(24, True), fill=WHITE, anchor="mm")
    d.line([382, 246, 656, 246], fill=GREEN, width=2)
    for i, (t, s) in enumerate(opts):
        y = top + i * step
        sel = i == 0
        d.rectangle([52, y, 986, y + 80], fill=(48, 56, 34) if sel else ROW)
        d.rectangle([52, y, 57, y + 80], fill=GREEN)
        d.text((108, y + 26), t, font=font(22, True), fill=WHITE, anchor="lm")
        d.text((108, y + 54), s, font=font(19), fill=GREY, anchor="lm")
    hints(d, w, panel_b + 18, [("\u2195", "CHOOSE"), ("\u23ce", "SELECT"), ("ESC", "CANCEL")])
    im.save(path)

choice(os.path.join(sys.argv[1], "invoice_wizard_v2_choice.png"))
