# 網頁版／手機版檢查清單

網頁版有三件事在桌面版上**永遠測不出來**，而且都是在 `../pinball` 已經踩過、
解過一次的坑。從 pinball 移植任何東西過來、或開新專案時，照這張表走一遍。

## 1. 中文缺字

`fonts/NotoSansTC-Game.ttf` 是**子集**字型，只含這個專案掃得到的字。
桌面版缺字時會自動用系統字型補上，所以看不出問題；網頁版沒有系統字型，直接變方框。

```
python tools/subset_font.py            # 掃字、重新產生子集
python tools/subset_font.py --check    # 列出字型裡沒有的字
```

掃描範圍寫在 `tools/subset_font.py` 裡：`story/SCRIPT.md` 全文、`data/*.json`、
`data/levels/*.json`，以及程式裡寫死的 UI 字串。**新增任何畫面文字後都要重跑。**
另外注意冷僻符號：Noto Sans TC 沒有 `✗`（U+2717），要用 `×`。

## 2. QR code / 外部連結點不動

`OS.shell_open()` 在手機瀏覽器會被擋掉。Godot 是在 `requestAnimationFrame`
裡處理輸入的，等到程式呼叫 `shell_open` 時，瀏覽器已經不認為這是「使用者直接點的」，
於是把新分頁當成彈出式廣告攔下來。桌面版沒這個限制，所以本機測不出來。

解法是 `scripts/WebLink.gd`（從 `../pinball/scripts/web_link.gd` 搬過來的）：
在畫布上疊一個真正的 HTML `<a target="_blank">`，讓瀏覽器自己處理點擊。

- 劇本裡用 `連結：<url>` 一行掛在圖示上，`tools/build_campaign.py` 會收進 `campaign.json`
- `scripts/Story.gd` 在 `OS.has_feature("web")` 時呼叫 `WebLink.show(url, 圖框範圍)`，
  換頁與離開場景都要 `WebLink.hide()`
- `dev/link_test.tscn` 驗資料那一半；「真的開得了新分頁」只能在手機上點一次

**手機玩家沒辦法掃自己螢幕上的 QR code**，所以有 QR 的頁面一定要同時能點。

## 3. 觸控

手機沒有鍵盤。`scripts/Touch.gd`（autoload，layer 8）只在關卡畫面生效：
左半邊按下去就長出搖桿（轉向／往下拉煞車，自動全速），右半邊點擊跳，右上角暫停。
劇情畫面本來就能點擊翻頁，那一層不攔輸入。

電腦上按 `T` 可以強制打開觸控層，用滑鼠試手感。

## 出一版

```
& "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Web" docs/index.html
```

`docs/` 就是 GitHub Pages 的來源（`main` 分支 `/docs`）。細節見 [docs/README.md](docs/README.md)。
匯出後把不小心跑進去的 `docs/*.import` 刪掉。

## 最後一關：真的用手機走一遍

四關跑到結局，特別是最後兩頁 QR code 要點得開。
線上版：<https://jueyi0206.github.io/antarctic-cats/>
