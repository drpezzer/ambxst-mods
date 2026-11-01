#!/usr/bin/env python3
"""Ambxst Skwd-wall Pre-caching Service

Pre-scales and optimizes wallpapers to primary screen resolution (1080p baseline JPEG)
so that Vulkan texture creation and transition initiation are instantaneous and zero-flash.
"""
import sys
import os
import json
import time
import hashlib
import subprocess
from concurrent.futures import ProcessPoolExecutor

HOME = os.path.expanduser("~")
AMBXST_CACHE = os.path.join(HOME, ".cache/ambxst")
BASE_CACHE_DIR = os.path.join(HOME, ".cache/skwd-wall-opt")
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


def detect_resolution():
    """Detects primary monitor resolution or defaults to 1920x1080."""
    try:
        out = subprocess.check_output(["hyprctl", "monitors", "-j"], stderr=subprocess.DEVNULL)
        monitors = json.loads(out.decode("utf-8"))
        if monitors and isinstance(monitors, list):
            focused = next((m for m in monitors if m.get("focused")), monitors[0])
            w = focused.get("width")
            h = focused.get("height")
            if w and h:
                return int(w), int(h)
    except Exception:
        pass
    return 1920, 1080


def get_wallpaper_dir():
    """Gets wallpaper directory from Ambxst cache or fallback."""
    try:
        cfg_path = os.path.join(AMBXST_CACHE, "wallpapers.json")
        if os.path.exists(cfg_path):
            with open(cfg_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                p = data.get("wallPath")
                if p and os.path.isdir(os.path.expanduser(p)):
                    return os.path.expanduser(p)
    except Exception:
        pass
    default_p = os.path.join(HOME, "Pictures/Wallpapers")
    return default_p if os.path.isdir(default_p) else HOME


def get_cache_dir(target_w, target_h):
    return os.path.join(BASE_CACHE_DIR, f"{target_w}x{target_h}")


def get_cache_path(src_path, target_w, target_h):
    abs_path = os.path.abspath(src_path)
    ext = os.path.splitext(abs_path)[1].lower()
    if ext not in IMAGE_EXTS:
        return src_path
    h = hashlib.sha256(abs_path.encode()).hexdigest()[:16]
    base = os.path.splitext(os.path.basename(abs_path))[0]
    return os.path.join(get_cache_dir(target_w, target_h), f"{h}_{base}.jpg")


def optimize_file_worker(args):
    try:
        os.nice(15)
    except Exception:
        pass
    src_path, target_w, target_h = args
    try:
        dest_path = get_cache_path(src_path, target_w, target_h)
        if dest_path == src_path:
            return dest_path

        if os.path.exists(dest_path):
            if os.path.getmtime(dest_path) >= os.path.getmtime(src_path):
                return dest_path

        cache_dir = get_cache_dir(target_w, target_h)
        os.makedirs(cache_dir, exist_ok=True)
        tmp_dest = dest_path + f".tmp.{os.getpid()}"

        if HAS_PIL:
            with Image.open(src_path) as img:
                if img.mode != "RGB":
                    img = img.convert("RGB")
                w, h = img.size
                if w == target_w and h == target_h:
                    cropped = img
                else:
                    scale = max(target_w / w, target_h / h)
                    nw, nh = int(round(w * scale)), int(round(h * scale))
                    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
                    left = (nw - target_w) // 2
                    top = (nh - target_h) // 2
                    cropped = resized.crop((left, top, left + target_w, top + target_h))
                cropped.save(tmp_dest, "JPEG", quality=95, progressive=False, optimize=False)
        else:
            # Fallback to ImageMagick
            cmd = [
                "magick", src_path + "[0]",
                "-resize", f"{target_w}x{target_h}^",
                "-gravity", "center",
                "-extent", f"{target_w}x{target_h}",
                "-colorspace", "sRGB",
                "-quality", "95",
                tmp_dest
            ]
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        os.replace(tmp_dest, dest_path)
        return dest_path
    except Exception:
        return src_path


def get_cache_stats(target_w, target_h, wall_dir):
    cache_dir = get_cache_dir(target_w, target_h)
    all_files = []
    if os.path.isdir(wall_dir):
        for root, _, filenames in os.walk(wall_dir):
            for fn in filenames:
                ext = os.path.splitext(fn)[1].lower()
                if ext in IMAGE_EXTS:
                    all_files.append(os.path.join(root, fn))

    total = len(all_files)
    cached_count = 0
    size_bytes = 0
    if os.path.isdir(cache_dir):
        for root, _, filenames in os.walk(cache_dir):
            for fn in filenames:
                if fn.endswith(".jpg"):
                    p = os.path.join(root, fn)
                    size_bytes += os.path.getsize(p)
                    cached_count += 1

    size_mb = round(size_bytes / (1024 * 1024), 1)
    return total, min(cached_count, total), size_mb


def main():
    target_w, target_h = detect_resolution()
    wall_dir = get_wallpaper_dir()
    max_cores = max(1, os.cpu_count() or 4)
    threads = min(4, max_cores)

    # Parse args
    args = sys.argv[1:]
    idx = 0
    mode = "status"
    get_file = None

    while idx < len(args):
        arg = args[idx]
        if arg == "--all":
            mode = "all"
        elif arg == "--status":
            mode = "status"
        elif arg == "--clear":
            mode = "clear"
        elif arg in ("--threads", "-j") and idx + 1 < len(args):
            try:
                threads = max(1, min(max_cores, int(args[idx + 1])))
            except ValueError:
                pass
            idx += 1
        elif arg == "--get" and idx + 1 < len(args):
            mode = "get"
            get_file = args[idx + 1]
            idx += 1
        elif arg == "--resolution" and idx + 1 < len(args):
            res_str = args[idx + 1]
            if "x" in res_str:
                parts = res_str.split("x")
                target_w, target_h = int(parts[0]), int(parts[1])
            idx += 1
        elif arg == "--dir" and idx + 1 < len(args):
            wall_dir = os.path.expanduser(args[idx + 1])
            idx += 1
        idx += 1

    if mode == "status":
        total, cached, size_mb = get_cache_stats(target_w, target_h, wall_dir)
        pct = int(round((cached / total * 100))) if total > 0 else 100
        print(f"STATUS {cached} {total} {size_mb} {pct} {max_cores}")
        return

    if mode == "clear":
        cache_dir = get_cache_dir(target_w, target_h)
        if os.path.isdir(cache_dir):
            import shutil
            shutil.rmtree(cache_dir)
        print(f"STATUS 0 0 0.0 0 {max_cores}")
        return

    if mode == "get":
        if get_file:
            print(optimize_file_worker((get_file, target_w, target_h)))
        return

    if mode == "all":
        all_files = []
        if os.path.isdir(wall_dir):
            for root, _, filenames in os.walk(wall_dir):
                for fn in filenames:
                    ext = os.path.splitext(fn)[1].lower()
                    if ext in IMAGE_EXTS:
                        all_files.append(os.path.join(root, fn))

        total = len(all_files)
        if total == 0:
            print(f"DONE 0 0.0")
            return

        worker_args = [(f, target_w, target_h) for f in all_files]
        workers = max(1, min(threads, max_cores))

        done_count = 0
        last_reported_pct = -1

        with ProcessPoolExecutor(max_workers=workers) as executor:
            for _ in executor.map(optimize_file_worker, worker_args, chunksize=8):
                done_count += 1
                pct = int(done_count * 100 / total)
                if pct != last_reported_pct or done_count == total:
                    last_reported_pct = pct
                    print(f"PROGRESS {done_count} {total} {pct}", flush=True)

        _, cached, size_mb = get_cache_stats(target_w, target_h, wall_dir)
        print(f"DONE {cached} {size_mb}", flush=True)


if __name__ == "__main__":
    main()
