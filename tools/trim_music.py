# -*- coding: utf-8 -*-
"""從 AI 生的長曲子裡剪出要用的一小段（過關號角、失敗提示）。

Flow 生出來的都是一兩分鐘的完整曲子，但遊戲要的是 5 秒的號角和 12 秒的失落句。
這支負責「聽」完整首、找出適合的段落，再剪出來轉成 ogg。

用法（在 antarctic/ 底下執行）：
    python tools/trim_music.py look  <檔案>                 # 只分析，印出每半秒的音量與樂句起點
    python tools/trim_music.py cut   <輸入> <輸出.ogg> <起點秒> <長度秒> [淡出秒]
    python tools/trim_music.py norm  <輸入> <輸出.ogg> [目標 RMS dB，預設 -18]

「樂句起點」是用能量的上升沿找的：前後 0.2 秒的平均音量突然變大就算一次起音。
剪的時候把起點對到起音上，聽起來才不會像從中間切進去。

循環用的曲子請改用 ../pinball/tools/make_loop.py，那支會找波形最像的兩點接起來。
"""
import os
import subprocess
import sys

import numpy as np

SR = 48000


def decode(path, channels=1):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", str(channels), "-ar", str(SR),
         "-f", "f32le", "-"], capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return a.reshape(-1, channels) if channels > 1 else a


def encode(samples, path):
    peak = np.abs(samples).max()
    if peak > 0.99:
        samples = samples * (0.99 / peak)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
         "-i", "-", "-c:a", "libvorbis", "-q:a", "4", path],
        input=samples.astype(np.float32).tobytes(), check=True)


def envelope(mono, step=0.1):
    """每 step 秒的音量（0~1）"""
    w = int(SR * step)
    n = len(mono) // w
    e = np.array([np.sqrt((mono[i * w:(i + 1) * w] ** 2).mean()) for i in range(n)])
    return e / max(e.max(), 1e-9)


def onsets(env, thresh=0.16):
    """能量上升沿 = 樂句起點。回傳 env 的索引"""
    d = np.diff(env, prepend=env[0])
    out = []
    for i, v in enumerate(d):
        if v > thresh and (not out or i - out[-1] > 3):
            out.append(i)
    return out


def look(path):
    mono = decode(path)
    env = envelope(mono)
    print("%s　%.1f 秒" % (os.path.basename(path), len(mono) / SR))
    print("音量（每 0.5 秒一格，0-9）：")
    line = ""
    for i in range(0, len(env), 5):
        line += str(min(int(env[i:i + 5].max() * 9.99), 9))
        if len(line) >= 60:
            print("  %6.1fs  %s" % ((i - 59 * 5) * 0.1, line))
            line = ""
    if line:
        print("  %6.1fs  %s" % ((len(env) - len(line) * 5) * 0.1, line))
    hits = onsets(env)
    print("樂句起點（秒）：", ", ".join("%.1f" % (i * 0.1) for i in hits[:40]))
    # 最安靜、最稀疏的 12 秒（失落句適合從這裡拿）
    w = 120
    if len(env) > w:
        scores = [(env[i:i + w].mean(), i) for i in range(0, len(env) - w, 5)]
        scores.sort()
        print("最安靜的 12 秒段落：", ", ".join("%.1fs" % (i * 0.1) for _, i in scores[:5]))


def cut(src, dst, start, length, fade_out=0.6, fade_in=0.02):
    stereo = decode(src, 2)
    a = int(start * SR)
    b = min(a + int(length * SR), len(stereo))
    seg = stereo[a:b].copy()
    fi = int(fade_in * SR)
    fo = int(fade_out * SR)
    if fi > 0:
        seg[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    if fo > 0:
        seg[-fo:] *= np.cos(np.linspace(0, np.pi / 2, fo))[:, None] ** 2
    encode(seg, dst)
    print("%s  %.1fs~%.1fs（%.1f 秒）→ %s" % (
        os.path.basename(src), start, start + (b - a) / SR, (b - a) / SR, dst))


def norm(src, dst, target_db=-18.0):
    """把整段拉到指定的 RMS 響度。

    從「最安靜的段落」剪出來的東西（例如失敗提示）本來就比其他曲子小聲十幾 dB，
    直接放會聽不到。這裡只動增益，不做壓縮，所以音樂的起伏還是原本的樣子。
    """
    stereo = decode(src, 2)
    mono = stereo.mean(axis=1)
    rms = float(np.sqrt((mono ** 2).mean()))
    gain = (10.0 ** (target_db / 20.0)) / max(rms, 1e-9)
    peak = float(np.abs(stereo).max()) * gain
    if peak > 0.99:                      # 別爆掉
        gain *= 0.99 / peak
    out = stereo * gain
    encode(out, dst)
    print("%s  RMS %.1f dB → %.1f dB（增益 %+.1f dB）→ %s" % (
        os.path.basename(src), 20 * np.log10(max(rms, 1e-9)),
        20 * np.log10(max(float(np.sqrt((out.mean(axis=1) ** 2).mean())), 1e-9)),
        20 * np.log10(gain), dst))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    mode = sys.argv[1]
    if mode == "look":
        look(sys.argv[2])
    elif mode == "norm":
        norm(sys.argv[2], sys.argv[3],
             float(sys.argv[4]) if len(sys.argv) > 4 else -18.0)
    elif mode == "cut":
        cut(sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]),
            float(sys.argv[6]) if len(sys.argv) > 6 else 0.6)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
