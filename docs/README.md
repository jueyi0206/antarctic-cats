# 網頁版

這個資料夾是 Godot 匯出的網頁版，**直接就是 GitHub Pages 的網站根目錄**。

放上 GitHub 之後：
1. 進 repo 的 **Settings → Pages**
2. Source 選 **Deploy from a branch**，分支選 `main`、資料夾選 **/docs**
3. 等一兩分鐘，網址會是 `https://<帳號>.github.io/<repo>/`

手機用瀏覽器打開就能玩，觸控介面會自動出現。

重新匯出（在 antarctic/ 底下）：

    Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" docs/index.html

注意事項：
- `.nojekyll` 不要刪掉，GitHub Pages 才不會用 Jekyll 處理這些檔案。
- 匯出設定沒有開執行緒支援，所以不需要 COOP/COEP 標頭，GitHub Pages 直接能跑。
- 改過台詞或程式裡會顯示的字之後，要重跑 `python tools/subset_font.py`，
  不然網頁版會出現方框（電腦版看不出來，因為會用系統字型補）。
