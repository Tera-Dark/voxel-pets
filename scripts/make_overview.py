#!/usr/bin/env python3
"""Builds the one-image UI overview (Chinese captions) from rendered snapshots.

Usage: python3 scripts/make_overview.py <snap_dir> <out_png> <version>
Snapshots come from `lune run tools/ui_snapshot` + `python3 scripts/render_ui.py`.
Captions use NotoSansCJK (system font) because the pixel font has no CJK glyphs.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SNAP_DIR = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ui_snapshots"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/home/user/ui_preview.png"
VERSION = sys.argv[3] if len(sys.argv) > 3 else "dev"

# (file, caption)
PANELS = [
    ("01_loading", "启动加载页（左上角有版本印章）"),
    ("02_first_join_partner_picker", "首次进入：三选一初始伙伴"),
    ("03_tutorial_pointer_battle", "新手引导：指向出战按钮"),
    ("05_battle_playback", "自动战斗：血条、能量、日志"),
    ("06_battle_result", "战斗结算与奖励"),
    ("07_hatch_unlocked_pointer", "孵蛋屋解锁提示"),
    ("09_hatch_result", "孵化结果（稀有度发光边框）"),
    ("11_hud_after_tutorial", "主界面：目标追踪 + 底部功能坞"),
    ("13_late_game_hud_currencies", "后期 HUD 与货币栏"),
    ("16_mobile_844x390_hud", "手机横屏：功能坞在伙伴与出战之间"),
    ("17_mobile_844x390_stages", "手机横屏：关卡选择"),
    ("18_mobile_390x844_hud", "手机竖屏：功能坞两行排布（新）"),
    ("19_mobile_390x844_stages", "手机竖屏：关卡选择自适应（新）"),
    ("20_mobile_390x844_hatch", "手机竖屏：孵蛋屋卡片换行（新）"),
]

COLS = 3
CELL_W, CELL_H, CAP_H, PAD, MARGIN = 600, 400, 40, 18, 24
HEADER_H = 110
BG = (34, 26, 18)
FG = (240, 220, 174)
GOLD = (232, 185, 90)
DIM = (227, 199, 155)

CJK = None
for p in (
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
):
    if os.path.exists(p):
        CJK = p
        break


def font(size):
    assert CJK, "NotoSansCJK not found"
    return ImageFont.truetype(CJK, size, index=0)


def load_snap(name):
    path = os.path.join(SNAP_DIR, name + ".png")
    im = Image.open(path).convert("RGB")
    # letterbox into the cell, preserving aspect
    s = min(CELL_W / im.width, CELL_H / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.NEAREST)
    cell = Image.new("RGB", (CELL_W, CELL_H), (24, 17, 11))
    cell.paste(im, ((CELL_W - im.width) // 2, (CELL_H - im.height) // 2))
    return cell


def main():
    rows = (len(PANELS) + COLS - 1) // COLS
    W = MARGIN * 2 + COLS * CELL_W + (COLS - 1) * PAD
    H = HEADER_H + rows * (CELL_H + CAP_H + PAD) + MARGIN
    page = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(page)
    title = f"Voxel Pets v{VERSION} — UI 预览（新像素风 + 竖屏适配）"
    sub = "暖木窗格 / 羊皮纸内衬 / 金色描边 · 关卡与孵蛋改为自适应流式布局 · 手机竖屏两行功能坞"
    d.text((MARGIN, 26), title, font=font(34), fill=GOLD)
    d.text((MARGIN, 72), sub, font=font(18), fill=DIM)
    for i, (name, caption) in enumerate(PANELS):
        r, c = divmod(i, COLS)
        x = MARGIN + c * (CELL_W + PAD)
        y = HEADER_H + r * (CELL_H + CAP_H + PAD)
        cell = load_snap(name)
        page.paste(cell, (x, y))
        d.rectangle([x - 2, y - 2, x + CELL_W + 1, y + CELL_H + 1], outline=(58, 36, 18), width=2)
        d.text((x + 4, y + CELL_H + 8), caption, font=font(20), fill=FG)
    page.save(OUT, optimize=True)
    print("overview ->", OUT, f"{page.width}x{page.height}")


if __name__ == "__main__":
    main()
