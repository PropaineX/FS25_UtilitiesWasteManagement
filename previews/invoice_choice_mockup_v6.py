"""Mock-up v6 of the UWM CO-OP page: new option look (icon tile, two-line text, arrow) and updated descriptions
(bulk goods, pallets, the depot). Same header and question as v5. python -I invoice_choice_mockup_v6.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

F = "C:/Windows/Fonts/"
HERE = os.path.dirname(os.path.abspath(__file__))
def font(sz, bold=False):
    return ImageFont.truetype(F + ("segoeuib.ttf" if bold else "segoeui.ttf"), sz)
def sym(sz):
    return ImageFont.truetype(F + "seguisym.ttf", sz)

BG = (36, 37, 35); CARD = (28, 29, 27); BAR = (8, 8, 8); TILE = (40, 44, 34)
GREEN = (134, 177, 17); GREEN_L = (166, 200, 60); TINT = (50, 60, 28)
WHITE = (235, 235, 235); GREY = (170, 170, 165); DIM = (110, 112, 105); LINE = (62, 64, 58)

def spaced(d, xy, text, fnt, fill, spacing=3):
    x, y = xy
    total = sum(d.textlength(c, font=fnt) + spacing for c in text) - spacing
    x -= total / 2
    for c in text:
        d.text((x, y), c, font=fnt, fill=fill, anchor="lm")
        x += d.textlength(c, font=fnt) + spacing

# small line icons, drawn in the tile (cx, cy = tile centre)
def icon_invoice(d, cx, cy, c):          # a bill with a dollar
    d.rounded_rectangle([cx - 13, cy - 17, cx + 13, cy + 17], 3, outline=c, width=3)
    d.line([cx - 7, cy - 8, cx + 7, cy - 8], fill=c, width=2)
    d.line([cx - 7, cy - 2, cx + 3, cy - 2], fill=c, width=2)
    d.text((cx + 1, cy + 8), "$", font=font(15, True), fill=c, anchor="mm")

def icon_request(d, cx, cy, c):          # an arrow coming in to a tray
    d.line([cx, cy - 17, cx, cy + 4], fill=c, width=3)
    d.polygon([(cx - 8, cy - 2), (cx + 8, cy - 2), (cx, cy + 8)], fill=c)
    d.line([cx - 15, cy + 6, cx - 15, cy + 15, cx + 15, cy + 15, cx + 15, cy + 6], fill=c, width=3)

def icon_buy(d, cx, cy, c):              # a cart
    d.line([cx - 17, cy - 13, cx - 11, cy - 13, cx - 6, cy + 6, cx + 13, cy + 6, cx + 17, cy - 7, cx - 9, cy - 7], fill=c, width=3)
    d.ellipse([cx - 7, cy + 10, cx - 1, cy + 16], fill=c)
    d.ellipse([cx + 7, cy + 10, cx + 13, cy + 16], fill=c)

def icon_sell(d, cx, cy, c):             # a price tag
    d.polygon([(cx - 16, cy - 4), (cx - 4, cy - 16), (cx + 16, cy - 16), (cx + 16, cy + 4), (cx + 4, cy + 16)], outline=c, width=3)
    d.ellipse([cx + 5, cy - 10, cx + 11, cy - 4], outline=c, width=2)

OPTIONS = [
    (icon_invoice, "Invoice a farm",
     "Bill a farm for what you sell: slurry, manure, electricity, bulk goods or pallets.",
     "Your goods go to the depot and wait there until the farm pays and picks them up."),
    (icon_request, "Request an invoice",
     "Ask a farm to sell you something. They approve it, you pay,",
     "and you collect it at the depot (electricity goes straight to your productions)."),
    (icon_buy, "Create a standing buy order",
     "Post what you want and your price on the market. Your money is held for it,",
     "and any co-op farm can fill part or all of the order."),
    (icon_sell, "Create a standing sell order",
     "Put goods up for sale at your price. They move to the depot,",
     "and any co-op farm can buy part or all of them."),
]

def choice(path):
    w = 1030; top = 220; step = 112; ch = 96
    panel_b = top + step * len(OPTIONS) + 30
    h = panel_b + 76
    im = Image.new("RGB", (w, h), BAR); d = ImageDraw.Draw(im)
    d.rounded_rectangle([14, 28, w - 14, panel_b], 10, fill=BG)

    # header (as v5): UWM CO-OP, full-width line, the question
    d.text((519, 76), "UWM CO-OP", font=font(34, True), fill=WHITE, anchor="mm")
    d.line([429, 104, 609, 104], fill=GREEN, width=3)
    d.line([40, 126, w - 40, 126], fill=LINE)
    d.text((519, 168), "What's on the books today?", font=font(24, True), fill=WHITE, anchor="mm")
    d.line([382, 192, 656, 192], fill=GREEN, width=2)

    for i, (icon, title, line1, line2) in enumerate(OPTIONS):
        y = top + i * step
        sel = i == 0
        x0, x1 = 52, 986
        d.rounded_rectangle([x0, y, x1, y + ch], 8, fill=TINT if sel else CARD,
                            outline=GREEN_L if sel else (46, 48, 43), width=2 if sel else 1)
        # icon tile
        tx0, ty0 = x0 + 18, y + 18
        d.rounded_rectangle([tx0, ty0, tx0 + 60, ty0 + 60], 8, fill=GREEN if sel else TILE)
        icon(d, tx0 + 30, ty0 + 30, (28, 34, 12) if sel else GREEN_L)
        # text
        d.text((x0 + 98, y + 26), title.upper(), font=font(20, True), fill=WHITE, anchor="lm")
        d.text((x0 + 98, y + 53), line1, font=font(16), fill=(205, 205, 200) if sel else GREY, anchor="lm")
        d.text((x0 + 98, y + 75), line2, font=font(16), fill=(205, 205, 200) if sel else GREY, anchor="lm")
        # arrow
        ax = x1 - 30
        d.line([ax - 6, y + ch / 2 - 10, ax + 4, y + ch / 2, ax - 6, y + ch / 2 + 10], fill=GREEN_L if sel else DIM, width=3)

    # key bar
    def key(x, k, label, ksym=False):
        f = sym(22) if ksym else font(22, True)
        kw = d.textlength(k, font=f) + 36
        d.rounded_rectangle([x, panel_b + 18, x + kw, panel_b + 58], 6, fill=(30, 40, 30))
        d.text((x + kw / 2, panel_b + 38), k, font=f, fill=GREEN_L, anchor="mm")
        d.text((x + kw + 14, panel_b + 38), label, font=font(22, True), fill=WHITE, anchor="lm")
        return x + kw + 14 + d.textlength(label, font=font(22, True))
    x = key(488, "\u2195", "CHOOSE", True)
    d.line([x + 12, panel_b + 26, x + 12, panel_b + 50], fill=DIM)
    x = key(x + 26, "\u23ce", "SELECT", True)
    d.line([x + 12, panel_b + 26, x + 12, panel_b + 50], fill=DIM)
    key(x + 26, "ESC", "CANCEL")
    im.save(path)

choice(os.path.join(sys.argv[1], "invoice_wizard_v6_choice.png"))
