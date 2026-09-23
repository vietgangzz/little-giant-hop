#!/usr/bin/env python3
"""Draws the 1024px app icon from the brand vectors (needs Pillow).

    python3 tools/make_icon.py LittleGiantHop/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import re
import sys

from PIL import Image, ImageDraw, ImageFilter

BODY = "M706 313.5L705 268L711 268.5Q717 269 729.5 272.5Q742 276 757 284Q772 292 784.5 304Q797 316 804.5 329Q812 342 816.5 360.5Q821 379 821 410Q821 441 823.5 455.5Q826 470 831.5 483Q837 496 848 512Q859 528 862.5 535.5Q866 543 867.5 549Q869 555 869 568Q869 581 865.5 591Q862 601 855 611Q848 621 841.5 627Q835 633 827.5 638Q820 643 800.5 651Q781 659 754 665.5Q727 672 691 676.5Q655 681 620 681.5Q585 682 562.5 679.5Q540 677 527 674Q514 671 506.5 668Q499 665 494 663.5Q489 662 478.5 656.5Q468 651 461.5 646.5Q455 642 446.5 634Q438 626 430 614.5Q422 603 416 587.5Q410 572 408 560Q406 548 406 531.5Q406 515 407 507.5Q408 500 413.5 480Q419 460 426.5 443.5Q434 427 443 412.5Q452 398 461.5 386Q471 374 482 362.5Q493 351 506.5 339.5Q520 328 534.5 318Q549 308 565.5 299Q582 290 594 285Q606 280 621.5 275.5Q637 271 639 271.5Q641 272 653 287.5Q665 303 682 328.5Q699 354 701.5 356.5Q704 359 705.5 359L707 359L706 313.5Z"
EYES = [
    "M557.5 419.5L559 415.5L562 416Q565 416.5 614 448L663 479.5L662 486Q661 492.5 656.5 501Q652 509.5 649 512Q646 514.5 643.5 517.5Q641 520.5 635.5 523.5Q630 526.5 623 527.5Q616 528.5 606.5 525.5Q597 522.5 588.5 515Q580 507.5 573 496Q566 484.5 562.5 474.5Q559 464.5 557.5 456.5Q556 448.5 556 436Q556 423.5 557.5 419.5Z",
    "M755.5 455.5L783 433L785 434L787 435L787.5 437Q788 439 789 453.5Q790 468 788.5 476Q787 484 784.5 490.5Q782 497 776.5 504Q771 511 767 513Q763 515 757 515Q751 515 747.5 513.5Q744 512 743 510.5Q742 509 739 506.5Q736 504 733.5 499.5Q731 495 729.5 490.5Q728 486 728 482L728 478L755.5 455.5Z",
]
RAYS = [
    "M872 211Q875 209 879.5 210Q884 211 896.5 219.5Q909 228 911.5 230.5Q914 233 914 236.5Q914 240 888.5 267.5Q863 295 859.5 299Q856 303 853 303.5Q850 304 843 299Q836 294 834.5 291L833 288L851 250.5Q869 213 872 211Z",
    "M922 290Q941 280 944.5 281Q948 282 949.5 284Q951 286 957 302Q963 318 962.5 321.5L962 325L957.5 327.5Q953 330 920 338Q887 346 882 347L877 348L874.5 346Q872 344 869.5 337Q867 330 867.5 326L868 322L885.5 311Q903 300 922 290Z",
    "M877.5 374L880 372L912 377.5L944 383L945 387Q946 391 942.5 403.5Q939 416 937.5 417.5Q936 419 931 419Q926 419 900 408Q874 397 872.5 393.5Q871 390 873 383Q875 376 877.5 374Z",
]

S = 4  # supersample
N = 1024 * S


def flatten(d, tf):
    toks = re.findall(r"[MLQZ]|-?\d*\.?\d+", d)
    pts, i, cur, cmd = [], 0, (0, 0), "M"
    while i < len(toks):
        if toks[i] in "MLQZ":
            cmd = toks[i]
            i += 1
            if cmd == "Z":
                continue
        if cmd in "ML":
            cur = (float(toks[i]), float(toks[i + 1]))
            i += 2
            pts.append(cur)
        elif cmd == "Q":
            c = (float(toks[i]), float(toks[i + 1]))
            p = (float(toks[i + 2]), float(toks[i + 3]))
            i += 4
            for k in range(1, 9):
                t = k / 8
                pts.append(((1 - t) ** 2 * cur[0] + 2 * (1 - t) * t * c[0] + t * t * p[0],
                            (1 - t) ** 2 * cur[1] + 2 * (1 - t) * t * c[1] + t * t * p[1]))
            cur = p
    return [tf(p) for p in pts]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def main(out):
    img = Image.new("RGBA", (N, N), (10, 10, 10, 255))
    d = ImageDraw.Draw(img)

    # Sky gradient.
    top, horizon = (8, 9, 12), (40, 46, 22)
    for y in range(N):
        d.line([(0, y), (N, y)], fill=lerp(top, horizon, (y / N) ** 1.6))

    # Retro sun with slits.
    cx, cy, r = N * 0.5, N * 0.6, N * 0.33
    halo = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([cx - r * 1.3, cy - r * 1.3, cx + r * 1.3, cy + r * 1.3], fill=(255, 116, 71, 90))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(60 * S)))
    sun = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sun)
    stops = [(0, (213, 246, 75)), (0.4, (255, 201, 74)), (0.72, (255, 116, 71)), (1, (209, 84, 34))]
    for y in range(int(cy - r), int(cy + r)):
        t = (y - (cy - r)) / (2 * r)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                sd.line([(0, y), (N, y)], fill=lerp(c0, c1, (t - t0) / (t1 - t0)) + (255,))
    mask = Image.new("L", (N, N), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    y, gap = cy + r * 0.1, r * 0.035
    while y < cy + r:
        md.rectangle([0, y, N, y + gap], fill=0)
        y += gap + r * 0.11
        gap *= 1.35
    img.paste(sun, (0, 0), mask)

    # Floor.
    fy = N * 0.8
    d.rectangle([0, fy, N, N], fill=(8, 9, 8))
    d.line([(0, fy), (N, fy)], fill=(213, 246, 75), width=3 * S)
    for i in range(-12, 13):
        x_far = N / 2 + i * N * 0.05
        x_near = N / 2 + i * N * 0.2
        d.line([(x_far, fy), (x_near, N)], fill=(213, 246, 75, 90), width=S * 2)
    for k in range(1, 5):
        yy = fy + (N - fy) * (k / 4) ** 2
        d.line([(0, yy), (N, yy)], fill=(213, 246, 75, 90), width=S * 2)

    # Mascot, centred.
    scale = N * 0.00125
    ox, oy = 637, 470

    def tf(p):
        return (N * 0.47 + (p[0] - ox) * scale, N * 0.47 + (p[1] - oy) * scale)

    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(flatten(BODY, tf), fill=(213, 246, 75, 150))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40 * S)))

    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 18 * S, y + 18 * S) for x, y in flatten(BODY, tf)], fill=(10, 10, 10, 255))
    img.alpha_composite(shadow)

    d = ImageDraw.Draw(img)
    d.polygon(flatten(BODY, tf), fill=(213, 246, 75))
    for e in EYES:
        d.polygon(flatten(e, tf), fill=(10, 10, 10))
    for ray in RAYS:
        d.polygon(flatten(ray, tf), fill=(255, 116, 71))

    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png")
