import sys, re, pathlib, xml.etree.ElementTree as ET
sys.path.insert(0, sys.argv[1])
from lupa import lua51
mod = pathlib.Path(sys.argv[2])
lua = lua51.LuaRuntime()
ok = True
for f in sorted(mod.rglob("*.lua")):
    src = f.read_text(encoding="utf-8")
    res = lua.execute("return function(s) local f, e = loadstring(s) return e end")(src)
    print(("OK  " if res is None else "ERR ") + str(f.relative_to(mod)) + ("" if res is None else "  " + res))
    ok &= res is None
for f in sorted(mod.rglob("*.xml")):
    try: ET.parse(f); print("OK  " + str(f.relative_to(mod)))
    except Exception as e: print("ERR " + str(f.relative_to(mod)) + " " + str(e)); ok = False
defined = {t.get("name") for t in ET.parse(mod/"modDesc.xml").iter("text")}
used = set()
for f in mod.rglob("*.lua"):
    used |= set(re.findall(r'"(uwm_[A-Za-z]+_?[A-Za-z]*)"', f.read_text(encoding="utf-8")))
for f in mod.rglob("*.xml"):
    used |= set(re.findall(r'\$l10n_(uwm_\w+)', f.read_text(encoding="utf-8")))
used -= {"uwm_good_electricity"} if False else set()
missing = sorted(k for k in used if k not in defined)
unused = sorted(k for k in defined if k not in used and k.startswith("uwm_"))
print("missing keys:", missing); print("unused keys:", unused)
sys.exit(0 if ok and not missing else 1)
