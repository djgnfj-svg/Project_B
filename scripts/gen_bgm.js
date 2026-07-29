// 절차 BGM 생성 — 망령 보스 테마 (D 단조, ~20초 심리스 루프)
// gen_sfx.py와 같은 철학: 파형을 코드로 합성. 적은 요소(4)로 위압+유령감.
//   1) 드론 pad (저역 D, 듀얼 디튠)  2) 발현 베이스(플럭 트라이앵글, 8분 오스티나토)
//   3) 유령 리드(사인+트라이앵글, 비브라토+디튠)  4) 타이코 킥(사인 스윕) + 노이즈 히트
// 실행: node scripts/gen_bgm.js  → assets/audio/bgm/boss_wraith_theme.wav
const fs = require('fs');

const SR = 44100;
const BPM = 92;
const BEAT = 60 / BPM;          // 초/박
const BAR = BEAT * 4;
const BARS = 8;
const DUR = BAR * BARS;         // 총 길이(초)
const N = Math.floor(DUR * SR);
const buf = new Float32Array(N);

const m2f = (n) => 440 * Math.pow(2, (n - 69) / 12);
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

// 파형
function osc(kind, ph) {
  const t = ph - Math.floor(ph);               // 0..1
  switch (kind) {
    case 'sine': return Math.sin(2 * Math.PI * t);
    case 'tri':  return 4 * Math.abs(t - 0.5) - 1;
    case 'saw':  return 2 * t - 1;
    case 'sq':   return t < 0.5 ? 1 : -1;
    case 'noise':return Math.random() * 2 - 1;
  }
  return 0;
}
// ADSR (초 단위)
function env(t, dur, a, d, s, r) {
  if (t < 0) return 0;
  if (t < a) return t / a;
  if (t < a + d) return 1 - (1 - s) * (t - a) / d;
  if (t < dur) return s;
  if (t < dur + r) return s * (1 - (t - dur) / r);
  return 0;
}
// 음 하나를 버퍼에 더함
function note(startS, durS, midi, kind, vol, adsr, opts = {}) {
  const f = m2f(midi);
  const detune = opts.detune || 0;             // 반음의 소수(디튠)
  const f2 = m2f(midi + detune);
  const vib = opts.vib || 0;                    // 비브라토 깊이(Hz)
  const vibRate = opts.vibRate || 5;
  const glide = opts.glideFrom || 0;            // 시작 주파수 배율(킥 스윕용)
  const s0 = Math.floor(startS * SR);
  const s1 = Math.min(N, Math.floor((startS + durS + adsr[4] + 0.05) * SR));
  let ph = 0, ph2 = 0;
  for (let i = s0; i < s1; i++) {
    const t = (i - s0) / SR;
    const e = env(t, durS, adsr[0], adsr[1], adsr[2], adsr[3], adsr[4]);
    if (e <= 0 && t > durS) continue;
    const vv = vib ? Math.sin(2 * Math.PI * vibRate * t) * vib : 0;
    let fr = f + vv;
    if (glide) fr = f * (glide + (1 - glide) * clamp(t / (durS * 0.5), 0, 1)); // 킥: 배율→1
    ph += fr / SR;
    ph2 += (f2 + vv) / SR;
    let smp = osc(kind, ph);
    if (detune) smp = 0.5 * (smp + osc(kind, ph2));           // 듀얼 디튠
    buf[i] += smp * vol * e;
  }
}
function kick(startS) {
  // 타이코: 110→48Hz 스윕 사인, 짧은 감쇠
  note(startS, 0.12, 45.7 /*~110Hz*/, 'sine', 0.9, [0.002, 0.05, 0.4, 0.0, 0.12], { glideFrom: 2.3 });
  // 클릭
  note(startS, 0.02, 60, 'noise', 0.15, [0.001, 0.01, 0.0, 0.0, 0.02]);
}
function hit(startS, vol) {
  note(startS, 0.10, 70, 'noise', vol, [0.001, 0.02, 0.2, 0.0, 0.10]); // 셰이커/스플래시
}

// ── 곡 구성 (D 단조 하모닉) ──
// 각 바: [베이스 루트 midi, 리드 midi, 리드2 midi(옵션)]
const D=[38,62,74], A=[45,69], Bb=[46,70], C=[48,72], G=[43,67], Cs=[49,73];
const bars = [
  { root:38, chord:[38,41,45], lead:[[0,2,69]], swamp:false }, // Dm  lead A4
  { root:38, chord:[38,41,45], lead:[[0,2,65],[2,2,62]] },     // Dm  F4→D4
  { root:46, chord:[46,50,53], lead:[[0,4,74]] },              // Bb  D5(long)
  { root:48, chord:[48,52,55], lead:[[0,2,70],[2,2,72]] },     // C   Bb4→C5
  { root:38, chord:[38,41,45], lead:[[0,2,69]] },              // Dm  A4
  { root:43, chord:[43,46,50], lead:[[0,4,70]] },              // Gm  Bb4
  { root:45, chord:[45,49,52], lead:[[0,4,73]] },              // A   C#5 (긴장)
  { root:45, chord:[45,49,52], lead:[[0,1,73],[1,1,72],[2,2,69]] }, // A→해결 준비
];

// 1) 드론 — 저역 D2, 전 구간, 듀얼 디튠(미세 흔들림), 아주 낮게
note(0, DUR, 38, 'saw', 0.10, [1.5, 0.5, 0.85, 2.0, 2.0], { detune: 0.06 });
note(0, DUR, 50, 'sine', 0.045, [2.0, 0.5, 0.8, 2.0, 2.0], { detune: -0.05 }); // 5도 위 얇은 패드

for (let b = 0; b < BARS; b++) {
  const t0 = b * BAR;
  const B = bars[b];
  // 2) 발현 베이스 — 8분 오스티나토(루트·루트·5도·루트 …), 플럭
  const fifth = B.root + 7;
  const seq = [B.root, B.root, fifth, B.root, B.root, B.root, fifth, B.root];
  for (let e = 0; e < 8; e++) {
    note(t0 + e * (BEAT/2), 0.28, seq[e], 'tri', 0.30, [0.004, 0.12, 0.25, 0.14, 0.30]);
  }
  // 3) 유령 리드 — 사인+트라이앵글 느낌(사인 vib), 디튠 코러스, 스파스
  for (const [lb, ld, lm] of B.lead) {
    note(t0 + lb * BEAT, ld * BEAT * 0.9, lm, 'sine', 0.22,
      [0.04, 0.3, 0.7, 0.25, 0.9], { detune: 0.04, vib: 4, vibRate: 5.5 });
    note(t0 + lb * BEAT, ld * BEAT * 0.9, lm - 12, 'tri', 0.07,
      [0.05, 0.3, 0.6, 0.25, 0.9], { vib: 3, vibRate: 5 }); // 옥타브 아래 얇게
  }
  // 옅은 코드 아르페지오 (분위기) — 후반부에만
  if (b >= 4) {
    for (let c = 0; c < 3; c++)
      note(t0 + (c*1.33) * BEAT, 0.5, B.chord[c] + 12, 'tri', 0.05, [0.02,0.2,0.3,0.2,0.5]);
  }
  // 4) 타이코 킥 — 1·3박. 후반(빌드)엔 2·4박도 + 4박에 노이즈 히트
  kick(t0 + 0 * BEAT);
  kick(t0 + 2 * BEAT);
  if (b >= 4) { kick(t0 + 1 * BEAT); kick(t0 + 3 * BEAT); hit(t0 + 3.5 * BEAT, 0.12); }
}

// ── 심리스 루프용: 앞/뒤 아주 짧은 크로스 페이드는 생략(드론이 연속이라 자연 연결) ──
// 정규화
let peak = 0;
for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(buf[i]));
const g = peak > 0 ? 0.89 / peak : 1;
const pcm = Buffer.alloc(N * 2);
for (let i = 0; i < N; i++) {
  let s = clamp(buf[i] * g, -1, 1);
  // 소프트 클립(따뜻하게)
  s = Math.tanh(s * 1.1);
  pcm.writeInt16LE(Math.round(s * 32767), i * 2);
}
// WAV 헤더
function wav(pcmBuf) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcmBuf.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22); h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcmBuf.length, 40);
  return Buffer.concat([h, pcmBuf]);
}
const out = 'assets/audio/bgm/boss_wraith_theme.wav';
fs.writeFileSync(out, wav(pcm));
console.log(`wrote ${out}  (${DUR.toFixed(1)}s, ${(pcm.length/1024).toFixed(0)}KB, ${BPM}BPM D단조)`);
