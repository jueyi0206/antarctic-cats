# 合成 audio/*.wav。從專案根目錄執行： python tools/make_audio.py
# 沒有外部相依，只用標準函式庫。改完波形參數重跑即可覆蓋。
# 作法沿用 ../pinball/tools/make_audio.py。

import wave, struct, math, random

SR = 22050


def w(name, samples):
    d = b''.join(struct.pack('<h', max(-32767, min(32767, int(s * 32767)))) for s in samples)
    f = wave.open("audio/" + name, 'wb')
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
    f.writeframes(d); f.close()
    print(name, round(len(samples) / SR, 3), "s")


def env(i, n, a=0.004, p=3.0):
    t = i / SR
    return min(t / a, 1.0) * ((1.0 - i / n) ** p)


def sweep(i, n, f0, f1):
    t = i / SR; T = n / SR
    return math.sin(2 * math.pi * (f0 * t + (f1 - f0) * t * t / (2 * T)))


def sq(i, f, duty=0.5):
    return 1.0 if (i * f / SR) % 1.0 < duty else -1.0


random.seed(19830412)

# 起跳：短促上揚的「咻」，方波帶一點空氣感
n = int(SR * 0.16)
w("jump.wav", [env(i, n, 0.004, 2.2) * (0.42 * sweep(i, n, 300, 720)
   + 0.16 * sq(i, 300 + 420 * i / n, 0.3)
   + 0.08 * random.uniform(-1, 1) * (1 - i / n) ** 3) for i in range(n)])

# 落地：踩在冰上的輕「喀」
n = int(SR * 0.09)
w("land.wav", [env(i, n, 0.002, 4.0) * (0.34 * math.sin(2 * math.pi * 210 * i / SR)
   + 0.30 * random.uniform(-1, 1) * (1 - i / n) ** 6) for i in range(n)])

# 掉進水裡：噗通 + 水花碎響
n = int(SR * 0.52)
w("splash.wav", [env(i, n, 0.003, 1.5) * (0.46 * sweep(i, n, 380, 70)
   + 0.30 * random.uniform(-1, 1) * (1 - i / n) ** 1.6
   + 0.12 * math.sin(2 * math.pi * 1600 * i / SR) * (1 - i / n) ** 5) for i in range(n)])

# 撞到旗竿：木頭「叩」＋竿子倒下的顫動
n = int(SR * 0.30)
w("trip.wav", [env(i, n, 0.002, 2.4) * (0.44 * math.sin(2 * math.pi * 520 * i / SR)
   + 0.20 * math.sin(2 * math.pi * 1180 * i / SR)
   + 0.18 * random.uniform(-1, 1) * (1 - i / n) ** 7
   + 0.10 * math.sin(2 * math.pi * 92 * i / SR) * (i / n)) for i in range(n)])

# 被海豹頂飛：低沉的「嗷」再加一記悶撞
n = int(SR * 0.44)
w("seal.wav", [env(i, n, 0.012, 1.8) * (0.40 * math.sin(2 * math.pi *
      (150 + 46 * math.sin(2 * math.pi * 5.5 * i / SR)) * i / SR)
   + 0.26 * math.sin(2 * math.pi * 300 * i / SR)
   + 0.18 * random.uniform(-1, 1) * (1 - i / n) ** 4) for i in range(n)])

# 吃到魚：木琴。C5-E5-G5 三音琶音，比其他音效低一個八度、泛音收掉大半，
# 刻意不搶戲 —— 吃魚是常態動作，響亮的話一路上會很吵。
# 4 倍與 6.3 倍泛音（敲擊樂器的泛音不是整數倍，這是它像木頭不像電子音的原因）。
# 其他候選在 tools/make_fish_variants.py。
def marimba(i, n, f, decay=22.0, h4=0.12, h6=0.035):
    t = i / SR
    e = min(t / 0.002, 1.0) * math.exp(-t * decay)
    return e * (math.sin(2 * math.pi * f * t)
                + h4 * math.sin(2 * math.pi * f * 4.0 * t)
                + h6 * math.sin(2 * math.pi * f * 6.3 * t))

n = int(SR * 0.26)
step = int(SR * 0.045)
w("fish.wav", [0.30 * sum(marimba(i - j * step, n, f)
               for j, f in enumerate([523.25, 659.25, 783.99]) if i >= j * step)
               for i in range(n)])

# 穿過黃旗：木琴單音，比吃魚更短更高。同一個樂器家族，但一聽就知道是別的東西。
n = int(SR * 0.17)
w("point.wav", [0.52 * marimba(i, n, 1046.5, decay=24.0, h4=0.20, h6=0.06)
                for i in range(n)])

# 時間快用完的滴答
n = int(SR * 0.07)
w("tick.wav", [env(i, n, 0.001, 5.0) * 0.30 *
   (sq(i, 1760, 0.25) + 0.3 * random.uniform(-1, 1) * (1 - i / n) ** 8) for i in range(n)])


# 時間到：下墜的洩氣聲
n = int(SR * 0.9)
w("timeup.wav", [env(i, n, 0.01, 1.3) * (0.38 * sweep(i, n, 440, 66)
   + 0.22 * sweep(i, n, 220, 33)
   + 0.10 * random.uniform(-1, 1) * (1 - i / n) ** 2) for i in range(n)])


# 小玲插旗：一下短短的「噗」—— 木棍插進雪裡的悶聲，很小聲，
# 因為它每 1.5 秒就會響一次，稍微大聲一點就會變成噪音
n = int(SR * 0.10)
w("flag.wav", [env(i, n, 0.002, 6.0) * 0.22 *
   (0.6 * math.sin(2 * math.pi * 320 * i / SR)
    + 0.4 * random.uniform(-1, 1) * (1 - i / n) ** 3) for i in range(n)])


# 撿到木天蓼：一小段往上衝的琶音，比吃魚誇張，但不要蓋過過關音
n = int(SR * 0.45)
notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
seg = n // len(notes)
def power_s(i):
    k = min(i // seg, len(notes) - 1)
    li = i - k * seg
    ln = seg if k < len(notes) - 1 else n - k * seg
    return env(li, ln, 0.003, 2.2) * 0.30 * (marimba(i, n, notes[k], decay=18.0, h4=0.25, h6=0.10)
        + 0.25 * math.sin(2 * math.pi * notes[k] * 2 * i / SR))
w("power.wav", [power_s(i) for i in range(n)])


# 過關音效不在這裡合成 —— 合成出來的號角都很塑膠。
# 現在用的是 Flow 生的曲子剪出來的 audio/music/goal.ogg（見 tools/trim_music.py）。
