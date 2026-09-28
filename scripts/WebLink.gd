class_name WebLink
## 網頁版：在畫布上疊一個真正的 HTML <a>，蓋住插圖那一塊。
##
## 為什麼不用 OS.shell_open：Godot 是在 requestAnimationFrame 裡處理點擊的，
## 離真正的點擊事件差了幾毫秒，手機瀏覽器會判定「不是使用者直接操作」而擋掉新分頁。
## 真人實測就是這樣 —— 電腦開得起來，手機點了沒反應。
##
## 換成真的 <a target="_blank">：點的是瀏覽器自己的元素，不經過遊戲，誰都不會擋。
##
## 代價是那一塊的點擊被 <a> 接走，遊戲收不到 —— 結束畫面本來就只想讓人點圖，剛好。

const ELEMENT_ID := "godot-ext-link"

## 檯面的虛擬解析度，用來把遊戲座標換算成畫面上的位置
const GAME_W := 720.0
const GAME_H := 1280.0

## %s = 網址（JSON 字串）、%f x4 = 遊戲座標的方框
const _SHOW := """
(function(){
  var id = %s;
  var a = document.getElementById(id);
  if (!a) {
    a = document.createElement('a');
    a.id = id;
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.style.position = 'fixed';
    a.style.zIndex = '50';
    a.style.background = 'transparent';
    document.body.appendChild(a);
  }
  a.href = %s;
  a.style.display = 'block';
  window.__gdLinkRect = [%f, %f, %f, %f];
  if (!window.__gdLinkPlace) {
    window.__gdLinkPlace = function(){
      var el = document.getElementById(%s);
      var c = document.querySelector('canvas');
      if (!el || !c || !window.__gdLinkRect) return;
      var r = c.getBoundingClientRect();
      var s = Math.min(r.width / %f, r.height / %f);
      var ox = r.left + (r.width - %f * s) / 2;
      var oy = r.top + (r.height - %f * s) / 2;
      var q = window.__gdLinkRect;
      el.style.left = (ox + q[0] * s) + 'px';
      el.style.top = (oy + q[1] * s) + 'px';
      el.style.width = (q[2] * s) + 'px';
      el.style.height = (q[3] * s) + 'px';
    };
    window.addEventListener('resize', window.__gdLinkPlace);
    window.addEventListener('orientationchange', window.__gdLinkPlace);
    // 手機轉向、網址列縮起來都會改變畫布大小，定期對位比追事件可靠
    setInterval(window.__gdLinkPlace, 400);
  }
  window.__gdLinkPlace();
})();
"""

const _HIDE := """
(function(){
  var a = document.getElementById(%s);
  if (a) a.style.display = 'none';
  window.__gdLinkRect = null;
})();
"""


## rect 是檯面座標（720x1280）裡要變成連結的那一塊
static func show(url: String, rect: Rect2) -> void:
	if not OS.has_feature("web") or url == "":
		hide()
		return
	var id := JSON.stringify(ELEMENT_ID)
	JavaScriptBridge.eval(_SHOW % [
		id, JSON.stringify(url),
		rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		id, GAME_W, GAME_H, GAME_W, GAME_H], true)


static func hide() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(_HIDE % JSON.stringify(ELEMENT_ID), true)
