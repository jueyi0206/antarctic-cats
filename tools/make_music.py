# 合成 audio/bgm_run.wav —— 一首會無縫循環的 chiptune 圓舞曲。
# 從專案根目錄執行： python tools/make_music.py
# 沒有外部相依，只用標準函式庫。
#
# 原作《けっきょく南極大冒険》用的是蕭邦的《小狗圓舞曲》（公有領域）。
# 這裡沒有直接重建那首曲子 —— 憑記憶寫很容易走音 —— 而是寫一首同樣是
# 3/4 拍、同樣輕快的原創圓舞曲當作暫代。要換成真曲子或 AI 生的音樂，
# 流程照 ../pinball/MUSIC.md：原檔丟 audio/source/，用 make_loop.py 剪成 ogg。

import wave, struct, math, random

SR = 22050
BPM = 168.0                 # 快速圓舞曲
BEAT = 60.0 / BPM           # 一拍 0.357 秒

A4 = 440.0
NAMES = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4,
         'F#': -3, 'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}


def freq(name):
    if name == '-':
        return 0.0
    octave = int(name[-1])
    semi = NAMES[name[:-1]]
    return A4 * (2.0 ** (semi / 12.0 + (octave - 4)))


def square(phase, duty=0.5):
    return 1.0 if phase % 1.0 < duty else -1.0


def triangle(phase):
    x = phase % 1.0
    return 4.0 * abs(x - 0.5) - 1.0


# 主旋律：D 大調，A(8 小節) B(8) A(8) B(8)，每小節 3 拍
A_PART = [
    ('D5', 1), ('F#5', .5), ('A5', .5), ('F#5', 1),
    ('G5', 1), ('E5', 1), ('C#5', 1),
    ('D5', 1), ('F#5', .5), ('A5', .5), ('D6', 1),
    ('C#6', 1.5), ('A5', 1.5),
    ('B5', 1), ('G5', .5), ('B5', .5), ('G5', 1),
    ('A5', 1), ('F#5', 1), ('D5', 1),
    ('E5', 1), ('G5', .5), ('B5', .5), ('A5', 1),
    ('D5', 2), ('-', 1),
]
B_PART = [
    ('A5', 1), ('C#6', .5), ('E6', .5), ('C#6', 1),
    ('B5', 1), ('G5', 1), ('E5', 1),
    ('F#5', 1), ('A5', .5), ('C#6', .5), ('A5', 1),
    ('B5', 1.5), ('F#5', 1.5),
    ('G5', 1), ('B5', .5), ('D6', .5), ('B5', 1),
    ('A5', 1), ('F#5', 1), ('A5', 1),
    ('G5', 1), ('E5', 1), ('C#5', 1),
    ('D5', 2), ('-', 1),
]
MELODY = A_PART + B_PART + A_PART + B_PART

# 每小節的和弦：根音 + 兩個和弦音（圓舞曲的 oom-pah-pah）
A_CHORDS = [
    ('D3', ['A3', 'D4']), ('A2', ['A3', 'C#4']), ('D3', ['A3', 'D4']), ('A2', ['A3', 'C#4']),
    ('G2', ['B3', 'D4']), ('D3', ['A3', 'D4']), ('A2', ['A3', 'C#4']), ('D3', ['A3', 'D4']),
]
B_CHORDS = [
    ('A2', ['A3', 'C#4']), ('E3', ['B3', 'E4']), ('A2', ['A3', 'C#4']), ('B2', ['B3', 'D4']),
    ('G2', ['B3', 'D4']), ('D3', ['A3', 'D4']), ('A2', ['A3', 'C#4']), ('D3', ['A3', 'D4']),
]
CHORDS = A_CHORDS + B_CHORDS + A_CHORDS + B_CHORDS

TOTAL_BARS = len(CHORDS)
TOTAL = int(TOTAL_BARS * 3 * BEAT * SR)
buf = [0.0] * TOTAL
random.seed(1983)


def add(start, dur, f, amp, kind='sq', duty=0.5, attack=0.006, release=0.55):
    if f <= 0.0:
        return
    n = int(dur * SR)
    for i in range(n):
        p = start + i
        if p >= TOTAL:
            break
        t = i / SR
        a = min(t / attack, 1.0)
        r = 1.0 - (i / n) ** 1.0
        e = a * (r ** release)
        # 一點點抖音，純方波太死
        ph = f * t * (1.0 + 0.0016 * math.sin(2 * math.pi * 5.2 * t))
        v = square(ph, duty) if kind == 'sq' else triangle(ph)
        buf[p] += v * amp * e


# 旋律
pos = 0
for name, beats in MELODY:
    dur = beats * BEAT
    add(int(pos * SR), dur * 0.94, freq(name), 0.26, 'sq', 0.42)
    pos += dur

# 低音與和弦
for bar, (root, chord) in enumerate(CHORDS):
    bar_t = bar * 3 * BEAT
    add(int(bar_t * SR), BEAT * 0.9, freq(root), 0.30, 'tri')
    for beat in (1, 2):
        for cn in chord:
            add(int((bar_t + beat * BEAT) * SR), BEAT * 0.45, freq(cn), 0.075, 'sq', 0.22)
    # 第一拍的低頻打點，讓腳步有著力處
    n = int(0.05 * SR)
    for i in range(n):
        p = int(bar_t * SR) + i
        if p < TOTAL:
            buf[p] += 0.16 * random.uniform(-1, 1) * (1 - i / n) ** 5

# 首尾各 12ms 交叉淡化，循環接縫才不會「噠」一聲
x = int(0.012 * SR)
for i in range(x):
    k = i / x
    buf[i] = buf[i] * k + buf[TOTAL - x + i] * (1 - k)

peak = max(abs(v) for v in buf) or 1.0
gain = 0.82 / peak
data = b''.join(struct.pack('<h', int(max(-32767, min(32767, v * gain * 32767)))) for v in buf)
f = wave.open("audio/bgm_run.wav", 'wb')
f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
f.writeframes(data); f.close()
print("bgm_run.wav", round(TOTAL / SR, 2), "s /", TOTAL_BARS, "小節 /", BPM, "BPM")
