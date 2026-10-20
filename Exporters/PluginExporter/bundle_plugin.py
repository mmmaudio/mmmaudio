"""Copy the Mojo libraries and resources an export staged into a built plugin.

    python3 bundle_plugin.py <plugin> <stage dir>

export_plugin.py copies this script into every project it generates, and the
project's CMakeLists.txt runs it after building each plugin format, so a plain
`cmake --build` produces a plugin that loads. <stage dir> is the project's
bundle/ folder: libs/ (already relocatable and signed) and resources/.

It must stay self-contained (standard library only, Python 3.9+), since it runs
from the project folder, wherever that is moved.
"""

import shutil
import subprocess
import sys
from pathlib import Path

IS_MAC = sys.platform == "darwin"


def bundle_lib_dir(plugin):
    """Must agree with MMMBridge::libraryDirectory() in juce_template/MMMBridge.h."""
    plugin = Path(plugin)
    if IS_MAC:
        return plugin / "Contents" / "Frameworks"
    if plugin.is_dir():  # VST3 bundle: <name>.vst3/Contents/<arch>-linux/<name>.so
        arch_dir = next((plugin / "Contents").glob("*-linux"))
        return arch_dir / f"{plugin.stem}_mmm"
    return plugin.parent / f"{plugin.stem}_mmm"  # CLAP: a single .clap file


def bundle_resource_dir(plugin):
    """Must agree with MMMBridge::resourceDirectory() in juce_template/MMMBridge.h."""
    if IS_MAC:
        return Path(plugin) / "Contents" / "Resources" / "MMMAudio"
    return bundle_lib_dir(plugin) / "resources"


def bundle(plugin, stage):
    plugin, stage = Path(plugin), Path(stage)
    if not plugin.exists():
        sys.exit(f"bundle_plugin: {plugin} doesn't exist")

    libs = bundle_lib_dir(plugin)
    libs.mkdir(parents=True, exist_ok=True)
    for lib in sorted((stage / "libs").iterdir()):
        shutil.copy2(lib, libs / lib.name)

    resources = stage / "resources"
    if resources.is_dir():
        for f in resources.rglob("*"):
            if f.is_file():
                dest = bundle_resource_dir(plugin) / f.relative_to(resources)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dest)

    if IS_MAC:
        subprocess.run(["codesign", "--force", "--sign", "-", str(plugin)], check=True, capture_output=True)
    print(f"bundle_plugin: added the Mojo libraries to {plugin}")


if __name__ == "__main__":
    bundle(*sys.argv[1:3])
