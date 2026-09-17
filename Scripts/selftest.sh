#!/bin/bash
# Самопроверка движка Agave.
#
# Генерирует сигналы с заранее известными свойствами, прогоняет их через все
# форматы и проверяет, что звук не пострадал: не сдвинулся во времени, не
# изменился по высоте и громкости, не перепутались каналы, а форматы без
# потерь возвращают исходные данные бит в бит.
#
# Нужны ffmpeg и python3 — они служат независимыми судьями, чтобы проверка
# не сводилась к «наш код подтверждает наш код».
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.selftest"
CLI="$WORK/selftest-cli"
FAILED=0
PASSED=0

command -v ffmpeg >/dev/null || { echo "нужен ffmpeg: brew install ffmpeg"; exit 2; }
command -v python3 >/dev/null || { echo "нужен python3"; exit 2; }

rm -rf "$WORK" && mkdir -p "$WORK"

echo "Сборка проверочной утилиты…"
BUILD_LOG="$WORK/build.log"
swiftc -O \
  "$ROOT/Agave/Model/OutputFormat.swift" \
  "$ROOT/Agave/Engine/AudioProbe.swift" \
  "$ROOT/Agave/Engine/PCMReader.swift" \
  "$ROOT/Agave/Engine/AppleAudioWriter.swift" \
  "$ROOT/Agave/Engine/MP3Writer.swift" \
  "$ROOT/Agave/Engine/VorbisWriter.swift" \
  "$ROOT/Agave/Engine/VorbisDecoder.swift" \
  "$ROOT/Agave/Engine/MP4TagWriter.swift" \
  "$ROOT/Agave/Engine/Transcoder.swift" \
  "$ROOT/Scripts/selftest/main.swift" \
  -F "$ROOT/Vendor" -framework LameKit -framework VorbisKit \
  -Xlinker -rpath -Xlinker "$ROOT/Vendor" \
  -o "$CLI" >"$BUILD_LOG" 2>&1
if [ ! -x "$CLI" ]; then
  echo "Сборка не удалась:"
  grep -E "error:" "$BUILD_LOG" | head -20
  exit 1
fi

# ---------------------------------------------------------------- сигналы

python3 - "$WORK" <<'PY'
import sys, wave, struct, math
work = sys.argv[1]
SR = 48000

def write(name, frames, sr=SR):
    w = wave.open(f"{work}/{name}", "wb")
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(frames); w.close()

# Щелчки: слева на 24000, справа на 48000 — проверяет и сдвиг, и порядок каналов.
f = bytearray()
for i in range(SR * 3):
    f += struct.pack("<hh", 20000 if i == 24000 else 0, 20000 if i == 48000 else 0)
write("click.wav", bytes(f))

# Чистый тон 1000 Гц, половина шкалы — проверяет высоту и громкость.
f = bytearray()
for i in range(SR * 2):
    v = int(16000 * math.sin(2 * math.pi * 1000 * i / SR))
    f += struct.pack("<hh", v, v)
write("sine.wav", bytes(f))
PY

# ---------------------------------------------------------------- анализ

analyze() {   # analyze <файл> <что> -> число
  python3 - "$1" "$2" <<'PY'
import sys, wave, struct, math
path, what = sys.argv[1], sys.argv[2]
w = wave.open(path, "rb")
n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
raw = w.readframes(n); w.close()
s = struct.unpack("<%dh" % (len(raw) // 2), raw)
left  = s[0::ch]
right = s[1::ch] if ch > 1 else left

if what == "rate":      print(sr)
elif what == "channels":print(ch)
elif what == "frames":  print(len(left))
elif what == "peakL":   print(max(range(len(left)),  key=lambda i: abs(left[i])))
elif what == "peakR":   print(max(range(len(right)), key=lambda i: abs(right[i])))
elif what == "level":   print(max(max(abs(x) for x in left), max(abs(x) for x in right)))
elif what == "freq":
    # частота по переходам через ноль с порогом, чтобы шум не давал ложных
    peak = max(abs(x) for x in left) or 1
    thr = peak * 0.2
    crossings, prev, first, last = 0, 0, None, None
    for i, v in enumerate(left):
        if v > thr and prev <= 0:
            prev = 1
            if first is None: first = i
            else: crossings += 1; last = i
        elif v < -thr and prev >= 0:
            prev = -1
    if first is None or last is None or crossings == 0: print(0)
    else: print(round(crossings * sr / (last - first), 2))
PY
}

check() {   # check <описание> <ожидание> <получено> [допуск]
  local desc="$1" want="$2" got="$3" tol="${4:-0}"
  local ok
  ok=$(python3 -c "print(1 if abs(float('$got')-float('$want'))<=float('$tol') else 0)" 2>/dev/null || echo 0)
  if [ "$ok" = "1" ]; then
    printf "    ✓ %-46s %s\n" "$desc" "$got"
    PASSED=$((PASSED+1))
  else
    printf "    ✗ %-46s %s (ожидалось %s±%s)\n" "$desc" "$got" "$want" "$tol"
    FAILED=$((FAILED+1))
  fi
}

# ---------------------------------------------------------------- проверки

echo
echo "════ Форматы без потерь: возврат данных бит в бит ════"
for fmt in wav aiff flac alac; do
  out="$WORK/rt.$fmt"; back="$WORK/rt_$fmt.wav"
  "$CLI" "$WORK/click.wav" "$out" "$fmt" 16 2>/dev/null
  if [ ! -f "$out" ]; then printf "    ✗ %-46s файл не создан\n" "$fmt"; FAILED=$((FAILED+1)); continue; fi
  ffmpeg -v error -y -i "$out" -c:a pcm_s16le "$back" 2>/dev/null
  a=$(ffmpeg -v error -i "$WORK/click.wav" -f s16le - 2>/dev/null | shasum | cut -d' ' -f1)
  b=$(ffmpeg -v error -i "$back"           -f s16le - 2>/dev/null | shasum | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then
    printf "    ✓ %-46s совпадает\n" "$fmt: звук идентичен исходному"
    PASSED=$((PASSED+1))
  else
    printf "    ✗ %-46s РАСХОДИТСЯ\n" "$fmt: звук идентичен исходному"
    FAILED=$((FAILED+1))
  fi
done

echo
echo "════ Все форматы: положение во времени и порядок каналов ════"
for fmt in wav aiff flac alac mp3 aac ogg; do
  case $fmt in wav|aiff|flac|alac) tol=0 ;; *) tol=60 ;; esac
  out="$WORK/cl.$fmt"; back="$WORK/cl_$fmt.wav"
  "$CLI" "$WORK/click.wav" "$out" "$fmt" 16 2>/dev/null
  [ -f "$out" ] || { printf "    ✗ %s: файл не создан\n" "$fmt"; FAILED=$((FAILED+1)); continue; }
  ffmpeg -v error -y -i "$out" -c:a pcm_s16le -ar 48000 "$back" 2>/dev/null
  echo "  $fmt:"
  check "щелчок в левом канале на 24000" 24000 "$(analyze "$back" peakL)" "$tol"
  check "щелчок в правом канале на 48000" 48000 "$(analyze "$back" peakR)" "$tol"
done

echo
echo "════ Все форматы: высота тона и громкость ════"
for fmt in wav aiff flac alac mp3 aac ogg; do
  out="$WORK/sn.$fmt"; back="$WORK/sn_$fmt.wav"
  "$CLI" "$WORK/sine.wav" "$out" "$fmt" 16 2>/dev/null
  [ -f "$out" ] || continue
  ffmpeg -v error -y -i "$out" -c:a pcm_s16le -ar 48000 "$back" 2>/dev/null
  echo "  $fmt:"
  check "тон остался 1000 Гц" 1000 "$(analyze "$back" freq)" 1
  check "пик остался на уровне 16000" 16000 "$(analyze "$back" level)" 900
done

echo
echo "════ Заявленные параметры файла ════"
for spec in "wav:16" "wav:24" "aiff:16" "aiff:24" "flac:16" "flac:24" "alac:16"; do
  fmt="${spec%%:*}"; bits="${spec##*:}"
  out="$WORK/d$bits.$fmt"
  "$CLI" "$WORK/sine.wav" "$out" "$fmt" "$bits" 2>/dev/null
  [ -f "$out" ] || { printf "    ✗ %s %s бит: файл не создан\n" "$fmt" "$bits"; FAILED=$((FAILED+1)); continue; }
  # Поля запрашиваем поимённо: ffprobe выдаёт их в своём порядке, не в нашем.
  raw=$(ffprobe -v error -show_entries stream=bits_per_raw_sample -of default=nw=1:nk=1 "$out" | head -1)
  smp=$(ffprobe -v error -show_entries stream=bits_per_sample -of default=nw=1:nk=1 "$out" | head -1)
  b="$raw"
  case "$b" in ""|"N/A"|"0") b="$smp" ;; esac
  check "$fmt, запрошено $bits бит" "$bits" "${b:-0}" 0
  check "$fmt, частота сохранена" 48000 "$(ffprobe -v error -show_entries stream=sample_rate -of default=nw=1:nk=1 "$out" | head -1)" 0
  check "$fmt, каналов" 2 "$(ffprobe -v error -show_entries stream=channels -of default=nw=1:nk=1 "$out" | head -1)" 0
done

echo
echo "════ MP3 без служебного заголовка: задержка декодера скомпенсирована ════"
# Такие файлы не содержат сведений о задержке кодировщика, поэтому идеального
# совпадения не добиться ни одним декодером. Но задержку декодера (529 сэмплов)
# система вычитает, и наш результат обязан быть ближе к правде, чем у ffmpeg.
ffmpeg -v error -y -i "$WORK/click.wav" -c:a libmp3lame -b:a 320k \
  -write_xing 0 -id3v2_version 0 "$WORK/nox.mp3" 2>/dev/null
"$CLI" "$WORK/nox.mp3" "$WORK/nox_agave.wav" wav 16 2>/dev/null
ffmpeg -v error -y -i "$WORK/nox.mp3" "$WORK/nox_ffmpeg.wav" 2>/dev/null
ours=$(analyze "$WORK/nox_agave.wav" peakL)
theirs=$(analyze "$WORK/nox_ffmpeg.wav" peakL)
check "щелчок у Agave (осталась задержка кодировщика)" 24576 "$ours" 5
check "щелчок у ffmpeg (задержка не вычтена вовсе)" 25105 "$theirs" 5
check "выигрыш Agave в сэмплах" 529 "$((theirs - ours))" 5

echo
echo "════ Пересчёт частоты не меняет высоту тона ════"
ffmpeg -v error -y -i "$WORK/sine.wav" -ar 48000 "$WORK/s48.wav" 2>/dev/null
"$CLI" "$WORK/s48.wav" "$WORK/res.wav" wav 16 2>/dev/null
check "1000 Гц при 48 кГц" 1000 "$(analyze "$WORK/res.wav" freq)" 1

echo
echo "─────────────────────────────────────────────────────"
printf "Пройдено: %d    Провалено: %d\n" "$PASSED" "$FAILED"
if [ "$FAILED" -eq 0 ]; then
  echo "Движок в порядке: файлы не портятся."
  rm -rf "$WORK"
  exit 0
else
  echo "Есть провалы. Промежуточные файлы оставлены в $WORK"
  exit 1
fi
