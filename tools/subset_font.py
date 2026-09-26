"""字型子集化：把 11.9 MB 的思源黑體，縮成只含遊戲會顯示的字。

用法（在 antarctic/ 資料夾底下執行）：
    python tools/subset_font.py            產生 fonts/NotoSansTC-Game.ttf
    python tools/subset_font.py --check     只檢查：遊戲用到的字是否都在子集字型裡

為什麼：網頁版要下載整包資料，完整中文字型就佔 11.9 MB，手機上很久才開得起來。

怎麼決定要哪些字：掃 story/campaign.json、scripts/、scenes/ 裡**引號內的字串**，
再加上 ASCII 可見字元與常用全形標點。

只掃引號是刻意的：註解裡的字不會顯示在畫面上，收進來只會讓「改一行註解就得
重跑字型」，而 dev/font_test.tscn 也會跟著誤報。

改了台詞或程式裡的字串之後，重跑這支腳本；沒重跑的話，
新字在遊戲裡會變成方框（--check 會抓出來）。
"""
import glob
import io
import os
import re
import sys

SRC = "fonts/NotoSansTC-VF.ttf"
OUT = "fonts/NotoSansTC-Game.ttf"
## 南極這邊多掃兩種：關卡檔（站名會顯示在 HUD）與劇本（劇情文字的來源）
SCAN = ["story/*.json", "scripts/*.gd", "scripts/**/*.gd", "scenes/*.tscn",
        "data/levels/*.json", "data/*.json"]
## 劇本整份都是要顯示的文字，不像程式只取引號內
SCAN_ALL = ["story/SCRIPT.md"]
## 引號內的字串。GDScript 兩種引號都能用，JSON 與 tscn 都是雙引號
STRING = re.compile('"[^"]*"' + "|'[^']*'")


def used_chars():
    chars = set(chr(c) for c in range(0x20, 0x7F))
    for pattern in SCAN:
        for path in glob.glob(pattern, recursive=True):
            text = io.open(path, encoding="utf-8", errors="ignore").read()
            for m in STRING.finditer(text):
                chars |= set(m.group(0))
    # 劇本整份都要（那是劇情文字的來源，不是只有引號內）
    for pattern in SCAN_ALL:
        for path in glob.glob(pattern, recursive=True):
            chars |= set(io.open(path, encoding="utf-8", errors="ignore").read())
    chars |= set("　、。，．：；！？「」『』（）〈〉《》…—‧～％＋－＝／＼＊＃＠")
    return {c for c in chars if c.isprintable()}


def main():
    from fontTools import subset
    from fontTools.ttLib import TTFont

    chars = used_chars()
    if "--check" in sys.argv:
        if not os.path.exists(OUT):
            print("還沒產生 %s，請先跑 python tools/subset_font.py" % OUT)
            return 1
        cmap = set()
        for table in TTFont(OUT)["cmap"].tables:
            cmap |= set(table.cmap.keys())
        # 空白類（像全形空格）子集工具會丟掉字形，但它本來就不會畫出東西，不算缺字
        missing = sorted(c for c in chars if ord(c) not in cmap and c.strip())
        if missing:
            print("子集字型缺 %d 個字：%s" % (len(missing), "".join(missing[:40])))
            print("請重跑 python tools/subset_font.py")
            return 1
        print("子集字型 OK，%d 個字都在" % len(chars))
        return 0

    font = TTFont(SRC)
    subsetter = subset.Subsetter(options=subset.Options(
        layout_features=["*"], name_IDs=["*"], notdef_outline=True, recalc_bounds=True))
    subsetter.populate(text="".join(sorted(chars)))
    subsetter.subset(font)
    font.save(OUT)
    before = os.path.getsize(SRC) / 1048576.0
    after = os.path.getsize(OUT) / 1048576.0
    print("%s  %.1f MB  →  %s  %.2f MB（%d 個字）" % (SRC, before, OUT, after, len(chars)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
