#!/usr/bin/env python3
"""Assemble the Shipaton demo video from a raw iPhone screen recording.

Usage:
  python3 scripts/build-demo-video.py [--purchase CLIP.mov] [--out out.mp4]

The raw recording is expected at ~/Downloads/ScreenRecording_09-29-2026 14-06-47_1.MP4
(override with --raw). An optional --purchase clip (purchase / restore footage) is
inserted before the end card. Output: 1920x1080, 30 fps, H.264, no audio.
"""
import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (8, 14, 21)
GOLD = (201, 169, 110)
INK = (240, 236, 226)
MUTED = (150, 160, 170)
PHONE_H = 1000
CROP_TOP = 112  # px of the 2436-tall source: status bar + recording pill

STORE_URL = "apps.apple.com/us/app/tamor-jewel-ring/id6814390528"

# (label, source start, source end, speed, caption, sub-caption)
SEGMENTS = [
    ("ring", 4.5, 9.0, 1, "A ring of gems\nyou earn with skill.", "Not luck. Not stamina timers."),
    ("break", 10.0, 21.0, 1, "Diamond - Glass Break", "Tap each red dot before time runs out."),
    ("spot", 21.0, 27.0, 1, "Inspect every gem", "Tap to spotlight it, swipe to rotate."),
    ("trace", 61.0, 79.0, 1, "Ruby - Glass Trace", "Follow the green dot. Three cracks and it's over."),
    ("crush", 86.0, 100.0, 1, "Obsidian - Crusher Room", "10 seconds. Hit the weak point for a higher grade."),
    ("kuru", 106.0, 149.0, 3, "Sapphire - Kurukuru World", "Find pairs that spin the same way. (3x speed)"),
    ("box", 159.0, 166.0, 1, "Your Gem Box", "Every gem you earn stays."),
    ("depths", 185.0, 187.2, 1, "Depths 1-3 are free", "Depths 4-6 need the one-time World 1 unlock."),
    ("pay", 187.2, 190.4, 1, "One purchase, no gems sold", "It unlocks access to Depths 4-6. Skill still decides the carats."),
]


def font(size, bold=False):
    for path, idx in (("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0),
                      ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0)):
        try:
            return ImageFont.truetype(path, size, index=idx)
        except Exception:
            continue
    return ImageFont.load_default()


def caption_png(path, title, sub):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((130, 120), "TAMOR", font=font(34, True), fill=GOLD)
    y = 380
    for line in title.split("\n"):
        d.text((130, y), line, font=font(74, True), fill=INK)
        y += 92
    d.text((130, y + 24), sub, font=font(36), fill=MUTED)
    im.save(path)


def title_card(path, lines, small=None, url=None):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    y = 330
    for text, size, color, bold in lines:
        w = d.textlength(text, font=font(size, bold))
        d.text(((W - w) / 2, y), text, font=font(size, bold), fill=color)
        y += int(size * 1.35)
    if small:
        w = d.textlength(small, font=font(34))
        d.text(((W - w) / 2, y + 30), small, font=font(34), fill=MUTED)
    if url:
        w = d.textlength(url, font=font(34, True))
        d.text(((W - w) / 2, y + 100), url, font=font(34, True), fill=GOLD)
    im.save(path)


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def encode_still(png, out, secs):
    run(["ffmpeg", "-y", "-loop", "1", "-i", str(png), "-t", str(secs), "-r", "30",
         "-vf", f"scale={W}:{H},format=yuv420p", "-c:v", "libx264", "-crf", "18", "-an", str(out)])


def encode_phone(src, out, start, end, speed, cap_png, phone_w=None):
    dur = (end - start)
    vf = (f"[0:v]crop=iw:ih-{CROP_TOP}:0:{CROP_TOP},setpts=(PTS-STARTPTS)/{speed},"
          f"scale=-2:{PHONE_H},fps=30[ph];"
          f"color=c=#{BG[0]:02x}{BG[1]:02x}{BG[2]:02x}:s={W}x{H}:r=30[bg];"
          f"[bg][ph]overlay=x=1180:y=40:shortest=1[a];"
          + (f"[a][1:v]overlay=0:0[v]" if cap_png else "[a]null[v]"))
    cmd = ["ffmpeg", "-y", "-ss", str(start), "-t", str(dur), "-i", str(src)]
    if cap_png:
        cmd += ["-i", str(cap_png)]
    cmd += ["-filter_complex", vf, "-map", "[v]", "-t", str(dur / speed),
            "-c:v", "libx264", "-crf", "19", "-pix_fmt", "yuv420p", "-an", str(out)]
    run(cmd)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.expanduser("~/Downloads/ScreenRecording_09-29-2026 14-06-47_1.MP4"))
    ap.add_argument("--purchase", help="optional purchase/restore clip to insert before the end card")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "docs/release/shipaton/out/tamor-demo.mp4"))
    a = ap.parse_args()
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)

    tmp = Path(tempfile.mkdtemp(prefix="tamor-demo-"))
    parts = []

    p = tmp / "title.png"
    title_card(p, [("TAMOR", 150, INK, True), ("Break glass. Chase light. Collect gems.", 46, GOLD, False)],
               small="Four skill mini-games · real-time Metal jewels")
    encode_still(p, tmp / "00_title.mp4", 3)
    parts.append(tmp / "00_title.mp4")

    for i, (label, s, e, sp, title, sub) in enumerate(SEGMENTS, 1):
        c = tmp / f"cap_{label}.png"
        caption_png(c, title, sub)
        o = tmp / f"{i:02d}_{label}.mp4"
        encode_phone(a.raw, o, s, e, sp, c)
        parts.append(o)

    if a.purchase:
        c = tmp / "cap_purchase.png"
        caption_png(c, "Purchase and restore", "Powered by RevenueCat. Restore Purchases brings the unlock back.")
        o = tmp / "90_purchase.mp4"
        run(["ffmpeg", "-y", "-i", a.purchase, "-i", str(c),
             "-filter_complex",
             f"[0:v]setpts=PTS-STARTPTS,scale=-2:{PHONE_H},fps=30[ph];"
             f"color=c=#{BG[0]:02x}{BG[1]:02x}{BG[2]:02x}:s={W}x{H}:r=30[bg];"
             f"[bg][ph]overlay=x=1180:y=40:shortest=1[a];[a][1:v]overlay=0:0[v]",
             "-map", "[v]", "-c:v", "libx264", "-crf", "19", "-pix_fmt", "yuv420p", "-an", str(o)])
        parts.append(o)

    p = tmp / "end.png"
    title_card(p, [("TAMOR", 130, INK, True), ("Available now on the App Store", 48, GOLD, False)],
               small="Free: Depths 1-3 · One-time unlock: Depths 4-6", url=STORE_URL)
    encode_still(p, tmp / "99_end.mp4", 4)
    parts.append(tmp / "99_end.mp4")

    lst = tmp / "list.txt"
    lst.write_text("".join(f"file '{x}'\n" for x in parts))
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", a.out])
    print(a.out)


if __name__ == "__main__":
    sys.exit(main())
