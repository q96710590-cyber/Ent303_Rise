#!/usr/bin/env python3
"""构建期处理开屏动画素材。

输入（Resources/）：
    pet.gif         开屏动画
    island.png      绿色平台
    cat_final.png   动画结束后的静态猫

输出（Resources/intro/）：
    f_000.png ...            逐帧（已合成为完整画布）
    meta.json                画布尺寸、每帧延时、猫的尾帧包围盒、相位帧号、平台表面高度
    island.png               裁切后的平台
    cat.png                  裁切后的静态猫
"""

import json
import os
import sys

from PIL import Image, ImageSequence

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
OUT = os.path.join(RES, "intro")


def ensure_dir(p):
    os.makedirs(p, exist_ok=True)


def trim(im):
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def main():
    gif = os.path.join(RES, "pet.gif")
    if not os.path.exists(gif):
        print("跳过：没有 Resources/pet.gif")
        return

    ensure_dir(OUT)

    # 清掉旧帧，避免换 GIF 后残留
    for f in os.listdir(OUT):
        if f.startswith("f_") and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))

    im = Image.open(gif)
    W, H = im.size
    frames, delays = [], []
    for i, fr in enumerate(ImageSequence.Iterator(im)):
        im.seek(i)
        rgba = fr.convert("RGBA")
        path = os.path.join(OUT, f"f_{i:03d}.png")
        rgba.save(path)
        frames.append(rgba)
        delays.append(int(im.info.get("duration", 80)))

    bboxes = [f.getbbox() for f in frames]

    # 相位 1：字母开始下沉 —— 内容顶边明显下移
    base_top = bboxes[0][1]
    sink = 0
    for i, b in enumerate(bboxes):
        if b[1] > base_top + 8:
            sink = i
            break

    # 相位 2：凝结完成 —— 从尾部往前找，包围盒不再变化的那一帧
    final_bbox = bboxes[-1]
    condense = len(frames) - 1
    for i in range(len(frames) - 1, -1, -1):
        if abs(bboxes[i][1] - final_bbox[1]) > 8:
            break
        condense = i

    cat_box = final_bbox  # (l, t, r, b)

    # 平台：裁切 + 采样 x=0.30 处的顶面高度（归一化）
    island_surface = 0.45
    island_path = os.path.join(RES, "island.png")
    if os.path.exists(island_path):
        island = trim(Image.open(island_path).convert("RGBA"))
        island.save(os.path.join(OUT, "island.png"))
        alpha = island.split()[-1]
        probe_x = int(island.width * 0.30)
        probe_x = min(max(probe_x, 0), island.width - 1)
        for y in range(island.height):
            if alpha.getpixel((probe_x, y)) > 40:
                island_surface = y / island.height
                break

    # 静态猫
    cat_path = os.path.join(RES, "cat_final.png")
    if os.path.exists(cat_path):
        cat = trim(Image.open(cat_path).convert("RGBA"))
        cat.save(os.path.join(OUT, "cat.png"))

    first_center = (bboxes[0][0] + bboxes[0][2]) / 2.0
    meta = {
        "canvas": [W, H],
        "firstCenterX": round(first_center, 2),
        "frameCount": len(frames),
        "delays": delays,
        "sinkFrame": sink,
        "condenseFrame": condense,
        "catBox": list(cat_box),
        "islandSurface": round(island_surface, 4),
    }
    with open(os.path.join(OUT, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)

    print(f"帧数 {len(frames)}, 画布 {W}x{H}")
    print(f"下沉帧 {sink}, 凝结帧 {condense}/{len(frames)-1}")
    print(f"尾帧猫包围盒 {cat_box}")
    print(f"平台表面高度 {island_surface:.3f}")
    total = sum(delays) / 1000.0
    print(f"总时长 {total:.2f}s")


if __name__ == "__main__":
    sys.exit(main())
