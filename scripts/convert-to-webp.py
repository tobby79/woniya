import os
import sys
from PIL import Image

SCRATCH = "C:/Users/user/AppData/Local/Temp/claude/e--------woniya/e0681588-3c2f-4f43-b52f-93ce46565396/scratchpad"
SRC_DIR = os.path.join(SCRATCH, "originals")
DST_DIR = os.path.join(SCRATCH, "webp")

QUALITY = 82
METHOD = 6

results = []

for root, dirs, files in os.walk(SRC_DIR):
    for name in files:
        if not name.lower().endswith((".jpg", ".jpeg")):
            continue
        src_path = os.path.join(root, name)
        rel = os.path.relpath(src_path, SRC_DIR)
        rel_webp = os.path.splitext(rel)[0] + ".webp"
        dst_path = os.path.join(DST_DIR, rel_webp)
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)

        img = Image.open(src_path)
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        img.save(dst_path, "WEBP", quality=QUALITY, method=METHOD)

        orig_size = os.path.getsize(src_path)
        new_size = os.path.getsize(dst_path)
        results.append((rel, orig_size, new_size))

total_orig = sum(r[1] for r in results)
total_new = sum(r[2] for r in results)

print(f"{'file':<45} {'orig(KB)':>10} {'webp(KB)':>10} {'reduction':>10}")
for rel, orig, new in sorted(results):
    print(f"{rel:<45} {orig/1024:>10.1f} {new/1024:>10.1f} {(1-new/orig)*100:>9.1f}%")

print()
print(f"TOTAL: {total_orig/1024/1024:.2f} MB -> {total_new/1024/1024:.2f} MB  ({(1-total_new/total_orig)*100:.1f}% reduction)")
print(f"Files converted: {len(results)}")
