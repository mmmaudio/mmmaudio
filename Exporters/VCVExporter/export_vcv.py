"""Export an MMMAudio graph as a VCV Rack plugin with one module.

    pixi run python Exporters/VCVExporter/export_vcv.py --graph_name FM4 --package_name examples \\
        --gui_file examples/FM4.py --install

or from Python, from the MMMAudio folder:

    from Exporters.VCVExporter.export_vcv import export_vcv
    export_vcv("FM4", "examples", gui_file="examples/FM4.py", install=True)

See Exporters/VCVExporter/VCVExporter.py for examples.

export_struct_vcv() (--struct on the command line) builds one struct, like Osc, as a
module instead: its next() arguments become input jacks, its result output jacks, and
the Float64 messages it reads knobs from -1 to 1.

The module runs the graph through the same engine interface as the plugins
(Exporters/PluginExporter/MMMAudioPluginBridge.mojo):

  - It has `num_in` audio inputs, which the graph reads with `world[].sound_in(i)`,
    and `num_out` audio outputs. Rack's +-5 V is the graph's +-1.
  - The Qt GUI script's sliders become knobs, turning through the same range
    with the same curve, and its buttons become buttons. A check box becomes a
    latching button, a combo box a knob with one step per item, and an XY pad
    two knobs (plus a button, if pressing the pad sends a message). Buttons that
    randomize or set other sliders move those knobs.
  - Knobs and buttons are read once per block and sent to the graph when they
    change, as the GUI would send them.

What it does (<Name> below is the module's name, by default graph_name):
  1. Compiles the graph and MMMAudioPluginBridge.mojo into shared libraries
     (as export_plugin.py does).
  2. If `gui_file` is given, translates its controls (Exporters/PluginExporter/gui_tracer.py).
  3. Writes a Rack plugin project to builds/Mojo<version>/<Name>/: the module's
     C++ (src/), its panel (res/), plugin.json, a Makefile, and the graph's Mojo
     libraries, the Mojo runtime and the files the graph loads (bundle/).
     With --no_build, the export stops here.
  4. Downloads the Rack SDK into Exporters/VCVExporter/, the first time (unless
     --rack_sdk names one).
  5. Builds it with the SDK's Makefile. The finished plugin folder is
     builds/Mojo<version>/<Name>/dist/MMMAudio-<Name>/. --install copies it into
     Rack's plugins folder (or --install_dir). Then restart Rack.

Run `export_vcv.py --help` to see all of the options.
"""

import argparse
import json
import math
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import textwrap
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from Exporters.PluginExporter import export_plugin as pe  # noqa: E402
from Exporters.SCExporter import export_sc as sce  # noqa: E402

# The module's C++ template and everything the export downloads live in src/.
SRC_DIR = HERE / "src"
TEMPLATE_DIR = SRC_DIR / "vcv_template"
# Projects go in builds/Mojo<version>/<Name>/, as the SCExporter's do.
BUILDS_ROOT = HERE / "builds"
# export_struct_vcv writes a graph that runs the struct here.
STRUCT_GRAPHS_DIR = SRC_DIR / "struct_graphs"
STRUCT_PACKAGE = "Exporters.VCVExporter.src.struct_graphs"

IS_MAC = pe.IS_MAC
RACK_OS = "mac" if IS_MAC else "lin"
RACK_CPU = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x64"
RACK_SDK_VERSION = "2.6.6"
RACK_SDK_URL = f"https://vcvrack.com/downloads/Rack-SDK-{RACK_SDK_VERSION}-{RACK_OS}-{RACK_CPU}.zip"
RACK_SDK_DIR = SRC_DIR / f"Rack-SDK-{RACK_SDK_VERSION}-{RACK_OS}-{RACK_CPU}"
RACK_USER_DIR = Path.home() / ("Library/Application Support/Rack2" if IS_MAC else ".local/share/Rack2")
PLUGINS_DIR = RACK_USER_DIR / f"plugins-{RACK_OS}-{RACK_CPU}"
PLUGIN_LIB = "plugin.dylib" if IS_MAC else "plugin.so"
SLUG_PREFIX = "MMMAudio-"

# The block sizes the module's menu offers (MMMModule.cpp's kBlockSizes).
BLOCK_SIZES = (1, 4, 16, 32, 64)

# Panel geometry, in mm. Rack panels are 128.5 mm tall and a whole number of
# HP (5.08 mm) wide.
HP = 5.08
PANEL_HEIGHT = 128.5
TITLE_Y = 6.5
CONTROLS_TOP = 12.0
CELL_WIDTH = 3 * HP   # one knob and its label
CELL_HEIGHT = 18.0
KNOB_Y = 6.5          # knob centre, from the top of its cell
LABEL_OFFSET = 8.5    # label centre, below the knob's
PORT_WIDTH = 2 * HP
PORT_ROW_HEIGHT = 15.0
PORT_Y = 9.0          # jack centre, from the top of its row
BOTTOM_MARGIN = 3.0
MIN_HP = 6
LABEL_CHARS = 10      # longest label that fits a cell
PORT_LABEL_CHARS = 7  # longest label that fits over a jack


def export_vcv(graph_name, package_name=None, gui_file=None, module_name=None, instrument=None,
               num_in=None, num_out=None, in_labels=None, out_labels=None, resources=(), block_size=32,
               install=False, build=True, rack_sdk=None, install_dir=None):
    """Build `package_name.graph_name` as a VCV Rack plugin. Returns the plugin
    folder (None with build=False).

    Args:
        graph_name: The graph's struct (and .mojo file) name, as for MMMAudio.
        package_name: The folder holding the graph, as for MMMAudio. By default
            the GUI script's `package_name`, or "examples" without one.
        gui_file: An MMMAudio Qt GUI script (like examples/FM4.py) whose
            sliders and buttons become the module's knobs and buttons.
        module_name: The module's name (default: graph_name). The plugin is
            MMMAudio-<module_name>.
        instrument: Build a module without audio inputs. By default, a graph
            that never reads `sound_in` is an instrument.
        num_in: The number of audio inputs. By default the GUI script's
            `num_input_channels` (capped at 2), or 2 without one. An instrument
            always has 0.
        num_out: The number of audio outputs. By default the N in the graph's
            `next() -> MFloat[N]`, then the GUI script's `num_output_channels`, then 2.
        in_labels: Names for the audio inputs, in order, like ["L", "R"]. A None
            in the list, a missing entry, or in_labels=None keeps the default
            name ("IN", or "IN 1", "IN 2", ...). Rack shows the full name when
            the mouse is over the jack; the panel shows its first 7 characters.
        out_labels: Names for the audio outputs, as for in_labels ("OUT", "OUT 1", ...).
        resources: Extra files or folders to bundle. Files the graph names by
            relative path (like "resources/Shiverer.wav") are found automatically.
        block_size: Samples the module collects before running the graph, which
            is also its latency: 1, 4, 16, 32 or 64. It can be changed in the
            module's right-click menu.
        install: Copy the plugin into Rack's plugins folder, replacing an earlier copy.
        build: Build the plugin with the Rack SDK. The project is always written
            to builds/Mojo<version>/<Name>/; with build=False, build it later
            with the commands in its README.md.
        rack_sdk: A Rack SDK folder. By default $RACK_DIR, else a copy downloaded
            into Exporters/VCVExporter/.
        install_dir: Install into this folder instead of Rack's plugins folder
            (implies install).
    """
    name = module_name or graph_name
    _check_options(name, install, install_dir, build, block_size)
    work_dir = _work_dir(name)

    # ---- what the module looks like ----
    spec = pe._trace_gui(Path(gui_file).resolve(), work_dir, name) if gui_file else pe._default_spec(name)
    ctor = spec.get("mmm_audio") or {}
    if package_name is None:
        package_name = ctor.get("package_name") or "examples"

    sources = pe._graph_sources(graph_name, package_name)
    if not sources:
        raise FileNotFoundError(f"can't find {package_name.replace('.', '/')}/{graph_name}.mojo")
    if num_out is None:
        num_out = pe._graph_output_channels(graph_name, package_name) or ctor.get("num_output_channels") or 2
    if instrument is None:
        instrument = not any("sound_in" in s.read_text(encoding="utf-8") for s in sources)
    if num_in is None:
        num_in = min(int(ctor.get("num_input_channels", 2)), 2)
    if instrument:
        num_in = 0
    in_labels = _port_labels(in_labels, "in_labels")
    out_labels = _port_labels(out_labels, "out_labels")

    controls, notes = _controls(spec)
    if not gui_file:
        notes.append("no gui_file, so the module has no knobs or buttons")
    return _export(
        name, work_dir, graph_name, package_name, spec, controls, notes, num_in, num_out, in_labels,
        out_labels, resources=pe._find_resources(graph_name, package_name, spec, resources),
        block_size=block_size, install=install, build=build, rack_sdk=rack_sdk, install_dir=install_dir,
        kind="instrument" if instrument else "effect", origin=f"the MMMAudio graph `{package_name}.{graph_name}`",
        description=f"The MMMAudio graph {package_name}.{graph_name}",
        tags=["Synth voice"] if instrument else ["Effect"],
        export_command=_export_command(graph_name, package_name, gui_file, module_name, instrument, num_in,
                                       num_out, in_labels[:num_in], out_labels[:num_out], resources,
                                       block_size))


def export_struct_vcv(struct_name, module="mmm_audio", module_name=None, method="next", params=None,
                      method_params=None, init_args=None, num_outputs=None, in_labels=None, out_labels=None,
                      block_size=32, install=False, build=True, rack_sdk=None, install_dir=None):
    """Build an MMMAudio struct, like Osc or a struct of your own, as a VCV Rack
    plugin. Returns the plugin folder (None with build=False).

    - Each argument of the struct's `next` method (or another method of it) becomes
      audio inputs, in order: one jack for a Float64, Bool or Int, N for an
      MFloat[N], MBool[N] or MInt[N]. The jacks are named after the arguments.
      +-5 V is +-1 to the struct, and a Bool is true above 0 V. While nothing is
      plugged into a jack, the argument gets its default value (or 0).
    - Its return value becomes the audio outputs, one jack per channel.
    - Each Float64 message the struct reads with its own Messenger gets a knob,
      which sends -1 to 1: scale the value in the struct. When the struct maps it
      with linlin, linexp or lincurve and plain numbers, the knob shows the
      mapped value (it still sends -1 to 1). A Bool message gets a
      latching button, and a trig (notify_trig) a button.

    Args:
        struct_name: The struct, e.g. "Osc".
        module: The Mojo package or module that defines it, as you would import
            it: "mmm_audio" (the default), or e.g. "Exporters.export_examples".
        module_name: The module's name (default: struct_name, plus the method's
            name for a method other than next). The plugin is MMMAudio-<module_name>.
        method, params, method_params, init_args: As for the SCExporter's
            export_struct_sc: the method to run each sample (default "next"), and
            Mojo code for the struct's parameters, the method's parameters, and
            __init__ arguments without a default.
        num_outputs: How many of the result's channels get output jacks, from the
            first: e.g. 5 of an MFloat[8]. By default all of them.
        in_labels: Names for the input jacks, in order, overriding the argument
            names. A None in the list, or a missing entry, keeps that jack's name.
        out_labels: Names for the output jacks ("OUT 1", ... by default), as for in_labels.
        block_size, install, build, rack_sdk, install_dir: As for export_vcv.
    """
    camel = "".join(w[:1].upper() + w[1:] for w in method.split("_"))
    name = module_name or struct_name + ("" if method == "next" else camel)
    _check_options(name, install, install_dir, build, block_size)
    work_dir = _work_dir(name)
    params = {k: str(v) for k, v in (params or {}).items()}

    graph_name = f"{name}Struct"
    g = sce.struct_graph(struct_name, module, method, params, method_params, init_args, STRUCT_GRAPHS_DIR,
                         graph_name, "Exporters/VCVExporter/export_vcv.py (export_struct_vcv)")
    struct_info, num_in, num_out = g["struct_info"], g["num_in"], g["num_out"]
    _log(f"exporting {module}.{struct_name}.{g['call_name']} (from {g['where']}) as {name}")
    for label, text in (("parameters", struct_info["params"]), (f"{method}'s parameters", struct_info["method_params"])):
        if text:
            _log(f"  {label}: {text}")
    if num_outputs is not None:
        if not 1 <= num_outputs <= num_out:
            raise ValueError(f"num_outputs must be from 1 to {num_out}: {struct_name}.{method} returns "
                             f"{num_out} channel{'s' if num_out != 1 else ''}")
        num_out = num_outputs

    # The jacks are named after the arguments, unless in_labels says otherwise.
    given = _port_labels(in_labels, "in_labels")
    names, unplugged = [], []
    for a in g["audio_args"]:
        for i in range(a["channels"]):
            names.append(a["arg"] if a["channels"] == 1 else f"{a['arg']} {i + 1}")
            unplugged.append(a["default"] or 0.0)
    labels = [l or n for l, n in zip(given + [None] * len(names), names)] + given[len(names):]

    controls, notes = _message_controls(struct_info["messages"], sce._find_struct(struct_name, module)[0])
    if not controls:
        notes.append(f"{struct_name} reads no messages, so the module has no knobs or buttons")

    cmd = [f"pixi run python Exporters/VCVExporter/export_vcv.py --struct {struct_name}"]
    if module != "mmm_audio":
        cmd.append(f"--module {module}")
    if module_name:
        cmd.append(f"--module_name {module_name}")
    cmd += sce.struct_command_args(method, params, g["method_params"], init_args)
    if num_outputs is not None:
        cmd.append(f"--num_outputs {num_outputs}")
    out_labels = _port_labels(out_labels, "out_labels")
    cmd += _labels_args(given[:num_in], out_labels[:num_out])
    if block_size != 32:
        cmd.append(f"--block_size {block_size}")
    return _export(
        name, work_dir, graph_name, STRUCT_PACKAGE, pe._default_spec(name), controls, notes, num_in, num_out,
        labels, out_labels, resources={}, block_size=block_size, install=install, build=build,
        rack_sdk=rack_sdk, install_dir=install_dir, kind="struct",
        origin=f"the MMMAudio struct `{module}.{struct_name}` (its `{method}`)",
        description=f"The MMMAudio struct {module}.{struct_name}",
        tags=["Effect"] if num_in else ["Synth voice"], export_command=" \\\n    ".join(cmd),
        unplugged=unplugged)


def _message_controls(messages, text):
    """A knob or button for each message a struct reads ([(key, send method)],
    as _struct_messages gives them), and notes on the ones left out. `text` is
    the struct's source, where _knob_display finds what each knob shows."""
    controls, notes = [], []
    for key, send in messages:
        base = {"id": None, "name": key, "label": _label(key), "randomize": [], "set": {}, "default": 0.0}
        if send in ("sendFloat", None):
            if send is None:
                notes.append(f"can't tell what type '{key}' is; its knob sends a Float64")
            display = _knob_display(text, key)
            shows = ""
            if display:
                mode, lo, hi, out_lo, out_hi, curve = display
                shows = f", shows {out_lo:g} to {out_hi:g}" + {"lin": "", "exp": " (exp)"}.get(mode, f" (curve {curve:g})")
            controls.append({**base, "kind": "value", "widget": "knob", "sends": [{"type": "float", "key": key}],
                             "states": [], "min": -1.0, "max": 1.0, "exp": 1.0, "integer": False,
                             "display": display, "doc": f"-1 to 1{shows}, sends {key}"})
        elif send == "sendBool":
            controls.append({**base, "kind": "state", "widget": "latch", "sends": [],
                             "states": [[{"type": "bool", "key": key, "value": v}] for v in (False, True)],
                             "doc": f"on or off, sends {key}"})
        elif send == "sendTrig":
            controls.append({**base, "kind": "trigger", "widget": "button", "sends": [],
                             "states": [[{"type": "trig", "key": key}]], "doc": f"sends {key}"})
        else:
            what = {"sendInt": "an Int", "sendString": "a String"}.get(send, "a list")
            notes.append(f"'{key}' is {what}, which a knob doesn't send; it is left out")
    return controls, notes


def _knob_display(text, key):
    """What the knob for message `key` shows: (mode, in_min, in_max, out_min,
    out_max, curve) when the struct maps the variable the message fills with
    linlin, linexp or lincurve and plain numbers, like
    `linexp(self.knob_freq + freq, -1.0, 1.0, 20.0, 200.0)`, else None. The knob
    still sends -1 to 1; Rack shows the value mapped as the struct maps it."""
    var = re.search(rf"\.update\(\s*\"{re.escape(key)}\"\s*,\s*self\.(\w+)\s*\)", text)
    if not var:
        return None
    num = r"\s*(-?[\d.]+(?:e-?\d+)?)\s*"
    m = re.search(rf"\b(linlin|linexp|lincurve)\(\s*self\.{var.group(1)}\b[^,()]*(?:\([^()]*\)[^,()]*)*,"
                  + ",".join([num] * 4) + rf"(?:,{num})?\)", text)
    if not m or (m.group(1) == "lincurve") != (m.group(6) is not None):
        return None
    mode = {"linlin": "lin", "linexp": "exp", "lincurve": "curve"}[m.group(1)]
    lo, hi, out_lo, out_hi = (float(m.group(i)) for i in range(2, 6))
    if lo == hi or (mode == "exp" and (out_lo <= 0 or out_hi <= 0)):
        return None
    return (mode, lo, hi, out_lo, out_hi, float(m.group(6) or 1.0))


def _labels_args(in_labels, out_labels):
    """The --in_labels and --out_labels options that repeat these labels."""
    cmd = []
    for arg, labels in (("--in_labels", in_labels), ("--out_labels", out_labels)):
        if any(labels):
            cmd.append(arg + " " + " ".join(shlex.quote(l) if l else "None" for l in labels))
    return cmd


def _check_options(name, install, install_dir, build, block_size):
    """Raise for options that can't work together, or a name Rack can't use."""
    if (install or install_dir is not None) and not build:
        raise ValueError("install needs a build; drop install (or install_dir) or build=False")
    if block_size not in BLOCK_SIZES:
        raise ValueError(f"block_size must be one of {', '.join(map(str, BLOCK_SIZES))}")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError(f"{name!r} can't be a Rack module name: use only letters, digits, _ and - "
                         "(pass module_name)")


def _work_dir(name):
    """builds/Mojo<version>/<name>/, created if needed."""
    work_dir = BUILDS_ROOT / f"Mojo{sce._mojo_version()}" / name
    work_dir.mkdir(parents=True, exist_ok=True)
    return work_dir


def _export(name, work_dir, graph_name, package_name, spec, controls, notes, num_in, num_out, in_labels,
            out_labels, resources, block_size, install, build, rack_sdk, install_dir, kind, origin,
            description, tags, export_command, unplugged=()):
    """The export's work, once the module's ports and controls are known: build the
    graph, write the project to `work_dir`, build it and install it. `resources`
    are the files to bundle (as _find_resources gives them), `kind` says what the
    module is in the log, `origin` what it runs in its README, and `unplugged` is
    each input's value while nothing is plugged into it (default 0)."""
    install = install or install_dir is not None
    install_dir = Path(install_dir).expanduser().resolve() if install_dir else PLUGINS_DIR
    slug = SLUG_PREFIX + name
    mojo_dir = work_dir.parent.name
    for labels, count, what in ((in_labels, num_in, "input"), (out_labels, num_out, "output")):
        if len(labels) > count:
            notes.append(f"the module has {count} audio {what}s, so these labels are left out: "
                         + ", ".join(repr(l) for l in labels[count:]))
    panel = _layout(name, controls, num_in, num_out, in_labels, out_labels)
    for port, value in zip(panel["inputs"], unplugged):
        port["unplugged"] = value
    _log(f"{kind} with {num_in} in / {num_out} out, "
         f"{len(controls)} controls, {panel['hp']} HP")
    for c in controls:
        _log(f"  {c['widget']}: {c['name']} ({c['doc']})")
    for n in notes:
        _log(f"  note: {n}")

    # ---- Mojo ----
    graph_lib, bridge_lib = pe._build_mojo_libs(graph_name, package_name)
    runtime = pe._runtime_closure([graph_lib, bridge_lib], pe._mojo_lib_dir())
    resource_files = resources
    for rel in resource_files:
        _log(f"bundling resource {rel}")
    graph_lib_name = f"{graph_name}Graph{pe.LIB_EXT}"
    bridge_lib_name = f"libMMMAudioPluginBridge{pe.LIB_EXT}"
    # The runtime libraries get names with the Mojo version in them, so that plugins
    # built with different versions load separate copies into Rack.
    renames = {n: sce._versioned_name(n, mojo_dir[len("Mojo"):]) for n in runtime}
    stage = pe._stage_bundle(work_dir, {graph_lib_name: graph_lib, bridge_lib_name: bridge_lib}, resource_files)
    for lib in (graph_lib_name, bridge_lib_name):
        sce._relink(stage / "libs" / lib, renames)
    sce._update_libs({renames[n]: path for n, path in runtime.items()}, stage / "libs", renames=renames)
    (stage / "resources").mkdir(exist_ok=True)

    # ---- the project ----
    src = work_dir / "src"
    if src.exists():
        shutil.rmtree(src)
    shutil.copytree(TEMPLATE_DIR, src)
    (src / "MMMVCVSpec.h").write_text(_spec_header(
        name, num_in, num_out, controls, spec, panel, block_size, graph_lib_name, bridge_lib_name,
        sorted(renames.values())))

    res = work_dir / "res"
    if res.exists():
        shutil.rmtree(res)
    res.mkdir()
    (res / f"{name}.svg").write_text(_panel_svg(panel, dark=False))
    (res / f"{name}-dark.svg").write_text(_panel_svg(panel, dark=True))

    version = _next_version(work_dir)
    (work_dir / "plugin.json").write_text(json.dumps({
        "slug": slug,
        "name": f"MMMAudio {name}",
        "version": version,
        "license": "MIT",
        "brand": "MMMAudio",
        "author": "MMMAudio",
        "authorEmail": "",
        "authorUrl": "",
        "pluginUrl": "",
        "manualUrl": "",
        "sourceUrl": "",
        "donateUrl": "",
        "changelogUrl": "",
        "modules": [{
            "slug": name,
            "name": name,
            "description": description,
            "tags": tags,
        }],
    }, indent=2) + "\n")
    sdk = _rack_sdk(rack_sdk) if build else Path(rack_sdk or os.environ.get("RACK_DIR") or RACK_SDK_DIR)
    (work_dir / "Makefile").write_text(MAKEFILE_TEMPLATE.format(slug=slug, version=version,
                                                                rack_dir=_home_path(sdk.resolve())))
    (work_dir / "README.md").write_text(README_TEMPLATE.format(
        name=name, slug=slug, origin=origin, mojo_dir=mojo_dir,
        plugin_lib=PLUGIN_LIB, plugins_dir=_home_path(install_dir),
        mac_steps=MAC_DIST_STEPS.format(slug=slug) if IS_MAC else "",
        export_command=export_command))
    if not build:
        _log(f"wrote the project to {work_dir} (not built; see its README.md)")
        return None

    # ---- build ----
    pe._run(["make", "-C", work_dir, f"RACK_DIR={sdk}", "-j", str(os.cpu_count() or 4)])
    dest = _assemble(work_dir, slug)
    _log(f"built {dest}")

    if install:
        install_dir.mkdir(parents=True, exist_ok=True)
        inst = install_dir / slug
        # Rack unpacks a .vcvplugin over the folder when it starts, so an older
        # packaged copy would replace this one.
        for old in install_dir.glob(f"{slug}-*.vcvplugin"):
            _log(f"removing {old}")
            old.unlink()
        if inst.exists():
            shutil.rmtree(inst)
        shutil.copytree(dest, inst, symlinks=True)
        _log(f"installed {inst}; restart Rack to use it")
    return dest


def _assemble(work_dir, slug):
    """Put the plugin folder together in dist/<slug>/, as the SDK's `make dist`
    does (without packing it into a .vcvplugin, which needs zstd)."""
    dist = work_dir / "dist" / slug
    if dist.parent.exists():
        shutil.rmtree(dist.parent)
    dist.mkdir(parents=True)
    lib = dist / PLUGIN_LIB
    shutil.copy2(work_dir / PLUGIN_LIB, lib)
    if IS_MAC:
        subprocess.run(["strip", "-S", str(lib)], check=True)
        # Rack links its plug-ins to libRack through this path, which it sets up when it starts.
        subprocess.run(["install_name_tool", "-change", "libRack.dylib", "/tmp/Rack2/libRack.dylib", str(lib)],
                       check=True, capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(lib)], check=True, capture_output=True)
    else:
        subprocess.run(["strip", "-s", str(lib)], check=True)
    shutil.copy2(work_dir / "plugin.json", dist / "plugin.json")
    shutil.copytree(work_dir / "res", dist / "res")
    shutil.copytree(work_dir / "bundle", dist / "bundle", symlinks=True)
    return dist


def _next_version(work_dir):
    """2.0.<n>, with n counting this module's builds. Rack only loads plug-ins whose
    major version is its own."""
    counter = work_dir / "build_number"
    try:
        n = int(counter.read_text()) + 1
    except (OSError, ValueError):
        n = 1
    counter.write_text(str(n))
    return f"2.0.{n}"


def _rack_sdk(rack_sdk):
    """A Rack SDK folder (with plugin.mk in it), downloaded the first time."""
    path = rack_sdk or os.environ.get("RACK_DIR")
    if path:
        path = Path(path).expanduser().resolve()
        if not (path / "plugin.mk").exists():
            raise FileNotFoundError(f"{path} is not a Rack SDK folder (no plugin.mk)")
        return path
    if not (RACK_SDK_DIR / "plugin.mk").exists():
        _log(f"downloading the Rack SDK ({RACK_SDK_URL}) into {RACK_SDK_DIR}")
        archive = SRC_DIR / "Rack-SDK.zip"
        urllib.request.urlretrieve(RACK_SDK_URL, archive)
        unpacked = SRC_DIR / "Rack-SDK.unpacked"
        if unpacked.exists():
            shutil.rmtree(unpacked)
        with zipfile.ZipFile(archive) as z:
            z.extractall(unpacked)
        archive.unlink()
        if RACK_SDK_DIR.exists():
            shutil.rmtree(RACK_SDK_DIR)
        # The archive holds one folder, Rack-SDK/.
        (unpacked / "Rack-SDK").rename(RACK_SDK_DIR)
        shutil.rmtree(unpacked)
        # zipfile doesn't keep the executable bit, which the SDK's helper scripts need.
        for f in RACK_SDK_DIR.rglob("*"):
            if f.is_file() and f.suffix in ("", ".py", ".sh"):
                os.chmod(f, 0o755)
    return RACK_SDK_DIR


def _home_path(path):
    """`path` with the home folder written as $(HOME), so the Makefile works for other users."""
    try:
        return f"$(HOME)/{path.relative_to(Path.home()).as_posix()}"
    except ValueError:
        return path.as_posix()


def _log(msg):
    print(f"[export_vcv] {msg}", flush=True)


# --------------------------------------------------------------------------
# Controls
# --------------------------------------------------------------------------
#
# A control is one knob or button:
#   {"name": its full name (the tooltip), "label": the panel's text,
#    "kind": "value" | "state" | "trigger", "widget": "knob" | "snap_knob" | "latch" | "momentary" | "button",
#    "sends": [...] and "states": [...], as in the SCExporter's controls,
#    "min", "max", "exp", "default", "integer", "choices",
#    "randomize": [control ids], "set": {control id: slider value}, "id": the GUI's param id or None}

def _controls(spec):
    """The GUI's controls in the order they appear in it, and notes on what they leave out."""
    params = {p["id"]: p for p in spec["params"]}
    controls, notes, done = [], [], set()

    def add_param(pid, momentary=False):
        if pid in done or pid not in params:
            return
        done.add(pid)
        controls.append(_param_control(params[pid], momentary))

    def walk(node):
        t = node.get("type")
        if t == "param":
            add_param(node["param"])
        elif t == "xy":
            for axis in ("x", "y"):
                if node.get(axis):
                    add_param(node[axis])
            if isinstance(node.get("pressed"), str):
                add_param(node["pressed"], momentary=True)
        elif t == "button":
            msgs = node.get("clicked") or node.get("pressed") or []
            moves = node.get("randomize") or node.get("set")
            if msgs or moves:
                what = [f"sends {', '.join(dict.fromkeys(m['key'] for m in msgs))}"] if msgs else []
                what += ["randomizes knobs"] if node.get("randomize") else []
                what += ["sets knobs"] if node.get("set") else []
                controls.append({"id": None, "name": node["label"], "label": _label(node["label"]),
                                 "kind": "trigger", "widget": "button", "sends": [], "states": [msgs],
                                 "default": 0.0, "randomize": node.get("randomize") or [],
                                 "set": node.get("set") or {}, "doc": " and ".join(what)})
        elif t == "file":
            notes.append(f"'{node['label']}' picks a file ({node['key']}), which a module can't do; "
                         "it is left out")
        for child in node.get("children", []):
            walk(child)

    walk(spec["layout"])
    for pid in params:
        add_param(pid)
    return controls, notes


def _param_control(p, momentary):
    """A knob or button for one of the GUI's parameters."""
    base = {"id": p["id"], "name": p["name"], "label": _label(p["name"]), "randomize": [], "set": {}}
    if p["kind"] == "float":
        sends = []
        for s in p.get("sends", []):
            if s["type"] == "list":
                sends.append({"type": "list", "key": s["key"], "list": s["list"], "index": s["index"]})
            elif s["type"] == "int":
                sends.append({"type": "int_round" if s.get("map") == "round" else "int", "key": s["key"]})
            elif s["type"] in ("float", "bool"):
                sends.append({"type": s["type"], "key": s["key"]})
        integer = bool(sends) and all(s["type"] in ("int", "int_round") for s in sends)
        keys = ", ".join(dict.fromkeys(s["key"] for s in sends))
        curve = f", curve {p.get('exp', 1.0):g}" if p.get("exp", 1.0) != 1.0 else ""
        return {**base, "kind": "value", "widget": "knob", "sends": sends, "states": [],
                "min": p["min"], "max": p["max"], "exp": p.get("exp", 1.0), "default": float(p["default"]),
                "integer": integer, "doc": f"{p['min']:g} to {p['max']:g}{curve}, sends {keys}"}
    states = p.get("states") or []
    if p["kind"] == "bool":
        return {**base, "kind": "state", "widget": "momentary" if momentary else "latch", "sends": [],
                "states": states, "default": 1.0 if p["default"] else 0.0,
                "doc": "on while held" if momentary else "on or off"}
    choices = p.get("choices") or [str(i) for i in range(len(states))]
    return {**base, "kind": "state", "widget": "snap_knob", "sends": [], "states": states,
            "choices": choices, "default": float(p["default"]), "doc": ", ".join(choices)}


def _label(text, chars=LABEL_CHARS):
    """A control's name, short enough for the panel. A number at the end (a
    channel's, as in "phase offset 2") is kept: "phas… 2"."""
    text = " ".join(re.sub(r"[_\s]+", " ", text).split())
    if len(text) <= chars:
        return text
    number = re.search(r" \d+$", text)
    suffix = number.group(0) if number and len(number.group(0)) < chars - 2 else ""
    return text[:chars - 1 - len(suffix)].rstrip() + "…" + suffix


def _port_labels(labels, arg):
    """`labels` as a list of names, each a string or None (keep the default)."""
    if labels is None:
        return []
    if isinstance(labels, str):
        raise TypeError(f"{arg} must be a list of strings, not a string")
    labels = list(labels)
    for l in labels:
        if l is not None and not isinstance(l, str):
            raise TypeError(f"{arg} must hold strings or None, not {l!r}")
    return [l if l and l.strip() else None for l in labels]


def _knob_value(c, value):
    """The knob position for a slider value: the value itself, or, for a slider
    with a curve, n in 0..1 where value = min + n^exp * (max - min)."""
    if c["exp"] == 1.0:
        return value
    if c["max"] == c["min"]:
        return 0.0
    n = min(max((value - c["min"]) / (c["max"] - c["min"]), 0.0), 1.0)
    return n ** (1.0 / c["exp"])


# --------------------------------------------------------------------------
# The panel
# --------------------------------------------------------------------------

def _layout(name, controls, num_in, num_out, in_labels=(), out_labels=()):
    """Where everything goes: the panel's width in HP, and each control's and
    port's centre in mm. Controls fill a grid row by row in the GUI's order;
    the inputs and then the outputs sit in rows at the bottom. `in_labels` and
    `out_labels` name the ports; a missing or None one gets the default name."""
    n = len(controls)
    min_width = max(MIN_HP * HP, len(name) * 2.4 + 4.0)
    cols = 1
    while True:
        hp = math.ceil(max(cols * CELL_WIDTH, min_width) / HP - 1e-6)
        width = hp * HP
        per_row = max(1, int(width / PORT_WIDTH + 1e-6))
        port_rows = math.ceil(num_in / per_row) + math.ceil(num_out / per_row)
        ports_top = PANEL_HEIGHT - BOTTOM_MARGIN - port_rows * PORT_ROW_HEIGHT
        rows = int((ports_top - CONTROLS_TOP) // CELL_HEIGHT)
        if rows * cols >= n:
            break
        cols += 1
    # Spread the controls across the whole width, centred. (The small margins keep
    # widths that are exact multiples, like 9 HP for three cells, from rounding down.)
    cols = max(cols, min(n, int(width / CELL_WIDTH + 1e-6)))
    x0 = (width - cols * CELL_WIDTH) / 2 + CELL_WIDTH / 2
    for i, c in enumerate(controls):
        c["x"] = x0 + (i % cols) * CELL_WIDTH
        c["y"] = CONTROLS_TOP + (i // cols) * CELL_HEIGHT + KNOB_Y

    def port_rows_of(count, default, labels, first_row):
        ports = []
        for i in range(count):
            row, col = divmod(i, per_row)
            in_row = min(per_row, count - row * per_row)
            x = (width - in_row * PORT_WIDTH) / 2 + PORT_WIDTH / 2 + col * PORT_WIDTH
            y = ports_top + (first_row + row) * PORT_ROW_HEIGHT + PORT_Y
            name = labels[i] if i < len(labels) and labels[i] else (
                default if count == 1 else f"{default} {i + 1}")
            ports.append({"name": name, "label": _label(name, PORT_LABEL_CHARS), "x": x, "y": y})
        return ports

    ins = port_rows_of(num_in, "IN", in_labels, 0)
    outs = port_rows_of(num_out, "OUT", out_labels, math.ceil(num_in / per_row))
    return {"title": name, "hp": hp, "width": width, "ports_top": ports_top, "inputs": ins, "outputs": outs}


def _panel_svg(panel, dark):
    """The panel's background: Rack draws the text, knobs and jacks on top."""
    w, h = panel["width"], PANEL_HEIGHT
    bg, ports, line = ("#1d242b", "#151a1f", "#3a444e") if dark else ("#e3e7ea", "#d3d9de", "#b7c0c8")
    top = panel["ports_top"] - 1.5
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="{w:.2f}mm" height="{h}mm" viewBox="0 0 {w:.2f} {h}">
          <rect x="0" y="0" width="{w:.2f}" height="{h}" fill="{bg}"/>
          <rect x="0" y="{top:.2f}" width="{w:.2f}" height="{h - top:.2f}" fill="{ports}"/>
          <rect x="2" y="10.5" width="{w - 4:.2f}" height="0.3" fill="{line}"/>
        </svg>
        """)


# --------------------------------------------------------------------------
# The C++ spec
# --------------------------------------------------------------------------

def _cpp_float(v):
    return f"{float(v)!r}f"


def _display_cpp(display):
    """A Control's display map, for _spec_header."""
    if not display:
        return "DisplayMap::None, { 0.f, 1.f, 0.f, 1.f, 1.f }"
    mode, *values = display
    return f"DisplayMap::{mode.capitalize()}, {{ {', '.join(_cpp_float(v) for v in values)} }}"


def _spec_header(name, num_in, num_out, controls, spec, panel, block_size, graph_lib_name, bridge_lib_name,
                 runtime_libs):
    arrays = sce._Arrays()
    init, num_init = arrays.msgs(spec.get("init", []))
    index = {c["id"]: i for i, c in enumerate(controls) if c["id"] is not None}
    cs = sce._cpp_string

    send_types = {"float": "Float", "int": "Int", "int_round": "IntRound", "bool": "Bool", "list": "ListElement"}
    widgets = {"knob": "Knob", "snap_knob": "SnapKnob", "latch": "Latch", "momentary": "Momentary",
               "button": "Button"}
    items = []
    for c in controls:
        sends = arrays.add("Send", [
            f"{{ SendType::{send_types[s['type']]}, {cs(s['key'])}, {s.get('list', 0)}, {s.get('index', 0)} }}"
            for s in c["sends"]])
        states = arrays.add("MsgList", ["{{ {}, {} }}".format(*arrays.msgs(st)) for st in c["states"]])
        choices = arrays.add("char*", [cs(x) for x in c.get("choices", [])])
        randomize = [index[pid] for pid in c["randomize"] if pid in index]
        sets = [(index[pid], _knob_value(controls[index[pid]], v)) for pid, v in c["set"].items()
                if pid in index and controls[index[pid]]["kind"] == "value"]
        randomize_array = arrays.add("int", [str(i) for i in randomize])
        sets_array = arrays.add("SetValue", [f"{{ {i}, {_cpp_float(v)} }}" for i, v in sets])
        kind = {"value": "Value", "state": "State", "trigger": "Trigger"}[c["kind"]]
        items.append(
            f"{{ {cs(c['name'])}, {cs(c['label'])}, ControlKind::{kind}, ControlWidget::{widgets[c['widget']]},\n"
            f"      {sends}, {len(c['sends'])}, {states}, {len(c['states'])},\n"
            f"      {_cpp_float(c.get('min', 0))}, {_cpp_float(c.get('max', 1))}, {_cpp_float(c.get('exp', 1))}, "
            f"{_cpp_float(c['default'])}, {'true' if c.get('integer') else 'false'}, {choices},\n"
            f"      {randomize_array}, {len(randomize)}, {sets_array}, {len(sets)}, "
            f"{_cpp_float(c['x'])}, {_cpp_float(c['y'])},\n"
            f"      {_display_cpp(c.get('display'))} }}")
    controls_array = arrays.add("Control", items)

    lists = spec.get("lists", [])
    lists_array = arrays.add("ListInit", [
        f"{{ {cs(l['key'])}, {len(l['values'])}, {arrays.add('double', [sce._cpp_double(v) for v in l['values']])} }}"
        for l in lists])

    def ports(items):
        return arrays.add("Port", [f"{{ {cs(p['name'])}, {cs(p['label'])}, {_cpp_float(p['x'])}, "
                                   f"{_cpp_float(p['y'])}, {_cpp_float(p.get('unplugged', 0.0))} }}"
                                   for p in items])
    ins, outs = ports(panel["inputs"]), ports(panel["outputs"])

    runtime = ", ".join(cs(n) for n in runtime_libs) or "nullptr"
    body = "\n".join(arrays.lines)
    return f"""\
// Generated by Exporters/VCVExporter/export_vcv.py - do not edit.
#pragma once

#include "MMMVCVTypes.h"

namespace MMMVCV {{

static constexpr const char* name = {cs(name)};
static constexpr const char* slug = {cs(name)}; // the module's; its panel is res/<slug>.svg
static constexpr int numIn = {num_in};
static constexpr int numOut = {num_out};
static constexpr int defaultBlockSize = {block_size};
static constexpr const char* bridgeLib = {cs(bridge_lib_name)};
static constexpr const char* graphLib = {cs(graph_lib_name)};
static constexpr const char* runtimeLibs[] = {{ {runtime} }};

// The panel, in mm.
static constexpr const char* title = {cs(panel['title'])};
static constexpr int panelHp = {panel['hp']};
static constexpr float titleY = {_cpp_float(TITLE_Y)};
static constexpr float labelOffset = {_cpp_float(LABEL_OFFSET)};
static constexpr float cellWidth = {_cpp_float(CELL_WIDTH)};
static constexpr float portWidth = {_cpp_float(PORT_WIDTH)};

{body}

// Sent once the graph is built.
static const Msg* const initMsgs = {init};
static constexpr int numInitMsgs = {num_init};

// The knobs and buttons, one param each, in this order.
static const Control* const controls = {controls_array};
static constexpr int numControls = {len(controls)};

static const ListInit* const lists = {lists_array};
static constexpr int numLists = {len(lists)};

static const Port* const inPorts = {ins};
static const Port* const outPorts = {outs};

}} // namespace MMMVCV
"""


# --------------------------------------------------------------------------
# Makefile and README
# --------------------------------------------------------------------------

MAKEFILE_TEMPLATE = """\
# Generated by Exporters/VCVExporter/export_vcv.py - do not edit.
RACK_DIR ?= {rack_dir}

# The SDK reads these from plugin.json with jq; setting them here means it isn't needed.
override SLUG := {slug}
override VERSION := {version}

SOURCES += src/MMMModule.cpp
DISTRIBUTABLES += res bundle

include $(RACK_DIR)/plugin.mk
"""

MAC_DIST_STEPS = """\
strip -S dist/{slug}/plugin.dylib
install_name_tool -change libRack.dylib /tmp/Rack2/libRack.dylib dist/{slug}/plugin.dylib
codesign --force --sign - dist/{slug}/plugin.dylib
"""

README_TEMPLATE = """\
# {name}

Generated by `Exporters/VCVExporter/export_vcv.py`. It is replaced on every export, so don't edit it.

A VCV Rack plugin, {slug}, with one module running {origin}, built with
{mojo_dir}. Everything it needs is in this folder; it doesn't need the MMMAudio repository
to build. Run the commands below from this folder.

## Build

Needs `make`, a C++ compiler (on macOS, Xcode's command line tools) and the Rack SDK. The
Makefile points at the SDK the export used; pass `RACK_DIR=/path/to/Rack-SDK` to use another.

```sh
make -j
```

The export then puts the plugin folder together in `dist/{slug}/`:

```sh
rm -rf dist && mkdir -p dist/{slug}
cp {plugin_lib} plugin.json dist/{slug}/
cp -R res bundle dist/{slug}/
{mac_steps}```

## Install

Copy `dist/{slug}/` into Rack's plugins folder, `{plugins_dir}/`, replacing any earlier
copy (and delete any `{slug}-*.vcvplugin` there). Then restart Rack.

## What's in here

- `src/`: the module's C++. `MMMVCVSpec.h` describes this graph's ports, knobs, buttons and
  setup messages, and where they sit on the panel.
- `res/`: the panel, light and dark.
- `bundle/`: the compiled Mojo graph, its engine and the Mojo runtime, plus files the graph loads.
- `plugin.json`, `Makefile`.

Changes to the Mojo code, the Qt GUI script, or files the graph loads need a new export,
from the MMMAudio folder:

```sh
{export_command}
```
"""


def _export_command(graph_name, package_name, gui_file, module_name, instrument, num_in, num_out,
                    in_labels, out_labels, resources, block_size):
    """The command line that repeats this export, run from the MMMAudio folder."""
    def rel(p):
        try:
            return Path(p).resolve().relative_to(REPO_ROOT).as_posix()
        except ValueError:
            return Path(p).resolve().as_posix()
    cmd = ["pixi run python Exporters/VCVExporter/export_vcv.py", f"--graph_name {graph_name}",
           f"--package_name {package_name}"]
    if gui_file:
        cmd.append(f"--gui_file {rel(gui_file)}")
    if module_name:
        cmd.append(f"--module_name {module_name}")
    cmd.append("--instrument" if instrument else f"--effect --num_in {num_in}")
    cmd.append(f"--num_out {num_out}")
    cmd += _labels_args(in_labels, out_labels)
    if resources:
        cmd.append("--resources " + " ".join(rel(r) for r in resources))
    if block_size != 32:
        cmd.append(f"--block_size {block_size}")
    return " \\\n    ".join(cmd)


def _cli_labels(labels):
    """--in_labels / --out_labels: "None" keeps that port's default name."""
    return None if labels is None else [None if l == "None" else l for l in labels]


def main():
    parser = argparse.ArgumentParser(
        description="Export an MMMAudio graph as a VCV Rack plugin.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            example, from the MMMAudio folder:
              pixi run python Exporters/VCVExporter/export_vcv.py \\
                  --graph_name FM4 --package_name examples \\
                  --gui_file examples/FM4.py --install"""))
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument("--graph_name", help="the graph to export, as for MMMAudio")
    what.add_argument("--struct", help="a struct to export instead, like Osc: its next() arguments become "
                                       "input jacks and its result output jacks")
    parser.add_argument("--package_name", help="the folder holding the graph (default: the GUI script's, else examples)")
    parser.add_argument("--gui_file", help="an MMMAudio Qt GUI script whose sliders and buttons become knobs and buttons")
    parser.add_argument("--module_name", help="the module's name (default: graph_name, or the struct's name)")
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--instrument", action="store_true", default=None, help="no audio inputs")
    kind.add_argument("--effect", dest="instrument", action="store_false", help="audio inputs")
    parser.add_argument("--num_in", type=int, help="audio inputs (effects only)")
    parser.add_argument("--num_out", type=int, help="audio outputs")
    parser.add_argument("--in_labels", nargs="+", metavar="LABEL",
                        help="names for the audio inputs, in order; None keeps one's default (IN 1, ...)")
    parser.add_argument("--out_labels", nargs="+", metavar="LABEL",
                        help="names for the audio outputs, in order; None keeps one's default (OUT 1, ...)")
    parser.add_argument("--resources", nargs="+", default=[],
                        help="extra files or folders to bundle (files the graph names are found automatically)")
    parser.add_argument("--block_size", type=int, default=32, choices=BLOCK_SIZES,
                        help="samples per graph block, which is also the latency (default 32; "
                             "changeable in the module's menu)")
    parser.add_argument("--install", action="store_true", help="copy the plugin into Rack's plugins folder")
    parser.add_argument("--install_dir", help="install into this folder instead (implies --install)")
    parser.add_argument("--no_build", dest="build", action="store_false",
                        help="only write the project into builds/Mojo<version>/<Name>/; build it later "
                             "with its README's commands")
    parser.add_argument("--rack_sdk", help="a Rack SDK folder (default: $RACK_DIR, else one downloaded into src/)")
    structs = parser.add_argument_group("with --struct")
    structs.add_argument("--module", default="mmm_audio", help="the Mojo package or module defining it (default: mmm_audio)")
    structs.add_argument("--method", default="next",
                         help="the method to run (default: next), e.g. next_basic_waveforms")
    structs.add_argument("--params", nargs="+", default=[], metavar="NAME=VALUE",
                         help="values for the struct's parameters (others have their defaults)")
    structs.add_argument("--method_params", nargs="+", default=[], metavar="NAME=VALUE",
                         help="values for the method's parameters, e.g. osc_type=OscType.saw; a parameter "
                              "pack takes a comma-separated list: osc_types=OscType.sine,OscType.saw")
    structs.add_argument("--init_args", nargs="+", default=[], metavar="NAME=EXPR",
                         help="Mojo expressions for __init__ arguments without a default")
    structs.add_argument("--num_outputs", type=int,
                         help="output jacks for the first this many of the result's channels (default: all)")
    args = parser.parse_args()

    if args.struct:
        pairs = lambda items: dict(i.split("=", 1) for i in items)
        export_struct_vcv(args.struct, args.module, module_name=args.module_name, method=args.method,
                          params=pairs(args.params), method_params=pairs(args.method_params),
                          init_args=pairs(args.init_args), num_outputs=args.num_outputs,
                          in_labels=_cli_labels(args.in_labels), out_labels=_cli_labels(args.out_labels),
                          block_size=args.block_size, install=args.install, build=args.build,
                          rack_sdk=args.rack_sdk, install_dir=args.install_dir)
        return
    export_vcv(args.graph_name, args.package_name, args.gui_file, module_name=args.module_name,
               instrument=args.instrument, num_in=args.num_in, num_out=args.num_out,
               in_labels=_cli_labels(args.in_labels), out_labels=_cli_labels(args.out_labels),
               resources=args.resources, block_size=args.block_size, install=args.install,
               build=args.build, rack_sdk=args.rack_sdk, install_dir=args.install_dir)


if __name__ == "__main__":
    main()
