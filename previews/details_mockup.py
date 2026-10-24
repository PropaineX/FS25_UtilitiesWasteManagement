"""Mock-up of the Details box (game info dialog style, as in the user's screenshot of the confirm box).
Text = the real output of UWMFrame.getDetailsText, with the game's number formatting.
Usage: python -I details_mockup.py <out.png>"""
import sys
from PIL import Image, ImageDraw, ImageFont

POWER = """Invoice #1: Electricity
Seller: Farm A
Buyer: Farm B

Ordered: 10,000 kWh
Price: $ 350 / 1,000 kWh
Repeats: One-off

Delivered: 4,123 kWh
Buyer paid: $ 1,443
Refunded to the buyer: $ 0
Seller received: $ 1,443
The seller had less electricity than ordered: only what was delivered is paid for.

Status: Done, 4,123 kWh
Sent on day 138
Finished on day 138"""

SLURRY = """Invoice #2: Slurry
Seller: Farm A
Buyer: Farm B

Ordered: 10,000 l
Price: $ 33 / 1,000 l
Repeats: One-off
Reserved for the buyer

Paid for: 10,000 l
Collected: 4,000 l
Not collected, refunded: 6,000 l
Buyer paid: $ 330
Refunded to the buyer: $ 198
Seller received: $ 132

Status: Ended, 4,000 l, reserved, $ 198 refunded
Sent on day 138
Finished on day 139"""

BG, BOX, BAR, GREEN, WHITE = (24, 24, 24), (40, 41, 40), (5, 5, 5), (132, 173, 10), (238, 238, 238)
font = ImageFont.truetype("seguisb.ttf", 22)
title = ImageFont.truetype("seguisb.ttf", 34)
key = ImageFont.truetype("seguisb.ttf", 24)


def dialog(text):
    lines = text.split("\n")
    w, line_h = 900, 31
    h = 150 + line_h * len(lines) + 40
    img = Image.new("RGB", (w, h + 66), BG)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h], radius=10, fill=BOX)
    cx = w // 2
    d.ellipse([cx - 52, 28, cx + 52, 132], outline=GREEN, width=4)
    d.text((cx, 80), "i", font=ImageFont.truetype("seguisb.ttf", 64), fill=GREEN, anchor="mm")
    y = 150
    for i, line in enumerate(lines):
        if i == 0:
            d.text((cx, y + 4), line.upper(), font=title, fill=WHITE, anchor="mm")
            y += line_h + 10
        else:
            d.text((cx, y), line, font=font, fill=WHITE, anchor="mm")
            y += line_h
    d.rectangle([0, h, w, h + 66], fill=BAR)
    d.rounded_rectangle([w - 190, h + 12, w - 132, h + 54], radius=4, fill=(20, 40, 5))
    d.text((w - 161, h + 33), "⏎", font=key, fill=GREEN, anchor="mm")
    d.text((w - 118, h + 33), "OK", font=ImageFont.truetype("seguisb.ttf", 26), fill=WHITE, anchor="lm")
    return img


a, b = dialog(POWER), dialog(SLURRY)
sheet = Image.new("RGB", (a.width + b.width + 90, max(a.height, b.height) + 90), (60, 60, 60))
sheet.paste(a, (30, 70))
sheet.paste(b, (a.width + 60, 70))
d = ImageDraw.Draw(sheet)
lab = ImageFont.truetype("arialbd.ttf", 30)
d.text((30, 20), "DETAILS: your 10,000 kWh electricity bill", font=lab, fill="white")
d.text((a.width + 60, 20), "DETAILS: a slurry order, part collected, then ended", font=lab, fill="white")
sheet.save(sys.argv[1])
print("saved", sys.argv[1], sheet.size)
