"""Mock-up v2 (2026-10-24): v1 with the depot status + manager line moved to a footer under the bottom line, so a
long status can't run into the tab arrows. Usage: python -I previews\\menu_mockup_v2.py <outDir> -> menu_v2_<view>.png"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import menu_mockup_v1 as v1  # noqa: E402

_header = v1.header


def header(d, balance):
    _header(d, balance)
    # v1 drew the depot line under the title: paint it out again
    d.rectangle([370, 152, 1100, 182], fill=v1.BG)


def footer(img):
    d = v1.ImageDraw.Draw(img)
    d.line([252, 1014, 1848, 1014], fill=v1.LINE, width=2)
    d.text((272, 1030), "Depot member: your share of the upkeep is $134 a day", font=v1.font(17), fill=v1.GREY)
    text = "You are the farm manager"
    w = d.textlength(text, font=v1.font(17))
    d.text((1828 - w, 1030), text, font=v1.font(17), fill=v1.GREY)


v1.header = header
_page = v1.page


def save_with_footer(original_save):
    def save(img, path):
        footer(img)
        original_save(img, str(path).replace("menu_v1_", "menu_v2_"))
    return save


if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    original = v1.Image.Image.save
    v1.Image.Image.save = save_with_footer(original)
    v1.view_incoming(out)
    v1.view_market(out)
    v1.view_myorders(out)
    v1.Image.Image.save = original
    print("done")
