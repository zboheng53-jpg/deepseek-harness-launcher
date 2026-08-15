import os
import subprocess
import sys
from pathlib import Path
from PIL import Image

def build_icon():
    root = Path(__file__).parent.parent.resolve()
    assets_dir = root / "assets"
    html_file = assets_dir / "icon_render.html"
    png_file = assets_dir / "app.png"
    ico_file = assets_dir / "app.ico"

    edge_paths = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ]
    browser_exe = None
    for p in edge_paths:
        if os.path.exists(p):
            browser_exe = p
            break

    if not browser_exe:
        print("Warning: Edge/Chrome executable not found, searching in PATH...")
        browser_exe = "msedge.exe"

    print(f"Using browser: {browser_exe}")
    cmd = [
        browser_exe,
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--default-background-color=00000000",
        "--window-size=512,512",
        f"--screenshot={png_file}",
        f"file:///{html_file.as_posix()}"
    ]
    print("Rendering SVG to PNG...")
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not png_file.exists():
        raise FileNotFoundError(f"Failed to generate {png_file}")

    print(f"Converting PNG to multi-resolution ICO: {ico_file}")
    img = Image.open(png_file)
    # Windows icon sizes
    icon_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(ico_file, format='ICO', sizes=icon_sizes)

    print("Icon build successful!")
    print(f"PNG: {png_file} ({png_file.stat().st_size} bytes)")
    print(f"ICO: {ico_file} ({ico_file.stat().st_size} bytes)")

if __name__ == "__main__":
    build_icon()
