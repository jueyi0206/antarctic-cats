# -*- coding: utf-8 -*-
"""把綠幕的姿勢表切成一張一張透明 PNG。

用法（在 antarctic/ 底下執行）：
    python tools/cut_sprites.py ling run run2 jump hit
    python tools/cut_sprites.py props grass_s grass_m grass_l --tight --out art/props

會讀 art/source/game/<名字>_sheet.jpg，找出圖上分開的幾團圖案，
照閱讀順序（先上排、再下排，每排由左到右）依序對應後面給的姿勢名稱，
用不到的那一張寫 `x` 就會跳過，
寫成 `run2=run` 則是把已經切好的 `run` 水平翻轉存成 `run2`（左右對稱的貓用這招換腳最準），
輸出 art/cats/<名字>_<姿勢>.png。

預設**共用同一張畫布與同一個縮放比例**（貓用這個）：遊戲裡貓是照固定寬度畫的，
各自裁切會讓同一隻貓忽大忽小、腳的位置也會跳。

`--tight` 改成**各自貼緊裁切**（道具、地形用這個）：每張只留自己那一團，四周不補空白。
縮放比例仍然是整張共用的，所以大小關係會保留 —— 大叢貓草切出來就是比小叢的大。
共用畫布會讓小東西在自己的圖裡縮成一小點，尺寸也不好對。

`--out <資料夾>` 換輸出位置，預設 art/cats。
`--from <檔案>` 指定來源圖（預設是 art/source/game/<名字>_sheet.jpg），
用在「同一隻貓、另外補幾張姿勢」的時候。

`--keep-green` 不做去綠邊：圖案本身是綠色的（貓草）時一定要加，
不然細草葉會被當成綠幕邊緣，鮮綠被壓成橄欖綠。

去背沿用 ../pinball/tools/key_green.py 的做法（G - max(R,B) 判斷綠幕、邊緣去綠）。
"""
import os
import sys

from PIL import Image, ImageChops, ImageFilter

SRC = os.path.join("art", "source", "game")
DST = os.path.join("art", "cats")

LO = 90
HI = 160
EDGE_RADIUS = 3
PAD = 16
MAX_SIDE = 320          # 遊戲裡一隻貓大約 100px 寬，存 3 倍
OUTLINE = (0x3B, 0x2A, 0x25)
MIN_BLOB = 0.004        # 小於整張圖這個比例的色塊當成雜點丟掉


def _lut(fn):
    return [max(0, min(255, int(round(fn(v))))) for v in range(256)]


def _bg_levels(diff):
    """量綠幕本身有多綠，決定去背門檻。

    Nano Banana 的綠幕不一定是純 #00FF00：有一張是 (61,201,32)，G - max(R,B) 只有 140，
    固定門檻 HI=160 會讓整片背景變成半透明。取四邊一圈的中位數，門檻往下調到比它低一點。
    """
    w, h = diff.size
    edge = []
    for x in range(0, w, 8):
        edge += [diff.getpixel((x, 2)), diff.getpixel((x, h - 3))]
    for y in range(0, h, 8):
        edge += [diff.getpixel((2, y)), diff.getpixel((w - 3, y))]
    edge.sort()
    bg = edge[len(edge) // 2]
    hi = min(HI, bg - 12)
    lo = min(LO, hi - 45)
    return lo, hi, bg


def key_rgba(img, keep_green=False):
    r, g, b = img.convert("RGB").split()
    max_rb = ImageChops.lighter(r, b)
    diff = ImageChops.subtract(g, max_rb)
    lo, hi, bg = _bg_levels(diff)
    if hi < HI:
        print("綠幕偏暗（G-max(R,B)=%d），去背門檻改成 %d~%d" % (bg, lo, hi))
    alpha = diff.point(_lut(
        lambda v: 255 if v <= lo else 0 if v >= hi else 255 * (hi - v) / (hi - lo)))

    w, h = alpha.size
    solid = alpha.point(_lut(lambda v: 255 if v > 200 else 0))
    near = solid.resize((w // 4 + 1, h // 4 + 1), Image.BOX)
    near = near.point(_lut(lambda v: 255 if v > 0 else 0)).filter(ImageFilter.MaxFilter(5))
    alpha = ImageChops.multiply(alpha, near.resize((w, h), Image.NEAREST))

    # 去綠邊：靠近透明處的一圈把 G 壓下來。
    # 但圖案本身就是綠色時（貓草）不能做 —— 細細的草葉整片都在這一圈裡，
    # 壓完會從鮮綠變成橄欖綠。
    if not keep_green:
        near_clear = alpha.point(_lut(lambda v: 255 if v < 250 else 0))
        band = near_clear.filter(ImageFilter.MaxFilter(EDGE_RADIUS * 2 + 1))
        g = Image.composite(ImageChops.darker(g, max_rb), g, band)

    out = Image.merge("RGBA", (r, g, b, alpha))
    clear = alpha.point(_lut(lambda v: 255 if v == 0 else 0))
    return Image.composite(Image.new("RGBA", out.size, OUTLINE + (0,)), out, clear)


def blobs(rgba):
    """回傳每一團圖案的框 (x0, y0, x1, y1)。用縮小後的遮罩做氾濫填滿，夠快也夠準。"""
    step = 4
    a = rgba.getchannel("A").point(_lut(lambda v: 255 if v > 40 else 0))
    w, h = a.width // step, a.height // step
    mask = a.resize((w, h), Image.BOX).filter(ImageFilter.MaxFilter(5))
    px = mask.load()
    seen = [[False] * w for _ in range(h)]
    boxes = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0][x0] or px[x0, y0] < 128:
                continue
            stack = [(x0, y0)]
            seen[y0][x0] = True
            bx0 = bx1 = x0
            by0 = by1 = y0
            n = 0
            while stack:
                x, y = stack.pop()
                n += 1
                bx0, bx1 = min(bx0, x), max(bx1, x)
                by0, by1 = min(by0, y), max(by1, y)
                for qx, qy in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= qx < w and 0 <= qy < h and not seen[qy][qx] and px[qx, qy] >= 128:
                        seen[qy][qx] = True
                        stack.append((qx, qy))
            if n >= MIN_BLOB * w * h:
                m = Image.new("L", (w, h), 0)
                mp = m.load()
                for qy in range(by0, by1 + 1):
                    for qx in range(bx0, bx1 + 1):
                        if seen[qy][qx] and px[qx, qy] >= 128:
                            mp[qx, qy] = 255
                boxes.append(((bx0 * step, by0 * step, (bx1 + 1) * step, (by1 + 1) * step),
                              m.resize(a.size, Image.NEAREST).filter(ImageFilter.MaxFilter(9))))
    return boxes


def _reading_order(boxes):
    """照閱讀順序排：先分出上下幾排，每一排再由左到右。

    AI 排姿勢表時常常排成兩排，而且第二排的起點不會對齊第一排。
    純粹用 x 排序會把上下兩排交錯在一起，姿勢就全對錯了。
    這裡用「垂直位置有沒有重疊超過一半」來分排。
    """
    rows = []
    for item in sorted(boxes, key=lambda t: t[0][1]):
        (x0, y0, x1, y1), _m = item
        h = y1 - y0
        placed = False
        for row in rows:
            ry0 = min(b[0][1] for b in row)
            ry1 = max(b[0][3] for b in row)
            overlap = min(y1, ry1) - max(y0, ry0)
            if overlap > 0.5 * min(h, ry1 - ry0):
                row.append(item)
                placed = True
                break
        if not placed:
            rows.append([item])
    out = []
    for row in rows:
        out.extend(sorted(row, key=lambda t: t[0][0]))
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    args = sys.argv[1:]
    tight = "--tight" in args
    keep_green = "--keep-green" in args
    args = [a for a in args if a not in ("--tight", "--keep-green")]
    sheet_override = ""
    if "--from" in args:
        i = args.index("--from")
        sheet_override = args[i + 1]
        del args[i:i + 2]
    out_dir = DST
    if "--out" in args:
        i = args.index("--out")
        out_dir = args[i + 1]
        del args[i:i + 2]
    name = args[0]
    # 「新姿勢=舊姿勢」表示水平翻轉既有的那張，不吃圖上的任何一團。
    # 左右對稱的貓（例如全白的莎莎）用這招做換腳最準：兩張一定完全相反
    poses = [a for a in args[1:] if "=" not in a]
    mirrors = [a.split("=", 1) for a in args[1:] if "=" in a]
    src = sheet_override if sheet_override else os.path.join(SRC, name + "_sheet.jpg")
    if not os.path.exists(src):
        print("找不到 " + src)
        return 1

    rgba = key_rgba(Image.open(src), keep_green)
    boxes = blobs(rgba)
    boxes = _reading_order(boxes)
    print("找到 %d 團圖案，要 %d 個姿勢" % (len(boxes), len(poses)))
    for b, _m in boxes:
        print("   x %4d~%4d   y %4d~%4d   %dx%d" % (b[0], b[2], b[1], b[3], b[2] - b[0], b[3] - b[1]))
    if len(boxes) != len(poses):
        print("數量對不上 —— 姿勢之間要留夠大的空隙，或是姿勢名稱給錯了")
        return 1

    # 共用畫布：取最大的那一團，四周留白
    cw = max(b[2] - b[0] for b, _m in boxes) + PAD * 2
    ch = max(b[3] - b[1] for b, _m in boxes) + PAD * 2
    side = max(cw, ch)
    scale = min(1.0, MAX_SIDE / side)

    os.makedirs(out_dir, exist_ok=True)
    for pose, (b, mask) in zip(poses, boxes):
        if pose in ("x", "-"):        # 用不到的那一張，切圖時跳過
            print("(跳過一張)")
            continue
        cx = (b[0] + b[2]) / 2
        cy = (b[1] + b[3]) / 2
        # 各自貼緊裁切：畫布換成自己的框，縮放比例照樣是整張共用的
        box_w = b[2] - b[0] + PAD * 2
        box_h = b[3] - b[1] + PAD * 2
        # 只留自己那一團：共用畫布比單一姿勢寬，光看框還會把隔壁那隻的尾巴切進來，
        # 所以用氾濫填滿量出來的遮罩擋掉
        only = rgba.copy()
        only.putalpha(ImageChops.multiply(only.getchannel("A"), mask))
        cw_i = box_w if tight else side
        ch_i = box_h if tight else side
        crop = only.crop((round(cx - cw_i / 2), round(cy - ch_i / 2),
                          round(cx + cw_i / 2), round(cy + ch_i / 2)))
        canvas = Image.new("RGBA", (cw_i, ch_i), OUTLINE + (0,))
        canvas.alpha_composite(crop)
        if scale < 1.0:
            size = (max(1, round(cw_i * scale)), max(1, round(ch_i * scale)))
            canvas = canvas.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
        dst = os.path.join(out_dir, "%s_%s.png" % (name, pose))
        canvas.save(dst, optimize=True)
        print("%s  ->  %s  %dx%d" % (pose, dst, canvas.width, canvas.height))

    for dst_pose, src_pose in mirrors:
        src = os.path.join(out_dir, "%s_%s.png" % (name, src_pose))
        if not os.path.exists(src):
            print("找不到要翻轉的 " + src)
            return 1
        out = Image.open(src).transpose(Image.FLIP_LEFT_RIGHT)
        dst = os.path.join(out_dir, "%s_%s.png" % (name, dst_pose))
        out.save(dst, optimize=True)
        print("%s  ->  %s  （%s 的水平翻轉）" % (dst_pose, dst, src_pose))
    return 0


if __name__ == "__main__":
    sys.exit(main())
