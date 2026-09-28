# -*- coding: utf-8 -*-
"""從 story/SCRIPT.md 產生 story/campaign.json。

從專案根目錄執行： python tools/build_campaign.py

劇本是給人寫的，json 是給遊戲讀的。改劇情只改 SCRIPT.md，再跑這支。
格式規則寫在 SCRIPT.md 的檔頭。
"""
import json, re, sys

SRC = "story/SCRIPT.md"
DST = "story/campaign.json"

CH_RE = re.compile(r"^第([一二三四五六七八九十]+)章\s+(.+)$")
END_RE = re.compile(r"^結局\s+(.+)$")
IMG_RE = re.compile(r"^【圖示\s*([^：]+)：(.+)】$")
LEVEL_RE = re.compile(r"^▶\s*(.+)$")
BRIEF_RE = re.compile(r"^任務卡〔(.+)〕$")
LINE_RE = re.compile(r"^([^〔：（]+?)(?:〔(.+?)〕)?：(.+)$")
NUM = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}

lines = open(SRC, encoding="utf-8").read().split("\n")

out = {
    "_說明": "由 tools/build_campaign.py 從 story/SCRIPT.md 產生。不要直接改這個檔案。",
    "_欄位": {"who": "誰說的，空字串＝旁白", "act": "動作提示", "scene": "切到哪張插圖", "text": "台詞"},
    "illustrations": {},
    "chapters": [],
}

chapter = None       # 目前的章
target = None        # 台詞要塞進哪個清單
section = None       # intro / lose / outro / ending
pending_scene = None # 下一句台詞要帶的插圖
last_img = None
in_brief = False
skipping = False
errors = []

for no, raw in enumerate(lines, 1):
    line = raw.strip()
    if not line or line.startswith("#") or line.startswith(">"):
        continue

    m = CH_RE.match(line)
    if m:
        n = NUM.get(m.group(1), 0)
        chapter = {"id": "ch%02d" % n, "title": "第%s章　%s" % (m.group(1), m.group(2)),
                   "intro": [], "level": {"stage": "stage-%02d" % n}, "lose": [], "outro": []}
        out["chapters"].append(chapter)
        target = None; skipping = False; in_brief = False
        continue

    m = END_RE.match(line)
    if m:
        out["ending_title"] = m.group(1)
        out["ending"] = []
        target = out["ending"]; section = "ending"; skipping = False; in_brief = False
        continue

    if line.startswith("本章圖示整理"):
        skipping = True
        continue
    if skipping:
        continue

    if line == "開場":
        target, section, in_brief = chapter["intro"], "intro", False
        continue
    if line == "失敗畫面":
        target, section, in_brief = chapter["lose"], "lose", False
        continue
    if line == "過關畫面":
        target, section, in_brief = chapter["outro"], "outro", False
        continue

    m = LEVEL_RE.match(line)
    if m:
        chapter["level"]["name"] = m.group(1)
        target = None
        continue
    m = BRIEF_RE.match(line)
    if m:
        chapter["level"]["brief"] = {"title": m.group(1), "lines": []}
        in_brief = True
        continue
    if in_brief:
        chapter["level"]["brief"]["lines"].append(line)
        continue

    m = IMG_RE.match(line)
    if m:
        key, title = m.group(1).strip(), m.group(2).strip()
        cid = chapter["id"] if chapter and section != "ending" else "ending"
        if section == "ending":
            cid = "ending"
        img_id = "%s_%s" % (cid, "lose" if key == "失敗" else "%02d" % int(key))
        out["illustrations"][img_id] = {"image": "res://art/story/%s.png" % img_id,
                                        "title": title, "note": ""}
        pending_scene = img_id
        last_img = img_id
        if key == "失敗" and chapter:
            chapter["lose_title"] = title
        elif section == "outro" and chapter and "outro_title" not in chapter:
            chapter["outro_title"] = title
        continue

    if line.startswith("連結："):
        # 這張圖在網頁版要變成可以點的連結（QR code 那兩頁）。
        # 手機看自己的螢幕沒辦法掃 QR code，一定要能點
        if last_img:
            out["illustrations"][last_img]["link"] = line[3:].strip()
        continue

    if line.startswith("畫面："):
        if last_img:
            out["illustrations"][last_img]["note"] = line[3:]
        continue

    if target is None:
        errors.append("第 %d 行不知道要放哪：%s" % (no, line))
        continue

    entry = None
    if line.startswith("（") and line.endswith("）"):
        entry = {"who": "", "act": "音效／動作", "text": line[1:-1].strip()}
    else:
        m = LINE_RE.match(line)
        if m:
            who = m.group(1).strip()
            entry = {"who": "" if who == "旁白" else who,
                     "act": m.group(2) or "", "text": m.group(3).strip()}
    if entry is None:
        errors.append("第 %d 行看不懂：%s" % (no, line))
        continue
    if pending_scene:
        entry["scene"] = pending_scene
        pending_scene = None
    target.append(entry)

json.dump(out, open(DST, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=2)

total = sum(len(c["intro"]) + len(c["lose"]) + len(c["outro"]) for c in out["chapters"])
total += len(out.get("ending", []))
print("%s：%d 章、%d 條台詞、%d 張插圖" % (DST, len(out["chapters"]), total, len(out["illustrations"])))
for c in out["chapters"]:
    print("  %s　開場 %d／失敗 %d／過關 %d　任務卡 %d 行" % (
        c["title"], len(c["intro"]), len(c["lose"]), len(c["outro"]),
        len(c["level"].get("brief", {}).get("lines", []))))
print("  結局「%s」%d 條" % (out.get("ending_title", "?"), len(out.get("ending", []))))
for e in errors:
    print("  ! " + e)
sys.exit(1 if errors else 0)
