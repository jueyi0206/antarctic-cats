# 南極大冒險（Antarctic Adventure）

貓咪在南極冰面上跑，時限內抵達下一個科考基地。劇情見 [STORY.md](STORY.md)。致敬 Konami《けっきょく南極大冒険》(1983)。
引擎：Godot 4.7.2（標準版 / GDScript）。與 `../pinball` 是兩個各自獨立的專案。

## 現在是什麼階段

**Phase 0 — 手感原型。** 這個版本不是遊戲，是一台調參數的機器：
用來回答「[LEVELS.md](LEVELS.md) 第 3 節那些物理常數，手感對不對」。
在有人真的用手玩過之前，那些數字全都只是紙上估計。

## 執行

用 Godot 開啟本資料夾（`project.godot`），按 **F5**：從第一章劇情開始，
走「開場劇情 → 任務卡 → 關卡 → 過關劇情（或失敗劇情後重跑）→ 下一章」。
流程在 `scripts/Flow.gd`，劇情播放在 `scenes/Story.tscn`，內容全部讀 `story/campaign.json`。
劇情頁按 `Esc` 整段跳過。插圖放在 `art/story/<id>.png`（1024×1024），沒放圖會顯示該畫什麼。

只想測關卡：在編輯器開 `scenes/Main.tscn` 按 **F6**，就是下面這套舊的測試模式。
四站，每站一條封閉迴圈賽道、各繞 2 圈（經典跑道 / 八字 / 蛇形摺疊 / 獎勵關，賽道允許立體交叉），過關後按空白鍵接著跑下一站。開場進**第一站**。按 `1` 可以切到「跳躍實驗室」：一排寬度從 80u 遞增到 240u 的缺口，
每個旁邊標著理論上該不該跳得過去 —— 用身體去驗證那條推論。
（實驗室是刻意的純直線，沒有彎道、冰洞和魚。想看關卡長什麼樣請按 `2` / `3`。）

| 鍵 | 動作 |
|---|---|
| `A` / `←`、`D` / `→` | 左右移動 |
| `Space` | 跳 |
| `W` / `↑`（按住） | 加速 |
| `S` / `↓`（按住） | 減速 |
| `Space`（過關後）| 前往下一站 |
| `1` ~ `4` | 直接跳到該站（第四關是獎勵關）|
| `L` | 跳躍實驗室 |
| `N` | 直接跳下一站 |
| `.` / `,` | **測試用**：沿賽道前進／後退 1000u |
| `B` | **測試用**：直接跳到下一段暴風雪 |
| `F` / `G` | **測試用**：直接失敗／直接過關（右下角也有按鈕）|
| `R` | 重跑這一關 |
| `P` | 叫出／收起右邊的參數台（預設收起）|
| `Tab` | 切換要調的參數 |
| `Q` / `E` | 把選中的參數 −／＋ |
| `F5` / `F9` | 把目前參數存成 `tuning.json` ／ 載回來 |
| `H` | 收起／展開下方的關卡驗證訊息 |
| `Esc` | 暫停／繼續（暫停時 HUD 會列出當下的賽道寬度與中心線）|
| `F12` | 存一張畫面到 `user://`，路徑會印在畫面與主控台 |
| `Shift` + `Esc` | 離開 |

左上角是**賽道地圖**：整條封閉迴圈畫在裡面（像賽車遊戲那樣），
白點是你、黃點是起終點、紅點是前方 1600u 內的裂縫與海豹，下面寫第幾圈和完成百分比。

畫面上的 **LAST JUMP** 是上一次實際跳出來的距離，
底下那行「理論值」是同一組參數推算出來的。**這兩個數字對不對得上，是這支原型唯一要回答的事。**

## 關卡驗證（不用開畫面）

在引擎所在的 `E:\Godot_v4.7.2-stable_win64.exe\` 資料夾裡開 PowerShell：

```powershell
.\Godot_v4.7.2-stable_win64_console.exe --headless --path antarctic res://dev/validate.tscn
```

（Windows PowerShell 5.1 不吃 `&&`，要串兩個指令請用 `;`。）

會把 `data/levels/` 底下每張關卡展開，檢查缺口跳不跳得過、助跑夠不夠、
時間餘裕夠不夠、三星達不達得到，然後印一張表。改完數值先跑這個，再開畫面。

## 檔案

| 路徑 | 是什麼 |
|---|---|
| [LEVELS.md](LEVELS.md) | 關卡架構：物理常數、段落積木、難度曲線、驗證規則 |
| [STORY.md](STORY.md) | 劇情：貓咪的南極遠征，角色沿用 ../pinball 的世界觀 |
| [STORY-PROMPT.md](STORY-PROMPT.md) | 給其他模型寫劇情用的提示詞（兩個版本）|
| [PROMPTS.md](PROMPTS.md) | 生圖提示詞：三隻貓的設定圖與五張劇情插圖 |
| [TUNING.md](TUNING.md) | 手感數值的版本紀錄 —— 改壞了要回得去 |
| [WEB.md](WEB.md) | 網頁版／手機版檢查清單：字型子集、可點的連結、觸控 —— 桌面版測不出來的那三件事 |
| [AUDIO.md](AUDIO.md) | 音效與音樂：全部程式合成，怎麼改怎麼重生 |
| `scripts/Constants.gd` | 所有可調的物理常數（autoload `Cfg`） |
| `scripts/TrackPath.gd` | 賽道形狀：原型控制點 + Catmull-Rom + 等弧長重取樣 |
| `scripts/TrackBuilder.gd` | 把關卡配方展開成障礙，並跑驗證器 |
| `scripts/Main.gd` | 遊戲本體：移動、碰撞、繪製、參數面板 |
| `scripts/Audio.gd` | 音效池與 BGM（autoload `Aud`）|
| `tools/make_audio.py` · `make_music.py` | 合成 `audio/*.wav`，零外部相依 |
| `data/segments.json` | 12 塊段落積木 |
| `data/levels/*.json` | 關卡配方（權重 + seed + 釘死的橋段，不存展開結果） |
| `dev/validate.tscn` | headless 關卡驗證器 |
| `dev/track_preview.tscn` | 把每關賽道畫成 PNG 到 `dev/preview/`，看形狀用 |

要出網頁版或手機版之前，先讀 [WEB.md](WEB.md)。
