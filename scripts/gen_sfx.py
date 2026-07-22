#!/usr/bin/env python3
# Project_B 절차적 SFX 생성 — 순수 stdlib(numpy 불필요). 레트로 픽셀 톤.
# 출력: assets/audio/sfx/*.wav (mono 22050Hz 16-bit)
import wave, struct, math, random, os

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..",
                   "..", "Desktop", "godot_games", "Project_B", "assets", "audio", "sfx")
# 위 상대경로는 스크래치패드 위치에 의존 — 실제로는 인자로 받은 절대경로를 쓴다
import sys
if len(sys.argv) > 1:
    OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

def write_wav(name, samples):
    # samples: list of float -1..1
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32000)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("wrote", path, len(samples), "samples")

def n(dur):
    return int(SR * dur)

def env_ad(i, total, attack, release):
    # attack/release는 초. 삼각형 엔벨로프
    t = i / SR
    dur = total / SR
    a = attack
    if t < a:
        return t / a if a > 0 else 1.0
    rt = dur - release
    if t > rt:
        return max(0.0, (dur - t) / release) if release > 0 else 0.0
    return 1.0

def square(phase):
    return 1.0 if (phase % (2*math.pi)) < math.pi else -1.0

def lowpass(samples, alpha):
    out = []
    y = 0.0
    for x in samples:
        y = y + alpha * (x - y)
        out.append(y)
    return out

random.seed(42)

# 1. swing — 에어리한 "쉭" 스워시(고역 노이즈, 부드럽고 조용하게)
def swing():
    total = n(0.16)
    raw = [(random.random()*2-1) for _ in range(total)]
    lp = lowpass(raw, 0.35)
    hp = [raw[i] - lp[i] for i in range(total)]  # 고역 성분 = airy
    body = lowpass(hp, 0.7)                       # 살짝 다듬어 거친 잡음 제거
    out = []
    dur = total / SR
    for i in range(total):
        t = i / SR
        # 빠른 상승 후 완만한 하강 — 휘두르며 지나가는 바람
        e = (t / 0.02) if t < 0.02 else max(0.0, 1.0 - (t - 0.02) / (dur - 0.02))
        out.append(body[i] * e * 0.4)  # 낮은 볼륨
    return out

# 2. hit — 펀치(저음 사각파 thud + 시작 노이즈 트랜지언트)
def hit():
    total = n(0.11)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.002, 0.09)
        t = i / SR
        f = 160 - 60*(t/(total/SR))  # 살짝 하강
        ph += 2*math.pi*f/SR
        tone = 0.6 * square(ph)
        trans = 0.7 * (random.random()*2-1) * math.exp(-t*90)  # 초반 딱
        out.append((tone*0.7 + trans) * e)
    return lowpass(out, 0.6)

# 3. hurt — 내가 맞음(사각파 하강 + 노이즈), hit보다 낮고 김
def hurt():
    total = n(0.16)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.003, 0.13)
        t = i / SR
        f = 220 - 110*(t/(total/SR))
        ph += 2*math.pi*f/SR
        tone = 0.55 * square(ph)
        noise = 0.35 * (random.random()*2-1) * math.exp(-t*30)
        out.append((tone + noise) * e * 0.9)
    return lowpass(out, 0.45)

# 4. roll — 회피 훅(노이즈 스웰, 먹먹하게)
def roll():
    total = n(0.26)
    out = []
    for i in range(total):
        e = env_ad(i, total, 0.06, 0.16)
        noise = (random.random()*2-1)
        out.append(noise * e * 0.55)
    return lowpass(lowpass(out, 0.25), 0.25)  # 이중 로우패스 = 먹먹한 바람소리

# 5. enemy_death — 하강 사각파 + 노이즈 꼬리
def enemy_death():
    total = n(0.28)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.004, 0.20)
        t = i / SR
        f = 320 - 240*(t/(total/SR))
        ph += 2*math.pi*f/SR
        tone = 0.5 * square(ph)
        noise = 0.25 * (random.random()*2-1) * math.exp(-t*12)
        out.append((tone + noise) * e * 0.9)
    return lowpass(out, 0.5)

# 6. player_death — 더 낮고 긴 하강 사인(무겁게)
def player_death():
    total = n(0.45)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.01, 0.30)
        t = i / SR
        f = 240 - 180*(t/(total/SR))
        ph += 2*math.pi*f/SR
        tone = 0.6 * math.sin(ph) + 0.2*square(ph)
        out.append(tone * e * 0.9)
    return lowpass(out, 0.55)

# 7. drop — 아이템 착지 "틱"(짧은 클릭 + 낮은 하강 톤, 조용하게)
def drop():
    total = n(0.08)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.001, 0.06)
        t = i / SR
        f = 420 - 160*(t/(total/SR))
        ph += 2*math.pi*f/SR
        tone = 0.4 * square(ph)
        click = 0.5 * (random.random()*2-1) * math.exp(-t*120)  # 초반 딱
        out.append((tone*0.5 + click) * e * 0.4)
    return lowpass(out, 0.5)

# 8. pickup_item — 일반 픽업(상승 블립, 밝게)
def pickup_item():
    total = n(0.12)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.004, 0.08)
        t = i/(total/SR)
        f = 520 + 420*t  # 상승
        ph += 2*math.pi*f/SR
        out.append(0.45 * square(ph) * e * 0.55)
    return lowpass(out, 0.6)

# 9. pickup_gold — 코인 두 톤(밝은 사인 짤랑)
def pickup_gold():
    total = n(0.18)
    out = []
    ph = 0.0
    for i in range(total):
        e = env_ad(i, total, 0.002, 0.12)
        t = i/(total/SR)
        f = 880 if t < 0.4 else 1320  # 두 단계 짤랑
        ph += 2*math.pi*f/SR
        out.append((0.4*math.sin(ph) + 0.18*math.sin(2*ph)) * e * 0.5)
    return out

# 10. blueprint — 도면 획득 팡파레(상승 아르페지오 C-E-G-C)
def blueprint():
    total = n(0.42)
    out = []
    ph = 0.0
    notes = [523, 659, 784, 1047]
    seg = max(1, total // len(notes))
    for i in range(total):
        e = env_ad(i, total, 0.004, 0.16)
        idx = min(len(notes)-1, i // seg)
        ph += 2*math.pi*notes[idx]/SR
        local = (i % seg) / seg
        ne = 1.0 if local > 0.05 else local/0.05  # 각 음 시작 어택
        out.append((0.35*math.sin(ph) + 0.14*square(ph)) * e * ne * 0.5)
    return out

write_wav("swing", swing())
write_wav("hit", hit())
write_wav("hurt", hurt())
write_wav("roll", roll())
write_wav("enemy_death", enemy_death())
write_wav("player_death", player_death())
write_wav("drop", drop())
write_wav("pickup_item", pickup_item())
write_wav("pickup_gold", pickup_gold())
write_wav("blueprint", blueprint())
print("done")
