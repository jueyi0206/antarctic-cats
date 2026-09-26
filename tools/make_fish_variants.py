# 吃到魚的音效候選（木琴系）。從專案根目錄執行： python tools/make_fish_variants.py
# 產生 audio/candidates/fish_*.wav，用檔案總管直接點開就能聽。
# 選好之後把對應的參數搬進 tools/make_audio.py 的 fish 那一段。

import wave, struct, math

SR = 22050


def w(path, samples):
    d = b''.join(struct.pack('<h', max(-32767, min(32767, int(s * 32767)))) for s in samples)
    f = wave.open(path, 'wb')
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
    f.writeframes(d); f.close()
    peak = max(abs(s) for s in samples)
    print("%-38s %.2fs  峰值 %.2f" % (path, len(samples) / SR, peak))


def marimba(i, n, f, decay, h4, h6, amp):
    """木琴／馬林巴：基頻為主，加 4 倍與 6.3 倍泛音（敲擊樂器的泛音不是整數倍）。
    decay 越大收得越快，h4 / h6 越小越溫暖不亮。"""
    t = i / SR
    e = min(t / 0.002, 1.0) * math.exp(-t * decay)
    return amp * e * (math.sin(2 * math.pi * f * t)
                      + h4 * math.sin(2 * math.pi * f * 4.0 * t)
                      + h6 * math.sin(2 * math.pi * f * 6.3 * t))


def arp(path, notes, gap, dur, decay, h4, h6, amp):
    n = int(SR * dur)
    step = int(SR * gap)
    w(path, [sum(marimba(i - j * step, n, f, decay, h4, h6, amp)
                 for j, f in enumerate(notes) if i >= j * step) for i in range(n)])


# 全部降一個八度（C5-E5-G5），泛音大幅收掉，音量壓低
C5, E5, G5 = 523.25, 659.25, 783.99

# 低調版 —— 預設採用
arp("audio/candidates/fish_soft.wav", [C5, E5, G5],
    gap=0.045, dur=0.26, decay=22.0, h4=0.12, h6=0.035, amp=0.30)

# 再更輕：兩個音、收得更快，幾乎只是「噠叮」一聲
arp("audio/candidates/fish_softest.wav", [C5, G5],
    gap=0.040, dur=0.20, decay=28.0, h4=0.08, h6=0.02, amp=0.24)

# 稍微亮一點（如果上面兩個在遊戲裡聽不見就用這個）
arp("audio/candidates/fish_soft_bright.wav", [C5, E5, G5],
    gap=0.045, dur=0.28, decay=20.0, h4=0.20, h6=0.06, amp=0.36)
