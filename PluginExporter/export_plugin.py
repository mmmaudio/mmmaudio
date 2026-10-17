"""Export an MMMAudio graph as a VST3, CLAP or AU plugin.

    python PluginExporter/export_plugin.py --graph_name BenjolinExample \\
        --package_name examples --plugin_type VST3 AU --gui_file examples/BenjolinExample.py

or from Python:

    from PluginExporter.export_plugin import export_plugin   # from the MMMAudio folder
    export_plugin("BenjolinExample", "examples", plugin_type=["VST3", "AU"],
                  gui_file="examples/BenjolinExample.py")

What it does:
  1. Builds the graph's shared library (as MMMAudio.py does) and
     MMMAudioPluginBridge.mojo, the engine's C ABI.
  2. Downloads JUCE (and, for CLAP, clap-juce-extensions) into this folder
     the first time.
  3. If `gui_file` is given, runs it against stand-ins for PySide6 and
     MMMAudio (see gui_tracer.py) to learn its controls, which become host
     automatable parameters and a plain JUCE editor. Without one, the plugin
     has no parameters, just the graph.
  4. Generates a JUCE CMake project in builds/<graph_name>/ and builds it.
     The Mojo libraries and resources are staged in builds/<graph_name>/bundle/,
     and the CMake project copies them into each plugin after building it
     (bundle_plugin.py), so the project also builds on its own with cmake.
     builds/<graph_name>/README.md has the commands. With --no_build, the
     export stops after writing the project.

The editor is written as ordinary JUCE code in builds/<graph_name>/Source/
(see editor_codegen.py), one named member per control, for you to restyle.
Re-exporting keeps it once you have edited it; --reset_editor regenerates it
from the GUI. Any other .cpp files you add to Source/ are compiled too, and
files in Source/assets/ (images, fonts) are embedded as JUCE BinaryData.

The finished plugins are left in builds/<graph_name>/plugins/, and copied to
the user's plug-in folders with --install.

Every plugin, instrument or effect, accepts MIDI and forwards it to the graph
as Int list messages: "note_on" and "note_off" ([note, velocity, channel]),
"cc" ([controller, value, channel]), "pitch_bend" ([value, channel]),
"poly_aftertouch" ([note, pressure, channel]), "channel_pressure"
([pressure, channel]) and "program_change" ([program, channel]). Messages
sent under one name during a block are pooled, so the graph gets all of them,
in order, with `Messenger.notify_update_all` into a `List[List[Int]]`. A graph
only has to read the ones it uses: these names don't print the Messenger's
"not retrieved" warning. In Python, `MMMAudio.send_midi` sends the same
messages, so a graph works the same with a MIDI device and as a plugin. See
`MMMAudioProcessor::sendMidi` in juce_template/PluginProcessor.cpp.

Needs git and cmake (`pixi add cmake`), plus Xcode's command line tools on
macOS, or on Linux a C++ toolchain, JUCE's dependencies (see LINUX_PACKAGES)
and patchelf.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent

JUCE_URL = "https://github.com/juce-framework/JUCE.git"
JUCE_TAG = "9.0.4"
CLAP_URL = "https://github.com/free-audio/clap-juce-extensions.git"
# No release supports JUCE 9 yet; main does (2026-10-06).
CLAP_COMMIT = "7adee3a1bd4684d4caa5601100e364abccff4b4d"

JUCE_DIR = HERE / "JUCE"
CLAP_DIR = HERE / "clap-juce-extensions"
TEMPLATE_DIR = HERE / "juce_template"
BUILDS_DIR = HERE / "builds"

PLUGIN_TYPES = {"vst3": "VST3", "clap": "CLAP", "au": "AU"}
IS_MAC = sys.platform == "darwin"
LIB_EXT = ".dylib" if IS_MAC else ".so"

# Where each format's bundle ends up and where the user plug-in folders are.
EXTENSIONS = {"VST3": ".vst3", "CLAP": ".clap", "AU": ".component"}
INSTALL_DIRS = {
    "VST3": Path.home() / ("Library/Audio/Plug-Ins/VST3" if IS_MAC else ".vst3"),
    "CLAP": Path.home() / ("Library/Audio/Plug-Ins/CLAP" if IS_MAC else ".clap"),
    "AU": Path.home() / "Library/Audio/Plug-Ins/Components",
}


def log(msg):
    print(f"[export_plugin] {msg}", flush=True)


def run(cmd, **kwargs):
    log(" ".join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True, **kwargs)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_bundle_plugin = _load("bundle_plugin", HERE / "bundle_plugin.py")
bundle_lib_dir = _bundle_plugin.bundle_lib_dir            # where a plugin's Mojo libraries go
bundle_resource_dir = _bundle_plugin.bundle_resource_dir  # and the files the graph loads


def _graph_bridge():
    """mmm_python/graph_bridge.py, loaded on its own: the mmm_python package's
    __init__ pulls in the whole Python side (PySide6, PortAudio...)."""
    return _load("graph_bridge", REPO_ROOT / "mmm_python" / "graph_bridge.py")


# --------------------------------------------------------------------------
# Mojo libraries
# --------------------------------------------------------------------------

def build_mojo_libs(graph_name, package_name):
    """Build the graph library and the plugin bridge against the same
    precompiled mmm_audio, so they agree on the Environment's layout."""
    gb = _graph_bridge()
    pkg_dir = gb.precompile_package(REPO_ROOT / "mmm_audio")

    log(f"building graph {package_name}.{graph_name}")
    graph_lib = gb.build_graph_lib(graph_name, package_name, pkg_dir)

    log("building MMMAudioPluginBridge")
    bridge_src = (HERE / "MMMAudioPluginBridge.mojo").read_text(encoding="utf-8")
    bridge_lib = gb.build_shared_lib(
        "MMMAudioPluginBridge",
        bridge_src,
        f"{pkg_dir.name}-{hashlib.sha256(bridge_src.encode()).hexdigest()[:12]}",
        [pkg_dir],
    )
    return Path(graph_lib), Path(bridge_lib)


def mojo_lib_dir():
    """The directory holding the Mojo runtime (libKGENCompilerRTShared etc.)."""
    candidates = [Path(sys.prefix) / "lib"]
    if shutil.which("mojo"):
        candidates.append(Path(shutil.which("mojo")).resolve().parent.parent / "lib")
    for c in candidates:
        if (c / f"libKGENCompilerRTShared{LIB_EXT}").exists():
            return c
    raise RuntimeError(f"can't find the Mojo runtime libraries (looked in {candidates})")


def runtime_closure(libs, lib_dir):
    """Every library from `lib_dir` that `libs` need, directly or not."""
    found, todo = {}, list(libs)
    while todo:
        lib = todo.pop()
        for dep in linked_libs(lib):
            name = Path(dep).name
            if name in found or not (lib_dir / name).exists():
                continue
            found[name] = lib_dir / name
            todo.append(lib_dir / name)
    return found


def linked_libs(lib):
    if IS_MAC:
        out = subprocess.run(["otool", "-L", str(lib)], capture_output=True, text=True).stdout
        deps = [line.split()[0] for line in out.splitlines()[1:] if line.strip()]
        return [d.replace("@rpath/", "") for d in deps if d.startswith("@rpath/")]
    out = subprocess.run(["ldd", str(lib)], capture_output=True, text=True).stdout
    return [line.split()[0] for line in out.splitlines() if "=>" in line]


def make_relocatable(lib):
    """Point a copied library's rpath at its own folder, then (macOS) re-sign it.

    Mojo bakes in the absolute path of the pixi environment; with that gone,
    the bundle only ever loads its own copies.
    """
    if not IS_MAC:
        if shutil.which("patchelf"):
            subprocess.run(["patchelf", "--set-rpath", "$ORIGIN", str(lib)], check=False)
        return  # without patchelf, stage_bundle has already warned
    out = subprocess.run(["otool", "-l", str(lib)], capture_output=True, text=True).stdout
    for rpath in re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", out):
        subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(lib)], check=False,
                       capture_output=True)
    subprocess.run(["install_name_tool", "-add_rpath", "@loader_path", str(lib)], check=False,
                   capture_output=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(lib)], check=True, capture_output=True)


# --------------------------------------------------------------------------
# JUCE
# --------------------------------------------------------------------------

def ensure_repo(path, url, tag=None, commit=None, recursive=False):
    """Clone `url` at `tag` (or `commit`) into `path`, unless it is already there."""
    if path.exists():
        return
    log(f"downloading {url} ({tag or commit}) into {path}")
    if tag:
        run(["git", "clone", "--depth", "1", "--branch", tag, url, path])
    else:
        run(["git", "clone", "--depth", "50", url, path])
        run(["git", "-C", path, "checkout", "--quiet", commit])
    if recursive:
        run(["git", "-C", path, "submodule", "update", "--init", "--recursive", "--depth", "1"])


def find_cmake():
    # A REPL started with the pixi env's python (not `pixi run`) doesn't have the env's
    # bin folder on PATH, so also look next to the running interpreter.
    cmake = shutil.which("cmake") or shutil.which("cmake", path=str(Path(sys.executable).parent))
    if cmake is None:
        raise RuntimeError("cmake not found - install it with `pixi add cmake` (or Homebrew/apt)")
    return cmake


# --------------------------------------------------------------------------
# Spec (parameters, setup messages, layout)
# --------------------------------------------------------------------------

def trace_gui(gui_file, work_dir):
    out = work_dir / "gui_spec.json"
    log(f"translating GUI {gui_file}")
    subprocess.run([sys.executable, str(HERE / "gui_tracer.py"), str(gui_file), str(out)],
                   check=True, cwd=REPO_ROOT, stdout=subprocess.DEVNULL)
    spec = json.loads(out.read_text())
    for w in spec["warnings"]:
        log(f"GUI warning: {w}")
    return spec


def graph_output_channels(graph_name, package_name):
    """The N in the graph's `def next(mut self) -> MFloat[N]`, if it can be found."""
    for root in (Path.cwd(), REPO_ROOT):
        src = root / package_name.replace(".", "/") / f"{graph_name}.mojo"
        if src.exists():
            text = src.read_text(encoding="utf-8")
            struct = re.search(rf"struct\s+{graph_name}\b.*?(?=\nstruct\s|\Z)", text, re.S)
            m = re.search(r"def\s+next\s*\(\s*mut\s+self\s*\)[^:]*->\s*MFloat\[(\d+)\]",
                          struct.group(0) if struct else text)
            if m:
                return int(m.group(1))
    return None


def graph_sources(graph_name, package_name):
    """The graph's .mojo file plus the modules of its own package it imports."""
    for root in (Path.cwd(), REPO_ROOT):
        pkg = root / package_name.replace(".", "/")
        main = pkg / f"{graph_name}.mojo"
        if main.exists():
            text = main.read_text(encoding="utf-8")
            names = re.findall(rf"^\s*from\s+(?:{re.escape(package_name)}|)\.(\w+)\s+import", text, re.M)
            return [main] + [pkg / f"{n}.mojo" for n in dict.fromkeys(names) if (pkg / f"{n}.mojo").exists()]
    return []


def find_resources(graph_name, package_name, spec, extra=()):
    """Files the graph (or the GUI's setup messages) refer to by relative path.

    Returns {relative path as written: file on disk}. They are copied into the
    bundle, where `resolve_resource_path` (mmm_audio/functions.mojo) finds them.
    """
    strings = []
    for src in graph_sources(graph_name, package_name):
        strings += re.findall(r'"([^"\n]+)"', src.read_text(encoding="utf-8"))
    for msg in spec.get("init", []):
        values = msg.get("value")
        strings += [v for v in (values if isinstance(values, list) else [values]) if isinstance(v, str)]

    found = {}
    for s in strings:
        if os.path.isabs(s) or "/" not in s and "." not in s:
            continue
        for root in (Path.cwd(), REPO_ROOT):
            if (root / s).is_file():
                found[s] = root / s
                break
    for e in extra:
        path = Path(e).resolve()
        files = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
        for f in files:
            try:
                rel = f.relative_to(Path.cwd().resolve())
            except ValueError:
                rel = f.relative_to(path.parent)
            found[rel.as_posix()] = f
    return found


def plugin_codes(name):
    """Four-character manufacturer/plugin codes; AU wants an upper-case first letter."""
    digest = hashlib.sha1(name.encode()).hexdigest()
    letters = re.sub(r"[^A-Za-z]", "", name) or "M"
    code = letters[0].upper() + "".join(chr(ord("a") + int(c, 16) % 26) for c in digest[:3])
    return "Mmma", code


# --------------------------------------------------------------------------
# Project generation
# --------------------------------------------------------------------------

CMAKE_TEMPLATE = """\
# Generated by export_plugin.py - do not edit.
# Self-contained: everything it needs is in this folder, or downloaded.
cmake_minimum_required(VERSION 3.28)
project({target} VERSION {version})

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "")

# JUCE is downloaded on the first configure, unless MMM_JUCE_DIR names a local
# checkout of the same version.
include(FetchContent)
set(MMM_JUCE_DIR "" CACHE PATH "A local JUCE {juce_tag} checkout to use instead of downloading it")
if(MMM_JUCE_DIR)
    add_subdirectory("${{MMM_JUCE_DIR}}" JUCE)
else()
    FetchContent_Declare(JUCE GIT_REPOSITORY {juce_url} GIT_TAG {juce_tag} GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(JUCE)
endif()
{clap_subdir}
juce_add_plugin({target}
    PRODUCT_NAME "{product_name}"
    COMPANY_NAME "MMMAudio"
    BUNDLE_ID "com.mmmaudio.{bundle_name}"
    IS_SYNTH {is_synth}
    NEEDS_MIDI_INPUT TRUE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    PLUGIN_MANUFACTURER_CODE {manufacturer_code}
    PLUGIN_CODE {plugin_code}
    AU_MAIN_TYPE {au_type}
    VST3_CATEGORIES {vst3_categories}
    FORMATS {juce_formats}
    COPY_PLUGIN_AFTER_BUILD FALSE)

juce_generate_juce_header({target})

# The editor (and anything else you add) lives in Source/.
# mmm_plugin/ is the MMMAudio side, replaced on every export.
file(GLOB EDITOR_SOURCES CONFIGURE_DEPENDS "${{CMAKE_CURRENT_SOURCE_DIR}}/Source/*.cpp")
target_sources({target} PRIVATE
    "${{CMAKE_CURRENT_SOURCE_DIR}}/mmm_plugin/PluginProcessor.cpp"
    ${{EDITOR_SOURCES}})

target_include_directories({target} PRIVATE
    "${{CMAKE_CURRENT_SOURCE_DIR}}/Source" "${{CMAKE_CURRENT_SOURCE_DIR}}/mmm_plugin" "${{CMAKE_CURRENT_SOURCE_DIR}}")

# Images, fonts... in Source/assets/ become BinaryData:: (#include "BinaryData.h").
file(GLOB EDITOR_ASSETS CONFIGURE_DEPENDS "${{CMAKE_CURRENT_SOURCE_DIR}}/Source/assets/*")
if(EDITOR_ASSETS)
    juce_add_binary_data({target}_Assets SOURCES ${{EDITOR_ASSETS}})
    target_link_libraries({target} PRIVATE {target}_Assets)
endif()

target_compile_definitions({target} PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries({target}
    PRIVATE juce::juce_audio_utils ${{CMAKE_DL_LIBS}}
    PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_lto_flags juce::juce_recommended_warning_flags)
{clap_plugin}{bundle_steps}"""

CLAP_SUBDIR = """
# clap-juce-extensions, likewise downloaded unless MMM_CLAP_DIR names a local checkout.
set(MMM_CLAP_DIR "" CACHE PATH "A local clap-juce-extensions checkout ({clap_commit})")
if(MMM_CLAP_DIR)
    add_subdirectory("${{MMM_CLAP_DIR}}" clap-juce-extensions EXCLUDE_FROM_ALL)
else()
    FetchContent_Declare(clap-juce-extensions GIT_REPOSITORY {clap_url} GIT_TAG {clap_commit}
        EXCLUDE_FROM_ALL)
    FetchContent_MakeAvailable(clap-juce-extensions)
endif()
"""

CLAP_PLUGIN = """
clap_juce_extensions_plugin(TARGET {target}
    CLAP_ID "com.mmmaudio.{bundle_name}"
    CLAP_FEATURES {clap_features})
"""


def bundle_steps(target, product_name, formats):
    """CMake that copies the staged Mojo libraries into each built plugin, and installs it."""
    lines = ["",
             "# After each build, copy the Mojo libraries and resources export_plugin.py staged",
             "# in bundle/ into the plugin, so `cmake --build` makes a plugin that loads.",
             "# `cmake --install build --component plugin` then copies it into the user plug-in",
             "# folders. (A plain `cmake --install` would also run JUCE's own install rules, which",
             "# copy JUCE into /usr/local.)",
             "find_package(Python3 REQUIRED COMPONENTS Interpreter)"]
    for fmt in formats:
        plugin = f"${{CMAKE_BINARY_DIR}}/{target}_artefacts/$<CONFIG>/{fmt}/{product_name}{EXTENSIONS[fmt]}"
        dest = "$ENV{HOME}/" + INSTALL_DIRS[fmt].relative_to(Path.home()).as_posix()
        lines += [f"add_custom_command(TARGET {target}_{fmt} POST_BUILD",
                  '    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/mmm_plugin/bundle_plugin.py"',
                  f'        "{plugin}" "${{CMAKE_CURRENT_SOURCE_DIR}}/bundle"',
                  "    VERBATIM)"]
        if IS_MAC or fmt != "CLAP":
            lines.append(f'install(DIRECTORY "{plugin}" DESTINATION "{dest}" USE_SOURCE_PERMISSIONS COMPONENT plugin)')
        else:  # a Linux .clap is a single file, with its libraries in a folder beside it
            libs = f"${{CMAKE_BINARY_DIR}}/{target}_artefacts/$<CONFIG>/{fmt}/{product_name}_mmm"
            lines.append(f'install(PROGRAMS "{plugin}" DESTINATION "{dest}" COMPONENT plugin)')
            lines.append(f'install(DIRECTORY "{libs}" DESTINATION "{dest}" USE_SOURCE_PERMISSIONS COMPONENT plugin)')
    if "AU" in formats:
        lines.append("# Make the AU cache notice the new component.")
        lines.append('install(CODE "execute_process(COMMAND killall -9 AudioComponentRegistrar OUTPUT_QUIET ERROR_QUIET)" COMPONENT plugin)')
    return "\n".join(lines) + "\n"


README_TEMPLATE = """\
# {product_name}

Generated by `PluginExporter/export_plugin.py`. It is replaced on every export, so
don't edit it.

A self-contained JUCE CMake project for the MMMAudio graph `{package_name}.{graph_name}`,
building {format_list}. You can move or copy this folder anywhere; it doesn't need the
MMMAudio repository to build. Run the commands below from this folder.

{requirements}

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE={config}
cmake --build build --config {config} --parallel --target {targets}
```

The first command configures the project; it is only needed once per `build/` folder.
It downloads JUCE{clap_note}, unless you point it at local copies:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE={config} -DMMM_JUCE_DIR=/path/to/JUCE{clap_flag}
```

(The exporter keeps copies in `PluginExporter/JUCE`{clap_dir_note}.) After moving this
folder, delete `build/` first: CMake won't reuse a build folder configured elsewhere.

The plugins end up in `build/{target}_artefacts/{config}/`, with the Mojo libraries
already copied in.

## Build and install

```sh
cmake --build build --config {config} --parallel --target {targets}
cmake --install build --config {config} --component plugin
```

`--component plugin` matters: without it, CMake also runs JUCE's own install rules,
which try to copy JUCE into `/usr/local` and fail.

This copies the plugins into your user plug-in folders:

{install_list}

Restart or rescan the host to pick them up.

## What's in here

- `Source/`: the editor, yours to edit (see the comment at the top of
  `Source/PluginEditor.h`). Other `.cpp` files you add are compiled, and files in
  `Source/assets/` become `BinaryData`.
- `mmm_plugin/`: the MMMAudio processor, its controls and `bundle_plugin.py`.
- `bundle/`: the compiled Mojo graph and runtime libraries, plus files the graph loads.
- `MMMPluginSpec.h`: the plugin's parameters and setup, translated from the Qt GUI.

Everything except `Source/` is replaced when the plugin is exported again. A CMake
build picks up changes to `Source/`. Changes to the Mojo graph, the Qt GUI script, or
files the graph loads need a new export, from the MMMAudio folder:

```sh
{export_command}
```

That writes to `PluginExporter/builds/{target}/`; if you moved this folder, copy the
new `bundle/`, `mmm_plugin/` and `MMMPluginSpec.h` over. Re-exporting keeps an edited
editor; add `--reset_editor` to regenerate it from the GUI.
"""


# JUCE's build dependencies on Debian/Ubuntu (JUCE/docs/Linux Dependencies.md),
# minus curl and webkit, which the projects turn off.
LINUX_PACKAGES = ("g++ libasound2-dev libjack-jackd2-dev libfreetype-dev libfontconfig1-dev "
                  "libx11-dev libxcomposite-dev libxcursor-dev libxext-dev libxinerama-dev "
                  "libxrandr-dev libxrender-dev libxi-dev")

MAC_REQUIREMENTS = """\
Needs CMake 3.28 or newer, git, python3 and Xcode's command line tools. Inside the
MMMAudio repository, `pixi run cmake ...` uses the pixi environment's CMake."""

LINUX_REQUIREMENTS = """\
Needs CMake 3.28 or newer, git, python3, a C++ compiler and JUCE's development
packages. On Debian/Ubuntu:

```sh
sudo apt update
sudo apt install {packages}
```

Inside the MMMAudio repository, `pixi run cmake ...` uses the pixi environment's CMake.

The export (not this build) also needs `patchelf`, to make the bundled Mojo libraries
load from the plugin rather than from the pixi environment: `pixi add patchelf` or
`sudo apt install patchelf`. Without it the export prints a warning, and the plugin may
only work on the machine that exported it.

The plugins only run on Linux on the same CPU architecture they were exported on."""


def write_readme(work_dir, *, target, product_name, graph_name, package_name, formats, config,
                 export_command):
    names = {"VST3": "VST3", "CLAP": "CLAP", "AU": "AU"}
    (work_dir / "README.md").write_text(README_TEMPLATE.format(
        product_name=product_name, target=target, graph_name=graph_name, package_name=package_name,
        format_list=", ".join(names[f] for f in formats), config=config,
        targets=" ".join(f"{target}_{f}" for f in formats),
        install_list="\n".join(f"- {names[f]}: `~/{INSTALL_DIRS[f].relative_to(Path.home()) / (product_name + EXTENSIONS[f])}`"
                               for f in formats),
        clap_note=" and clap-juce-extensions" if "CLAP" in formats else "",
        clap_flag=" -DMMM_CLAP_DIR=/path/to/clap-juce-extensions" if "CLAP" in formats else "",
        clap_dir_note=" and `PluginExporter/clap-juce-extensions`" if "CLAP" in formats else "",
        export_command=export_command,
        requirements=MAC_REQUIREMENTS if IS_MAC else LINUX_REQUIREMENTS.format(
            packages=" \\\n    ".join(textwrap.wrap(LINUX_PACKAGES, 70)))))


def stage_bundle(work_dir, libs, resource_files):
    """Copy what goes inside each plugin into work_dir/bundle/: the Mojo libraries
    (made relocatable and signed) and the resources. bundle_plugin.py takes it from there."""
    if not IS_MAC and not shutil.which("patchelf"):
        log("WARNING: patchelf not found, so the bundled Mojo libraries keep pointing at this "
            "pixi environment. The plugin may still load (it preloads the Mojo runtime), but "
            "install patchelf (`pixi add patchelf` or `sudo apt install patchelf`) and re-export "
            "to make it portable.")
    stage = work_dir / "bundle"
    if stage.exists():
        shutil.rmtree(stage)
    (stage / "libs").mkdir(parents=True)
    for name, src in libs.items():
        dest = stage / "libs" / name
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
        make_relocatable(dest)
    for rel, src in resource_files.items():
        dest = stage / "resources" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    return stage


def copy_plugin_sources(work_dir):
    """Copy the processor, controls and bundle_plugin.py into work_dir/mmm_plugin/."""
    dest = work_dir / "mmm_plugin"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(TEMPLATE_DIR, dest)
    shutil.copy2(HERE / "bundle_plugin.py", dest / "bundle_plugin.py")


def cpp_string(s):
    return json.dumps(s)


def next_version(work_dir):
    """0.1.<n>, with n counting this target's builds.

    Hosts cache a plugin's description (its parameters, buses, AU validation) by
    version, and keep using the cached one while the version stays the same, so every
    build gets a new one.
    """
    counter = work_dir / "build_number"
    try:
        n = int(counter.read_text()) + 1
    except (OSError, ValueError):
        n = 1
    counter.write_text(str(n))
    return f"0.1.{n}"


def write_project(work_dir, *, target, product_name, formats, is_synth, num_in, num_out,
                  spec, graph_lib_name, bridge_lib_name, runtime_libs, version):
    manufacturer_code, plugin_code = plugin_codes(target)
    bundle_name = re.sub(r"[^A-Za-z0-9]", "", target).lower()
    juce_formats = [f for f in formats if f != "CLAP"] or ["VST3"]  # the CLAP wrapper needs one JUCE format

    cmake = CMAKE_TEMPLATE.format(
        target=target, version=version, product_name=product_name, bundle_name=bundle_name,
        is_synth="TRUE" if is_synth else "FALSE",
        manufacturer_code=manufacturer_code, plugin_code=plugin_code,
        # effects are "music effects" so that AU hosts send them MIDI too
        au_type="kAudioUnitType_MusicDevice" if is_synth else "kAudioUnitType_MusicEffect",
        vst3_categories="Instrument" if is_synth else "Fx",
        juce_formats=" ".join(juce_formats),
        juce_url=JUCE_URL, juce_tag=JUCE_TAG,
        clap_subdir=CLAP_SUBDIR.format(clap_url=CLAP_URL, clap_commit=CLAP_COMMIT) if "CLAP" in formats else "",
        clap_plugin=CLAP_PLUGIN.format(
            target=target, bundle_name=bundle_name,
            clap_features="instrument synthesizer stereo" if is_synth else "audio-effect stereo")
        if "CLAP" in formats else "",
        bundle_steps=bundle_steps(target, product_name, formats),
    )
    (work_dir / "CMakeLists.txt").write_text(cmake)
    copy_plugin_sources(work_dir)

    runtime = ", ".join(cpp_string(n) for n in runtime_libs) or "nullptr"
    header = f"""\
// Generated by export_plugin.py - do not edit.
#pragma once

namespace MMMSpec
{{
    static constexpr const char* name = {cpp_string(product_name)};
    static constexpr int numIn = {num_in};
    static constexpr int numOut = {num_out};
    static constexpr bool isSynth = {"true" if is_synth else "false"};
    static constexpr const char* bridgeLib = {cpp_string(bridge_lib_name)};
    static constexpr const char* graphLib = {cpp_string(graph_lib_name)};
    static constexpr const char* runtimeLibs[] = {{ {runtime} }};
    static constexpr const char* json = R"MMMJSON({json.dumps(spec, indent=1)})MMMJSON";
}}
"""
    (work_dir / "MMMPluginSpec.h").write_text(header)


def default_spec(title):
    return {"title": title, "width": None, "height": None, "params": [], "lists": [], "init": [],
            "layout": {"type": "vbox", "children": []}, "warnings": []}


# --------------------------------------------------------------------------
# Main entry point
# --------------------------------------------------------------------------

def normalize_types(plugin_type):
    if plugin_type is None:
        plugin_type = ["VST3"]
    if isinstance(plugin_type, str):
        plugin_type = re.split(r"[,\s]+", plugin_type)
    types_ = []
    for t in plugin_type:
        if not t:
            continue
        key = t.strip().lower()
        if key not in PLUGIN_TYPES:
            raise ValueError(f"unknown plugin_type {t!r}; choose from VST3, Clap, AU")
        types_.append(PLUGIN_TYPES[key])
    if "AU" in types_ and not IS_MAC:
        raise ValueError("AU plugins can only be built on macOS")
    return list(dict.fromkeys(types_))


def export_plugin(graph_name, package_name="examples", plugin_type="VST3", gui_file=None,
                  plugin_name=None, instrument=None, num_in=None, num_out=None,
                  resources=(), install=False, config="Release", reset_editor=False, build=True):
    """Build `package_name.graph_name` as audio plugin(s). Returns the plugin paths
    (an empty list with build=False).

    Args:
        graph_name: The graph's struct (and .mojo file) name, as for MMMAudio.
        package_name: The folder holding the graph, as for MMMAudio.
        plugin_type: "VST3", "Clap" or "AU", or a list of them.
        gui_file: An MMMAudio Qt GUI script (like examples/BenjolinExample.py)
            to translate into the plugin's parameters and editor.
        plugin_name: The plugin's name in the host (default: graph_name).
        instrument: Build an instrument rather than an effect. By default this
            is taken from the GUI script (`in_device=None` means no input).
        num_in: The number of input channels on the plugin. By default this will be taken from the GUI script's. However, if instrument=True, num_in is forced to 0. 
        num_out: Channel counts. By default from the GUI script's
            MMMAudio(...) call and the graph's `next() -> MFloat[N]`.
        resources: Extra files or folders to bundle. Files the graph names
            by relative path (like "resources/Shiverer.wav") are found and
            bundled automatically.
        install: If True, copy the plugins into the user's plug-in folders.
        config: CMake build type. "Release" or "Debug".
        reset_editor: Regenerate builds/<name>/Source/PluginEditor.* from the GUI
            even if it has been edited (it is kept otherwise).
        build: Configure and build the project with CMake. Will always write
            the project (Mojo libraries included) into builds/<name>/. With build=True, the project will be built and the plugins copied into builds/<name>/plugins/. With build=False, the project is only written, and you can build later with the commands in its README.md.
    """
    if install and not build:
        raise ValueError("install needs a build; drop install or build=False")
    formats = normalize_types(plugin_type)
    target = re.sub(r"[^A-Za-z0-9_]", "_", plugin_name or graph_name)
    product_name = plugin_name or graph_name

    work_dir = BUILDS_DIR / target
    work_dir.mkdir(parents=True, exist_ok=True)

    # ---- what the plugin looks like ----
    spec = trace_gui(Path(gui_file).resolve(), work_dir) if gui_file else default_spec(product_name)
    ctor = spec.get("mmm_audio") or {}
    if ctor.get("graph_name") and ctor["graph_name"] != graph_name:
        log(f"note: {gui_file} runs graph '{ctor['graph_name']}', but the plugin is built from '{graph_name}'")

    if num_out is None:
        num_out = graph_output_channels(graph_name, package_name) or ctor.get("num_output_channels") or 2
    if instrument is None:
        instrument = "in_device" in ctor and ctor["in_device"] is None
    if num_in is None:
        num_in = 0 if instrument else min(int(ctor.get("num_input_channels", 2)), 2)
    if instrument:
        num_in = 0
    log(f"{'instrument' if instrument else 'effect'} with {num_in} in / {num_out} out, "
        f"{len(spec['params'])} parameters")

    # ---- Mojo ----
    graph_lib, bridge_lib = build_mojo_libs(graph_name, package_name)
    lib_dir = mojo_lib_dir()
    runtime = runtime_closure([graph_lib, bridge_lib], lib_dir)
    resource_files = find_resources(graph_name, package_name, spec, resources)
    for rel in resource_files:
        log(f"bundling resource {rel}")
    graph_lib_name = f"{graph_name}Graph{LIB_EXT}"
    bridge_lib_name = f"libMMMAudioPluginBridge{LIB_EXT}"

    stage_bundle(work_dir, {graph_lib_name: graph_lib, bridge_lib_name: bridge_lib, **runtime},
                 resource_files)

    version = next_version(work_dir)
    write_project(work_dir, target=target, product_name=product_name, formats=formats,
                  is_synth=instrument, num_in=num_in, num_out=num_out, spec=spec,
                  graph_lib_name=graph_lib_name, bridge_lib_name=bridge_lib_name,
                  runtime_libs=sorted(runtime), version=version)
    editor_codegen = _load("editor_codegen", HERE / "editor_codegen.py")
    editor_codegen.write_editor(work_dir / "Source", spec, source=Path(gui_file).name if gui_file else "the graph",
                                reset=reset_editor, log=log)
    write_readme(work_dir, target=target, product_name=product_name, graph_name=graph_name,
                 package_name=package_name, formats=formats, config=config,
                 export_command=export_command(graph_name, package_name, formats, gui_file, plugin_name,
                                               instrument, num_in, num_out, resources, config))
    if not build:
        log(f"wrote the project to {work_dir} (not built; see its README.md)")
        return []

    # ---- JUCE ----
    ensure_repo(JUCE_DIR, JUCE_URL, tag=JUCE_TAG)
    if "CLAP" in formats:
        ensure_repo(CLAP_DIR, CLAP_URL, commit=CLAP_COMMIT, recursive=True)

    cmake = find_cmake()
    build_dir = work_dir / "build"
    local = [f"-DMMM_JUCE_DIR={JUCE_DIR}"] + ([f"-DMMM_CLAP_DIR={CLAP_DIR}"] if "CLAP" in formats else [])
    run([cmake, "-S", work_dir, "-B", build_dir, f"-DCMAKE_BUILD_TYPE={config}", *local])
    targets = [f"{target}_{f}" for f in formats]
    jobs = str(os.cpu_count() or 4)
    run([cmake, "--build", build_dir, "--config", config, "--parallel", jobs, "--target", *targets])

    # ---- bundle the Mojo libraries ----
    artefacts = build_dir / f"{target}_artefacts" / config
    out_dir = work_dir / "plugins"
    out_dir.mkdir(exist_ok=True)
    results = []
    for fmt in formats:
        built = artefacts / fmt / f"{product_name}{EXTENSIONS[fmt]}"
        if not built.exists():
            raise RuntimeError(f"expected {built} after the build")
        dest = out_dir / built.name
        if dest.exists():
            shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
        # The build already put the Mojo libraries in (bundle_plugin.py).
        shutil.copytree(built, dest, symlinks=True) if built.is_dir() else shutil.copy2(built, dest)
        libs = bundle_lib_dir(dest)
        if not built.is_dir():  # a Linux .clap: its libraries sit in a folder beside it
            shutil.copytree(bundle_lib_dir(built), libs, symlinks=True, dirs_exist_ok=True)
        # copytree keeps the build folder's date, which only changes when the folder is
        # first made, so Finder would show the first build's date on every later build.
        os.utime(dest)
        results.append(dest)
        log(f"built {dest} (version {version})")

        if install:
            inst = INSTALL_DIRS[fmt] / dest.name
            inst.parent.mkdir(parents=True, exist_ok=True)
            if inst.exists():
                shutil.rmtree(inst) if inst.is_dir() else inst.unlink()
            shutil.copytree(dest, inst, symlinks=True) if dest.is_dir() else shutil.copy2(dest, inst)
            os.utime(inst)
            if not IS_MAC and fmt == "CLAP":
                shutil.copytree(libs, inst.parent / libs.name, dirs_exist_ok=True)
            log(f"installed {inst}")

    if install and "AU" in formats:
        # Make the AU cache notice the new component.
        subprocess.run(["killall", "-9", "AudioComponentRegistrar"], capture_output=True)

    return results


def export_command(graph_name, package_name, formats, gui_file, plugin_name, instrument,
                   num_in, num_out, resources, config):
    """The command line that repeats this export, run from the MMMAudio folder."""
    def rel(p):
        try:
            return Path(p).resolve().relative_to(REPO_ROOT).as_posix()
        except ValueError:
            return Path(p).resolve().as_posix()
    cmd = ["pixi run python PluginExporter/export_plugin.py", f"--graph_name {graph_name}",
           f"--package_name {package_name}", "--plugin_type " + " ".join(formats)]
    if gui_file:
        cmd.append(f"--gui_file {rel(gui_file)}")
    if plugin_name:
        cmd.append(f'--plugin_name "{plugin_name}"')
    cmd.append("--instrument" if instrument else "--effect")
    if not instrument and num_in is not None:
        cmd.append(f"--num_in {num_in}")
    if num_out is not None:
        cmd.append(f"--num_out {num_out}")
    if resources:
        cmd.append("--resources " + " ".join(rel(r) for r in resources))
    if config != "Release":
        cmd.append(f"--config {config}")
    return " \\\n    ".join(cmd)


def main():
    parser = argparse.ArgumentParser(description="Export an MMMAudio graph as an audio plugin.")
    parser.add_argument("--graph_name", required=True, help="the graph to export, as for MMMAudio")
    parser.add_argument("--package_name", default="examples", help="the folder holding the graph")
    parser.add_argument("--plugin_type", nargs="+", default=["VST3"],
                        help="one or more of VST3, Clap, AU (default VST3)")
    parser.add_argument("--gui_file", help="an MMMAudio Qt GUI script to translate into a JUCE editor")
    parser.add_argument("--plugin_name", help="the plugin's name (default: graph_name)")
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--instrument", action="store_true", default=None,
                      help="build an instrument (no audio input)")
    kind.add_argument("--effect", dest="instrument", action="store_false",
                      help="build an effect (audio in and out)")
    parser.add_argument("--num_in", type=int, help="input channels (effects only)")
    parser.add_argument("--num_out", type=int, help="output channels")
    parser.add_argument("--resources", nargs="+", default=[],
                        help="extra files or folders to bundle (files the graph names are found automatically)")
    parser.add_argument("--install", action="store_true", help="copy into the user plug-in folders")
    parser.add_argument("--config", default="Release", choices=["Release", "Debug"])
    parser.add_argument("--no_build", dest="build", action="store_false",
                        help="only write the project into builds/<name>/; build it later with its README's commands")
    parser.add_argument("--reset_editor", action="store_true",
                        help="regenerate the editor in builds/<name>/Source/ from the GUI, discarding edits")
    args = parser.parse_args()

    export_plugin(args.graph_name, args.package_name, args.plugin_type, args.gui_file,
                  plugin_name=args.plugin_name, instrument=args.instrument, num_in=args.num_in,
                  num_out=args.num_out, resources=args.resources, install=args.install,
                  config=args.config, reset_editor=args.reset_editor, build=args.build)


if __name__ == "__main__":
    main()
