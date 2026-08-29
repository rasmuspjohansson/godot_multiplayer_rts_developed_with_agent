#!/usr/bin/env python3
"""Chroma-key neon green screen from vegetation PNGs (tree, spruce, bush, stone).

Uses a tight bright-green mask so darker tree foliage is preserved.
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ASSETS = [
    ROOT / "images/background/tree.png",
    ROOT / "images/background/tree_spruce.png",
    ROOT / "images/background/bush.png",
    ROOT / "images/background/stone.png",
]


def key_screen_green(bgr: np.ndarray) -> np.ndarray:
    b, g, r = cv2.split(bgr)
    bg = (g > 180) & (g > r * 1.8) & (g > b * 1.8) & (r < 100) & (b < 100)
    bg_mask = bg.astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    bg_mask = cv2.morphologyEx(bg_mask, cv2.MORPH_CLOSE, kernel, iterations=1)
    alpha = cv2.bitwise_not(bg_mask)
    alpha = cv2.GaussianBlur(alpha, (5, 5), 0)
    bgra = cv2.cvtColor(bgr, cv2.COLOR_BGR2BGRA)
    bgra[:, :, 3] = alpha
    return bgra


def main() -> int:
    for path in ASSETS:
        if not path.is_file():
            print(f"MISSING: {path}", file=sys.stderr)
            return 1
        bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if bgr is None:
            print(f"READ_FAIL: {path}", file=sys.stderr)
            return 1
        bgra = key_screen_green(bgr)
        cv2.imwrite(str(path), bgra)
        fg_pct = (bgra[:, :, 3] > 128).mean() * 100.0
        corners = [
            bgra[5, 5, 3],
            bgra[5, -6, 3],
            bgra[-6, 5, 3],
            bgra[-6, -6, 3],
        ]
        print(f"KEYED {path.name}: foreground={fg_pct:.1f}% corner_alpha={corners}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
