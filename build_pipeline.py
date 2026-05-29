import os
import subprocess
import shutil

# --- CONFIGURATION ---
GODOT_EXE = r""

# --- PATH SETUP ---
ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
GODOT_PROJECT_DIR = os.path.join(ROOT_DIR, "godot")
BUILD_DIR = os.path.join(ROOT_DIR, "Builds")

GAME_NAME = "ExviusReborn"

# Exact preset names from godot/export_presets.cfg
WIN_PRESET_NAME = "Windows Desktop"
ANDROID_APK_PRESET_NAME = "Android"
ANDROID_PCK_PRESET_NAME = "Android Assets PCK"


def run_godot_export(preset_name, output_path, pack_only=False):
    print(f"--> Exporting '{preset_name}' -> {output_path}")
    # --export-pack writes only the .pck (used by the assets-only preset).
    # --export-debug writes the runnable artifact for the platform.
    flag = "--export-pack" if pack_only else "--export-debug"
    command = [
        GODOT_EXE,
        "--headless",
        flag,
        preset_name,
        output_path,
    ]
    subprocess.run(command, cwd=GODOT_PROJECT_DIR, check=True)
    print(f"--> Finished '{preset_name}'.")


def zip_file(src_file, zip_base_path):
    """Create <zip_base_path>.zip containing just src_file at the archive root."""
    zip_path = zip_base_path + ".zip"
    if os.path.exists(zip_path):
        os.remove(zip_path)

    staging = zip_base_path + "_zipstaging"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(staging, exist_ok=True)
    try:
        shutil.copy(src_file, os.path.join(staging, os.path.basename(src_file)))
        shutil.make_archive(zip_base_path, "zip", staging)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    print(f"--> Zipped: {zip_path}")


def zip_dir(src_dir, zip_base_path):
    zip_path = zip_base_path + ".zip"
    if os.path.exists(zip_path):
        os.remove(zip_path)
    shutil.make_archive(zip_base_path, "zip", src_dir)
    print(f"--> Zipped: {zip_path}")


def build_windows():
    print("\n=== Windows ===")
    win_dir = os.path.join(BUILD_DIR, "Windows")
    if os.path.exists(win_dir):
        shutil.rmtree(win_dir)
    os.makedirs(win_dir, exist_ok=True)

    exe_path = os.path.join(win_dir, f"{GAME_NAME}.exe")
    run_godot_export(WIN_PRESET_NAME, exe_path)

    zip_dir(win_dir, os.path.join(BUILD_DIR, f"{GAME_NAME}_Windows"))


def build_android():
    print("\n=== Android APK ===")
    apk_path = os.path.join(BUILD_DIR, f"{GAME_NAME}.apk")
    run_godot_export(ANDROID_APK_PRESET_NAME, apk_path)
    zip_file(apk_path, os.path.join(BUILD_DIR, f"{GAME_NAME}_Android_APK"))

    print("\n=== Android Assets PCK ===")
    pck_path = os.path.join(BUILD_DIR, "assets.pck")
    run_godot_export(ANDROID_PCK_PRESET_NAME, pck_path, pack_only=True)
    zip_file(pck_path, os.path.join(BUILD_DIR, f"{GAME_NAME}_Android_PCK"))


if __name__ == "__main__":
    print("=== Starting Build Pipeline ===")
    os.makedirs(BUILD_DIR, exist_ok=True)

    build_windows()
    build_android()

    print("\n=== Pipeline Complete! ===")
