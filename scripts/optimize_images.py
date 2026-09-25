#!/usr/bin/env python3
"""把 docs/concept-art 下的大图压缩为 ≤1600px 的 JPG（质量 88），源 PNG 删除，避免仓库膨胀。"""
import sys, pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent / "docs" / "concept-art"
for png in sorted(root.glob("*.png")):
    img = Image.open(png).convert("RGB")
    w, h = img.size
    scale = min(1.0, 1600 / max(w, h))
    if scale < 1.0:
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    out = png.with_suffix(".jpg")
    img.save(out, "JPEG", quality=88, optimize=True)
    png.unlink()
    print(f"{png.name} -> {out.name}  {out.stat().st_size/1024:.0f} KB")
