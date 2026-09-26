#!/usr/bin/env python3
"""Renders GUI dumps from tools/ui_snapshot.luau to PNG so layouts can be reviewed without Studio.

Approximates Roblox GUI layout: UDim2 size/position, AnchorPoint, UIPadding, UIListLayout,
UIGridLayout, UISizeConstraint, ScreenGui-level UIScale, AutomaticSize (text / lists), clipping
(ScrollingFrame, ClipsDescendants), ZIndex ordering between siblings, UIStroke outlines, text
alignment / wrapping / truncation with the Press Start 2P pixel font. Not rendered: 3D (sky and
ground are drawn as a backdrop), images, rich text.

Usage: python3 scripts/render_ui.py [dir-with-json] [--font PATH]
Font: tools/data/fonts/PressStart2P-Regular.ttf, /tmp/PressStart2P-Regular.ttf, or DejaVu Mono.
"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TOPBAR_INSET = 58
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIXEL_FONTS = [
    os.path.join(ROOT, "tools", "data", "fonts", "PressStart2P-Regular.ttf"),
    "/tmp/PressStart2P-Regular.ttf",
]
MONO_FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"]
GUI_CLASSES = {
    "Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ViewportFrame",
    "ImageLabel", "ImageButton", "CanvasGroup",
}
TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}

_font_cache = {}


FONT_URL = "https://github.com/google/fonts/raw/main/ofl/pressstart2p/PressStart2P-Regular.ttf"


def ensure_pixel_font():
    """Downloads Press Start 2P (SIL OFL) to /tmp once if no local copy exists."""
    if any(os.path.exists(p) for p in PIXEL_FONTS):
        return
    try:
        import urllib.request

        urllib.request.urlretrieve(FONT_URL, "/tmp/PressStart2P-Regular.ttf")
    except Exception as exc:  # offline: fall back to DejaVu Sans Mono
        print("pixel font unavailable (%s); using a monospace fallback" % exc)


def font(size, mono=False):
    size = max(4, int(round(size)))
    key = (size, mono)
    if key not in _font_cache:
        paths = (MONO_FONTS if mono else PIXEL_FONTS) + MONO_FONTS
        for p in paths:
            if os.path.exists(p):
                # Press Start 2P draws ~1 px per unit at size=TextSize
                _font_cache[key] = ImageFont.truetype(p, size)
                break
        else:
            _font_cache[key] = ImageFont.load_default()
    return _font_cache[key]


def rgb(c, alpha=1.0):
    c = c or [1, 1, 1]
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(max(0, min(1, alpha)) * 255))


def P(node, key, default=None):
    v = node["props"].get(key)
    return default if v is None else v


def child_of_class(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def is_gui(node):
    return node["class"] in GUI_CLASSES


def visible(node):
    return P(node, "Visible", True) is not False


# ------------------------------------------------------------------------------------ layout
def text_lines(node, width, scale):
    text = str(P(node, "Text", ""))
    if not text:
        return [], 0
    size = P(node, "TextSize", 14) * scale
    f = font(size, mono="Code" in str(P(node, "FontFace", "")))
    lines = []
    for para in text.split("\n"):
        if not P(node, "TextWrapped", False) or width <= 0:
            lines.append(para)
            continue
        words, cur = para.split(" "), ""
        for w in words:
            trial = (cur + " " + w) if cur else w
            if f.getlength(trial) <= width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    line_h = size * 1.2 * P(node, "LineHeight", 1)
    return lines, line_h


def base_size(node, pw, ph):
    s = P(node, "Size", [0, 0, 0, 0])
    w, h = s[0] * pw + s[1], s[2] * ph + s[3]
    lim = child_of_class(node, "UISizeConstraint")
    if lim:
        mx, mn = P(lim, "MaxSize", [1e9, 1e9]), P(lim, "MinSize", [0, 0])
        w, h = max(mn[0], min(mx[0], w)), max(mn[1], min(mx[1], h))
    return w, h


def padded(node, x, y, w, h):
    pad = child_of_class(node, "UIPadding")
    if not pad:
        return x, y, w, h

    def u(k, total):
        v = P(pad, k, [0, 0])
        return v[0] * total + v[1]

    l, r, t, b = u("PaddingLeft", w), u("PaddingRight", w), u("PaddingTop", h), u("PaddingBottom", h)
    return x + l, y + t, max(0, w - l - r), max(0, h - t - b)


def auto_size(node, w, h, scale):
    mode = P(node, "AutomaticSize", "None")
    if mode not in ("Y", "XY"):
        return w, h
    if node["class"] in TEXT_CLASSES:
        lines, lh = text_lines(node, w, scale)
        h = max(h, len(lines) * lh / scale + 4)
    lst = child_of_class(node, "UIListLayout")
    if not lst and node["class"] not in TEXT_CLASSES:
        kids = [c for c in node["children"] if is_gui(c) and visible(c)]
        cx, cy, cw, ch = padded(node, 0, 0, w, h)
        bottom = 0
        for c in kids:
            bw, bh = base_size(c, cw, ch)
            bw, bh = auto_size(c, bw, bh, scale)
            pos, anc = P(c, "Position", [0, 0, 0, 0]), P(c, "AnchorPoint", [0, 0])
            bottom = max(bottom, pos[2] * ch + pos[3] - anc[1] * bh + bh)
        h = max(h, bottom + (h - ch))
    if lst:
        kids = [c for c in node["children"] if is_gui(c) and visible(c)]
        pad = P(lst, "Padding", [0, 0])
        cx, cy, cw, ch = padded(node, 0, 0, w, h)
        total = 0
        for i, c in enumerate(kids):
            cw2, ch2 = base_size(c, cw, ch)
            cw2, ch2 = auto_size(c, cw2, ch2, scale)
            total += ch2 + (pad[0] * ch + pad[1] if i else 0)
        h = max(h, total + (h - ch))
    return w, h


def layout(node, rect, scale, out, clip, xf=(0.0, 0.0, 1.0)):
    """rect = (x, y, w, h) in the parent's local px; xf maps local -> root logical px
    (nested UIScale objects compose into xf); out collects (node, rootRect, clip, k)."""
    x, y, w, h = rect
    uis = child_of_class(node, "UIScale")
    if uis and P(uis, "Scale", 1) != 1:
        u = P(uis, "Scale", 1)
        anc = P(node, "AnchorPoint", [0, 0])
        ax, ay = x + anc[0] * w, y + anc[1] * h
        tx, ty, k = xf
        xf = (tx + ax * k * (1 - u), ty + ay * k * (1 - u), k * u)
    tx, ty, k = xf
    root_rect = (tx + x * k, ty + y * k, w * k, h * k)
    out.append((node, root_rect, clip, k))
    if node["class"] == "ScrollingFrame" or P(node, "ClipsDescendants", False):
        cx0, cy0, cx1, cy1 = clip
        rx, ry, rw, rh = root_rect
        clip = (max(cx0, rx), max(cy0, ry), min(cx1, rx + rw), min(cy1, ry + rh))
    cx, cy, cw, ch = padded(node, x, y, w, h)
    kids = [c for c in node["children"] if is_gui(c) and visible(c)]
    sizes = []
    for c in kids:
        bw, bh = base_size(c, cw, ch)
        sizes.append(auto_size(c, bw, bh, scale))
    lst, grid = child_of_class(node, "UIListLayout"), child_of_class(node, "UIGridLayout")
    if lst:
        order = sorted(range(len(kids)), key=lambda i: (P(kids[i], "LayoutOrder", 0), i))
        horiz = P(lst, "FillDirection", "Vertical") == "Horizontal"
        pad = P(lst, "Padding", [0, 0])
        gap = pad[0] * (cw if horiz else ch) + pad[1]
        total = sum(sizes[i][0 if horiz else 1] for i in order) + gap * max(0, len(order) - 1)
        ha, va = P(lst, "HorizontalAlignment", "Left"), P(lst, "VerticalAlignment", "Top")
        if horiz:
            px = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(ha, 0)
            for i in order:
                sw, sh = sizes[i]
                py = cy + {"Top": 0, "Center": (ch - sh) / 2, "Bottom": ch - sh}.get(va, 0)
                layout(kids[i], (px, py, sw, sh), scale, out, clip, xf)
                px += sw + gap
        else:
            py = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(va, 0)
            for i in order:
                sw, sh = sizes[i]
                px = cx + {"Left": 0, "Center": (cw - sw) / 2, "Right": cw - sw}.get(ha, 0)
                layout(kids[i], (px, py, sw, sh), scale, out, clip, xf)
                py += sh + gap
    elif grid:
        order = sorted(range(len(kids)), key=lambda i: (P(kids[i], "LayoutOrder", 0), i))
        cs, cp = P(grid, "CellSize", [0, 100, 0, 100]), P(grid, "CellPadding", [0, 5, 0, 5])
        gw, gh = cs[0] * cw + cs[1], cs[2] * ch + cs[3]
        px_, py_ = cp[0] * cw + cp[1], cp[2] * ch + cp[3]
        per_row = max(1, int((cw + px_) // (gw + px_)))
        for n, i in enumerate(order):
            r, c = divmod(n, per_row)
            layout(kids[i], (cx + c * (gw + px_), cy + r * (gh + py_), gw, gh), scale, out, clip, xf)
    else:
        for c, (sw, sh) in zip(kids, sizes):
            pos, anc = P(c, "Position", [0, 0, 0, 0]), P(c, "AnchorPoint", [0, 0])
            px = cx + pos[0] * cw + pos[1] - anc[0] * sw
            py = cy + pos[2] * ch + pos[3] - anc[1] * sh
            layout(c, (px, py, sw, sh), scale, out, clip, xf)


# ------------------------------------------------------------------------------------ drawing
def blend_rect(img, box, color):
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(img.width, x1), min(img.height, y1)
    if x1 <= x0 or y1 <= y0 or color[3] == 0:
        return
    region = img.crop((x0, y0, x1, y1))
    overlay = Image.new("RGBA", region.size, color)
    img.paste(Image.alpha_composite(region, overlay), (x0, y0))


def draw_node(img, node, rect, clip, origin, scale, k=1.0):
    ts = scale * k  # text / stroke scale (nested UIScale); positions already include k
    ox, oy = origin
    x, y, w, h = rect
    X0, Y0, X1, Y1 = ox + x * scale, oy + y * scale, ox + (x + w) * scale, oy + (y + h) * scale
    cx0, cy0, cx1, cy1 = [ox + clip[0] * scale, oy + clip[1] * scale, ox + clip[2] * scale, oy + clip[3] * scale]
    box = (max(X0, cx0), max(Y0, cy0), min(X1, cx1), min(Y1, cy1))
    if box[2] <= box[0] or box[3] <= box[1]:
        return
    bt = P(node, "BackgroundTransparency", 0)
    if bt < 1:
        blend_rect(img, box, rgb(P(node, "BackgroundColor3"), 1 - bt))
    if node["class"] == "ViewportFrame":
        d = ImageDraw.Draw(img)
        d.text(((X0 + X1) / 2, (Y0 + Y1) / 2), "3D", fill=(120, 130, 160, 255), font=font(10 * ts), anchor="mm")
    stroke = child_of_class(node, "UIStroke")
    if stroke and P(stroke, "Transparency", 0) < 1:
        t = max(1, int(round(P(stroke, "Thickness", 1) * ts)))
        col = rgb(P(stroke, "Color", [0, 0, 0]), 1 - P(stroke, "Transparency", 0))
        for i in range(t):
            for b in (
                (X0 - i - 1, Y0 - i - 1, X1 + i + 1, Y0 - i),
                (X0 - i - 1, Y1 + i, X1 + i + 1, Y1 + i + 1),
                (X0 - i - 1, Y0 - i - 1, X0 - i, Y1 + i + 1),
                (X1 + i, Y0 - i - 1, X1 + i + 1, Y1 + i + 1),
            ):
                blend_rect(img, (max(b[0], cx0 - t), max(b[1], cy0 - t), min(b[2], cx1 + t), min(b[3], cy1 + t)), col)
    if node["class"] in TEXT_CLASSES and str(P(node, "Text", "")):
        tt = P(node, "TextTransparency", 0)
        if tt >= 1:
            return
        lines, lh = text_lines(node, w * scale, ts)
        size = P(node, "TextSize", 14) * ts
        f = font(size, mono="Code" in str(P(node, "FontFace", "")))
        total = len(lines) * lh
        ya = P(node, "TextYAlignment", "Center")
        ty = {"Top": Y0, "Center": (Y0 + Y1 - total) / 2, "Bottom": Y1 - total}.get(ya, Y0)
        if P(node, "TextTruncate", "None") == "AtEnd" and total > (Y1 - Y0) + 1:
            keep = max(1, int((Y1 - Y0) // lh))
            lines = lines[:keep]
            lines[-1] = lines[-1][: max(0, len(lines[-1]) - 3)] + "..."
            ty = {"Top": Y0, "Center": (Y0 + Y1 - keep * lh) / 2, "Bottom": Y1 - keep * lh}.get(ya, Y0)
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        color = rgb(P(node, "TextColor3", [0, 0, 0]), 1 - tt)
        stroke_w = 1 if P(node, "TextStrokeTransparency", 1) < 1 else 0
        stroke_c = rgb(P(node, "TextStrokeColor3", [0, 0, 0]), 1 - P(node, "TextStrokeTransparency", 1))
        xa = P(node, "TextXAlignment", "Center")
        for i, line in enumerate(lines):
            lw = f.getlength(line)
            if P(node, "TextTruncate", "None") == "AtEnd" and lw > (X1 - X0) and line:
                while line and f.getlength(line + "...") > (X1 - X0):
                    line = line[:-1]
                line += "..."
                lw = f.getlength(line)
            tx = {"Left": X0, "Center": (X0 + X1 - lw) / 2, "Right": X1 - lw}.get(xa, X0)
            d.text((tx, ty + i * lh + (lh - size) / 2), line, fill=color, font=f,
                   stroke_width=stroke_w, stroke_fill=stroke_c)
        # clip text to the node's clip box (text may spill out of its own box, like Roblox)
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle([cx0, cy0, cx1, cy1], fill=255)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
        img.alpha_composite(layer)


def draw_tree(img, node, items_by_id, origin, scale):
    for entry in items_by_id.get(id(node), []):
        _, rect, clip, k = entry
        draw_node(img, node, rect, clip, origin, scale, k)
    kids = [c for c in node["children"] if is_gui(c) and visible(c)]
    kids = sorted(enumerate(kids), key=lambda t: (P(t[1], "ZIndex", 1), t[0]))
    for _, c in kids:
        draw_tree(img, c, items_by_id, origin, scale)


def backdrop(img, W, H):
    d = ImageDraw.Draw(img)
    for yy in range(H):
        t = yy / H
        if t < 0.42:
            c = (int(120 + 60 * t), int(190 + 40 * t), 245, 255)
        else:
            c = (96, 168, 78, 255) if ((yy // 40) % 2) else (84, 150, 68, 255)
        d.line([(0, yy), (W, yy)], fill=c)
    # Roblox top bar buttons (inset area)
    d.rounded_rectangle([14, 12, 58, 56], radius=22, fill=(24, 26, 34, 235))
    d.rounded_rectangle([66, 12, 166, 56], radius=22, fill=(24, 26, 34, 235))


def placement(x, y, w, h, W, H):
    """Mirror of Highlight.placement() in src/client/UI/Highlight.luau."""
    cy = y + h / 2
    if x + w < W * 0.22 and cy < H * 0.8:
        return "right"
    if cy > H * 0.55:
        return "above"
    if y + h + 46 + 50 < H:
        return "below"
    return "above"


def draw_pointer(img, rect, text):
    x, y, w, h = rect
    W, H = img.size
    d = ImageDraw.Draw(img)
    for i in range(4):
        d.rectangle([x - 6 - i, y - 6 - i, x + w + 6 + i, y + h + 6 + i], outline=(255, 200, 60, 255))
    bw, bh = 300, 46
    cx, cy = x + w / 2, y + h / 2
    mode = placement(x, y, w, h, W, H)
    max_x = max(8, W - bw - 8)
    if mode == "right":
        bx, by = x + w + 44, cy - bh / 2
        tri = [(x + w + 10, cy), (x + w + 36, cy - 14), (x + w + 36, cy + 14)]
    elif mode == "above":
        bx, by = min(max(cx - bw / 2, 8), max_x), y - bh - 40
        tri = [(cx, y - 8), (cx - 14, y - 34), (cx + 14, y - 34)]
    else:
        bx, by = min(max(cx - bw / 2, 8), max_x), y + h + 40
        tri = [(cx, y + h + 8), (cx - 14, y + h + 34), (cx + 14, y + h + 34)]
    d.polygon(tri, fill=(255, 200, 60, 255), outline=(12, 12, 20, 255))
    d.rectangle([bx, by, bx + bw, by + bh], fill=(255, 200, 60, 255), outline=(12, 12, 20, 255), width=3)
    f = font(10)
    lines, cur = [], ""
    for word in text.split(" "):
        trial = (cur + " " + word) if cur else word
        if f.getlength(trial) <= bw - 16 or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    ty = by + (bh - len(lines) * 13) / 2
    for i, line in enumerate(lines):
        d.text((bx + bw / 2, ty + i * 13 + 6), line, fill=(24, 26, 40, 255), font=f, anchor="mm")


def render(path):
    dump = json.load(open(path))
    W, H = dump["viewport"]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    backdrop(img, W, H)
    guis = sorted(enumerate(dump["guis"]), key=lambda t: (P(t[1], "DisplayOrder", 0), t[0]))
    screen_rects = {}  # node name -> first visible screen-space rect
    pointer = dump.get("highlight")
    for _, g in guis:
        if P(g, "Enabled", True) is False:
            continue
        if g["name"] == "VoxelPetsTutorial":
            if pointer and pointer["target"] in screen_rects:
                draw_pointer(img, screen_rects[pointer["target"]], pointer.get("text") or "")
            continue
        full = P(g, "ScreenInsets", "") == "None" or P(g, "IgnoreGuiInset", False) is True
        top = 0 if full else TOPBAR_INSET
        uis = child_of_class(g, "UIScale")
        s = P(uis, "Scale", 1) if uis else 1
        lw, lh = W / s, (H - top) / s
        out = []
        kids = [c for c in g["children"] if is_gui(c) and visible(c)]
        for c in kids:
            bw, bh = base_size(c, lw, lh)
            bw, bh = auto_size(c, bw, bh, s)
            pos, anc = P(c, "Position", [0, 0, 0, 0]), P(c, "AnchorPoint", [0, 0])
            layout(c, (pos[0] * lw + pos[1] - anc[0] * bw, pos[2] * lh + pos[3] - anc[1] * bh, bw, bh),
                   s, out, (0, 0, lw, lh))
        items = {}
        for node, rect, clip, k in out:
            items.setdefault(id(node), []).append((node, rect, clip, k))
            nm = node.get("name")
            if nm and nm not in screen_rects:
                rx, ry, rw, rh = rect
                screen_rects[nm] = (rx * s, top + ry * s, rw * s, rh * s)
        for _, c in sorted(enumerate(kids), key=lambda t: (P(t[1], "ZIndex", 1), t[0])):
            draw_tree(img, c, items, (0, top), s)
    png = os.path.splitext(path)[0] + ".png"
    img.convert("RGB").save(png)
    return png


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--font" in sys.argv:
        PIXEL_FONTS.insert(0, sys.argv[sys.argv.index("--font") + 1])
    folder = args[0] if args else "/tmp/ui_snapshots"
    ensure_pixel_font()
    files = sorted(glob.glob(os.path.join(folder, "*.json")))
    for f in files:
        print("rendered", render(f))
    if not files:
        print("no snapshots in", folder)


if __name__ == "__main__":
    main()
