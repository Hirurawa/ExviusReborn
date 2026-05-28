import os
import subprocess
import shutil
import json

# --- CONFIGURATION ---
# Update this to the actual path of your Godot executable
GODOT_EXE = r""

# --- PATH SETUP ---
# 1. Get the directory where this python script actually lives (Project Root)
ROOT_DIR = os.path.dirname(os.path.abspath(__file__))

# 2. Define the subdirectories
GODOT_PROJECT_DIR = os.path.join(ROOT_DIR, "godot")
BUILD_DIR = os.path.join(ROOT_DIR, "Builds")

# Your project details
GAME_NAME = "ExviusReborn"
PACKAGE_NAME = "com.hirurawa.exviusreborn"
VERSION_CODE = "1"
VERSION_NAME = "1.0"

# Exact names of your presets in Godot's export menu
WIN_PRESET_NAME = "Windows Desktop"
ANDROID_PRESET_NAME = "Android"

def run_godot_export(preset_name, output_path):
    print(f"--> Exporting {preset_name}...")
    command = [
        GODOT_EXE,
        "--headless",
        "--export-debug",
        preset_name,
        output_path
    ]
    # cwd=GODOT_PROJECT_DIR forces Godot to run from inside the 'godot' folder
    # so it can find the project.godot and export_presets.cfg files.
    subprocess.run(command, cwd=GODOT_PROJECT_DIR, check=True)
    print(f"--> Finished exporting {preset_name}.")

def build_windows():
    win_dir = os.path.join(BUILD_DIR, "Windows")
    os.makedirs(win_dir, exist_ok=True)
    
    exe_path = os.path.join(win_dir, f"{GAME_NAME}.exe")
    run_godot_export(WIN_PRESET_NAME, exe_path)
    
    print("--> Zipping Windows build...")
    shutil.make_archive(os.path.join(BUILD_DIR, f"{GAME_NAME}_Windows"), 'zip', win_dir)
    print("--> Windows zip created.")

def build_android_xapk():
    android_build_dir = os.path.join(BUILD_DIR, "Android_Raw")
    xapk_staging_dir = os.path.join(BUILD_DIR, "XAPK_Staging")
    os.makedirs(android_build_dir, exist_ok=True)
    
    apk_path = os.path.join(android_build_dir, f"{GAME_NAME}.apk")
    obb_filename = f"main.{VERSION_CODE}.{PACKAGE_NAME}.obb"
    obb_path = os.path.join(android_build_dir, obb_filename)
    
    run_godot_export(ANDROID_PRESET_NAME, apk_path)
    
    print("--> Assembling XAPK staging folder...")
    obb_target_dir = os.path.join(xapk_staging_dir, "Android", "obb", PACKAGE_NAME)
    os.makedirs(obb_target_dir, exist_ok=True)
    
    shutil.copy(apk_path, os.path.join(xapk_staging_dir, f"{GAME_NAME}.apk"))
    shutil.copy(obb_path, os.path.join(obb_target_dir, obb_filename))
    
    # Updated to look for the icon inside the Godot project folder
    icon_source = os.path.join(GODOT_PROJECT_DIR, "icon.png")
    if os.path.exists(icon_source):
        shutil.copy(icon_source, os.path.join(xapk_staging_dir, "icon.png"))
    
    total_size = os.path.getsize(apk_path) + os.path.getsize(obb_path)
    manifest = {
        "xapk_version": 1,
        "package_name": PACKAGE_NAME,
        "name": GAME_NAME,
        "version_code": VERSION_CODE,
        "version_name": VERSION_NAME,
        "min_sdk_version": "24",
        "target_sdk_version": "35",
        "total_size": total_size,
        "expansions": [
            {
                "file": f"Android/obb/{PACKAGE_NAME}/{obb_filename}",
                "install_location": "REQUIRE_EXTERNAL",
                "install_path": f"Android/obb/{PACKAGE_NAME}/{obb_filename}"
            }
        ]
    }
    
    with open(os.path.join(xapk_staging_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=4)
        
    print("--> Zipping XAPK archive...")
    zip_path = os.path.join(BUILD_DIR, GAME_NAME) 
    shutil.make_archive(zip_path, 'zip', xapk_staging_dir)
    
    final_xapk_path = os.path.join(BUILD_DIR, f"{GAME_NAME}.xapk")
    if os.path.exists(final_xapk_path):
        os.remove(final_xapk_path) 
    os.rename(zip_path + ".zip", final_xapk_path)
    
    print("--> Cleaning up intermediate files...")
    shutil.rmtree(android_build_dir)
    shutil.rmtree(xapk_staging_dir)
    
    print(f"--> Android XAPK created successfully: {final_xapk_path}")

if __name__ == "__main__":
    print("=== Starting Build Pipeline ===")
    # Ensure the Builds folder exists before doing anything else
    os.makedirs(BUILD_DIR, exist_ok=True)
    
    build_windows()
    build_android_xapk()
    
    print("=== Pipeline Complete! ===")