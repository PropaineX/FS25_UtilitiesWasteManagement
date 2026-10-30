"""What the player sees: ESC page -> New -> UWM CO-OP -> form (v4 look). python -I flow_mockup_v1.py <outDir>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
out = sys.argv[1]
F = "C:/Windows/Fonts/"
bold = lambda s: ImageFont.truetype(F + "segoeuib.ttf", s)

page = Image.open("menu_v2_incoming.png").convert("RGB")
d = ImageDraw.Draw(page)
# the button is just "New" now (opens the CO-OP page on every tab)
x0 = 1584
d.rectangle([x0 - 2, 1090, 1722, 1125], fill=(8, 8, 8))
d.text((x0, 1108), "NEW", font=bold(20), fill=(235, 235, 235), anchor="lm")
# highlight ring on the Space key, as if just pressed
d.rounded_rectangle([1490, 1089, 1574, 1124], 6, outline=(166, 200, 60), width=3)
page.save(os.path.join(out, "flow_v1_1_page.png"))

def over(base, dialog, name, maxh=1040):
    bg = ImageEnhance.Brightness(base).enhance(0.35)
    if dialog.height > maxh:
        dialog = dialog.resize((int(dialog.width * maxh / dialog.height), maxh), Image.LANCZOS)
    bg.paste(dialog, ((bg.width - dialog.width) // 2, (bg.height - dialog.height) // 2))
    bg.save(os.path.join(out, name))
    return bg

clean = Image.open("menu_v2_incoming.png").convert("RGB")
s2 = over(clean, Image.open("invoice_wizard_v3_choice.png").convert("RGB"), "flow_v1_2_coop.png")
s3 = over(clean, Image.open("invoice_form_style_v4.png").convert("RGB"), "flow_v1_3_form.png", 1100)

# one strip with arrows
thumbs = [im.resize((800, 450), Image.LANCZOS) for im in (Image.open(os.path.join(out, "flow_v1_1_page.png")), s2, s3)]
strip = Image.new("RGB", (800 * 3 + 2 * 120 + 80, 560), (14, 14, 14))
sd = ImageDraw.Draw(strip)
labels = ["1. ESC > Utilities page, press SPACE (New)", "2. UWM CO-OP: pick Invoice a farm", "3. The new invoice form"]
for i, t in enumerate(thumbs):
    x = 40 + i * 920
    strip.paste(t, (x, 70))
    sd.text((x + 400, 40), labels[i], font=bold(24), fill=(235, 235, 235), anchor="mm")
    if i < 2:
        ax = x + 830
        sd.polygon([(ax, 280), (ax + 60, 295), (ax, 310)], fill=(166, 200, 60))
        sd.line([ax - 30, 295, ax + 10, 295], fill=(166, 200, 60), width=8)
strip.save(os.path.join(out, "flow_v1_strip.png"))
