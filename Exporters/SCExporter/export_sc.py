"""Export an MMMAudio graph as a SuperCollider UGen.

    pixi run python Exporters/SCExporter/export_sc.py --graph_name FM4 --package_name examples \\
        --gui_file examples/FM4.py --install

or from Python, from the MMMAudio folder:

    from Exporters.SCExporter.export_sc import export_sc
    export_sc("FM4", "examples", gui_file="examples/FM4.py", install=True)

export_struct_sc("Osc") exports a single struct instead: the arguments of its
next() method become the UGen's audio-rate arguments (MMMOsc.ar(freq: 440)).

See Exporters/SCExporter/SCExporter.py for examples.

The UGen runs the graph through the same engine interface as the plugins
(Exporters/PluginExporter/MMMAudioPluginBridge.mojo):

  - The graph's audio inputs (`world[].sound_in(i)`) are its first, audio-rate,
    inputs. An instrument has none.
  - Each control becomes a control-rate input, read once per block and sent to
    the graph when it changes, as MMMAudio.py's send_float, send_int and
    send_bool would. The controls come from the GUI script's sliders, check
    boxes, combo boxes, XY pads and buttons (a button becomes a trigger), and
    from the Float64, Int and Bool values and triggers the graph reads with a
    Messenger that the GUI doesn't already send.
  - Any message (strings, lists...) can also be sent with a unit command, which
    the UGen's class wraps: `FM4.sendString(synth, "key", "text")` and so on.

What it does (<Name> below is the UGen's class name, by default graph_name):
  1. Compiles the graph and MMMAudioPluginBridge.mojo into shared libraries
     (as export_plugin.py does).
  2. If `gui_file` is given, translates its controls (Exporters/PluginExporter/gui_tracer.py).
  3. Writes a CMake project to builds/Mojo<version>/<Name>/: the UGen's C++ (src/),
     its sclang class and help file (sc/), and the graph's Mojo libraries and
     resources (bundle/). The Mojo runtime libraries, the same for every UGen
     built with that Mojo version, go in builds/Mojo<version>/shared_libraries/,
     renamed with the version (libKGENCompilerRTShared.1.1.0.dylib).
     With --no_build, the export stops here.
  4. Downloads SuperCollider's plug-in headers into Exporters/SCExporter/supercollider,
     the first time (unless --sc_path names a SuperCollider source folder).
  5. Builds it. The finished extension folder is
     builds/Mojo<version>/<Name>/extension/<Name>/. --install copies it into the
     MMMAudio folder of the user Extensions folder (or --install_dir), as
     Mojo<version>/<Name>/, and the runtime into Mojo<version>/shared_libraries/.

The extension folder holds <Name>.scx (.so on Linux), Classes/<Name>.sc, its
help file (HelpSource/Classes/<Name>.schelp, with an example), and an "ignore"
folder with the graph's Mojo libraries and the files the graph loads. The UGen
loads the Mojo runtime from ../shared_libraries/. SuperCollider doesn't look
inside folders named "ignore", so it won't mistake the Mojo libraries for
plug-ins or class files.

Run `export_sc.py --help` to see all of the options.
"""

import argparse
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from Exporters.PluginExporter import export_plugin as pe  # noqa: E402

TEMPLATE_DIR = HERE / "sc_template"
# Projects go in builds/Mojo<version>/<Name>/, next to builds/Mojo<version>/shared_libraries/,
# the Mojo runtime libraries all of that version's UGens use. They are installed the same
# way: <install folder>/Mojo<version>/<Name>/ and <install folder>/Mojo<version>/shared_libraries/.
BUILDS_ROOT = HERE / "builds"
SHARED_LIBS = "shared_libraries"

SC_URL = "https://github.com/supercollider/supercollider.git"
SC_TAG = "Version-3.13.0"
SC_DIR = HERE / "supercollider"

IS_MAC = pe.IS_MAC
SCX_EXT = ".scx" if IS_MAC else ".so"
EXTENSIONS_DIR = Path.home() / ("Library/Application Support/SuperCollider/Extensions" if IS_MAC
                                else ".local/share/SuperCollider/Extensions")
# Exported UGens are installed together, in this folder of the user Extensions folder
# (unless install_dir says otherwise), grouped by the Mojo version they were built with:
# MMMAudio/Mojo<version>/<Name>/ for each UGen, and MMMAudio/Mojo<version>/shared_libraries/
# for the Mojo runtime libraries they share.
INSTALL_DIR = EXTENSIONS_DIR / "MMMAudio"

# Words sclang won't take as argument names, and the UGen's own arguments.
RESERVED = {"in", "id", "this", "super", "thisProcess", "thisFunction", "thisFunctionDef",
            "thisMethod", "thisThread", "var", "arg", "classvar", "const", "nil", "true",
            "false", "inf", "pi", "rate", "mul", "add"}


def export_sc(graph_name, package_name=None, gui_file=None, ugen_name=None, instrument=None,
              num_in=None, num_out=None, resources=(), install=False, config="Release",
              build=True, sc_path=None, install_dir=None):
    """Build `package_name.graph_name` as a SuperCollider UGen. Returns the
    extension folder (None with build=False).

    Args:
        graph_name: The graph's struct (and .mojo file) name, as for MMMAudio.
        package_name: The folder holding the graph, as for MMMAudio. By default
            the GUI script's `package_name`, or "examples" without one.
        gui_file: An MMMAudio Qt GUI script (like examples/FM4.py) whose
            controls become the UGen's control-rate inputs.
        ugen_name: The UGen's class name (default: graph_name, capitalized).
        instrument: Build a UGen without audio inputs. By default, a graph
            that never reads `sound_in` is an instrument.
        num_in: The number of audio inputs. By default the GUI script's
            `num_input_channels` (capped at 2), or 2 without one. An instrument
            always has 0.
        num_out: The number of outputs. By default the N in the graph's
            `next() -> MFloat[N]`, then the GUI script's `num_output_channels`, then 2.
        resources: Extra files or folders to bundle. Files the graph names by
            relative path (like "resources/Shiverer.wav") are found automatically.
        install: Copy the extension into the user Extensions folder's MMMAudio
            folder (created if it isn't there), replacing an earlier copy, and the
            Mojo runtime libraries into Mojo<version>/shared_libraries/. The
            extension goes in Mojo<version>/<Name>/, and copies built with other
            Mojo versions are removed.
        config: CMake build type, "Release" or "Debug".
        build: Configure and build the project with CMake. The project is
            always written to builds/Mojo<version>/<Name>/; with build=False, build
            it later with the commands in its README.md.
        sc_path: A SuperCollider source folder to take the plug-in headers
            from. By default $SC_PATH, else a copy downloaded into Exporters/SCExporter/.
        install_dir: Install into this folder instead of Extensions/MMMAudio
            (implies install). It is created if it isn't there.
    """
    return _export(graph_name, package_name, gui_file, ugen_name, instrument, num_in, num_out, resources,
                   install, config, build, sc_path, install_dir)


def _export(graph_name, package_name, gui_file, ugen_name, instrument, num_in, num_out, resources,
            install, config, build, sc_path, install_dir=None, audio_args=None, origin=None,
            export_command=None, struct_info=None):
    """export_sc's work. `audio_args` (from export_struct_sc) names the audio inputs:
    [{"name", "channels", "default", "doc"}], in order, and `struct_info` describes
    the struct: {"struct", "method", "params", "method_params"}. `origin` is ("graph"
    or "struct", its dotted path), and `export_command` repeats the export."""
    install = install or install_dir is not None
    install_dir = Path(install_dir).expanduser().resolve() if install_dir else INSTALL_DIR
    if install and not build:
        raise ValueError("install needs a build; drop install (or install_dir) or build=False")
    name = ugen_name or graph_name[:1].upper() + graph_name[1:]
    if not re.fullmatch(r"[A-Z][A-Za-z0-9_]*", name):
        raise ValueError(f"{name!r} can't be a SuperCollider class name: it needs to start with a "
                         "capital letter and have only letters, digits and _ (pass ugen_name)")

    mojo_dir = f"Mojo{_mojo_version()}"
    builds_dir = BUILDS_ROOT / mojo_dir
    work_dir = builds_dir / name
    work_dir.mkdir(parents=True, exist_ok=True)

    # ---- what the UGen looks like ----
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
    if audio_args is not None:
        num_in = sum(a["channels"] for a in audio_args)
        instrument = num_in == 0
    origin = origin or ("graph", f"{package_name}.{graph_name}")

    controls, notes = _gui_controls(spec)
    scanned, scan_notes = _source_controls(sources, spec, covered=_keys_sent(spec))
    controls += scanned
    notes += scan_notes
    _name_controls(controls)
    _log(f"{'instrument' if instrument else 'effect'} with {num_in} in / {num_out} out, "
         f"{len(controls)} control inputs")
    for a in audio_args or []:
        _log(f"  {a['name']} (audio rate, {a['doc']})")
    for c in controls:
        _log(f"  {c['name']} ({c['doc']})")
    for n in notes:
        _log(f"  note: {n}")

    # ---- Mojo ----
    graph_lib, bridge_lib = pe._build_mojo_libs(graph_name, package_name)
    runtime = pe._runtime_closure([graph_lib, bridge_lib], pe._mojo_lib_dir())
    resource_files = pe._find_resources(graph_name, package_name, spec, resources)
    for rel in resource_files:
        _log(f"bundling resource {rel}")
    graph_lib_name = f"{graph_name}Graph{pe.LIB_EXT}"
    bridge_lib_name = f"libMMMAudioPluginBridge{pe.LIB_EXT}"
    # The runtime libraries get names with the Mojo version in them, so that UGens
    # built with different versions load separate copies into one server.
    version = mojo_dir[len("Mojo"):]
    renames = {n: _versioned_name(n, version) for n in runtime}
    runtime = {renames[n]: path for n, path in runtime.items()}
    # The UGen's own libraries go in its ignore/ folder, and find the shared runtime
    # in Mojo<version>/shared_libraries/: ../../shared_libraries from there.
    stage = pe._stage_bundle(work_dir, {graph_lib_name: graph_lib, bridge_lib_name: bridge_lib},
                             resource_files, rpaths=[f"../../{SHARED_LIBS}"])
    for lib in (graph_lib_name, bridge_lib_name):
        _relink(stage / "libs" / lib, renames)
    (stage / "resources").mkdir(exist_ok=True)
    _update_libs(runtime, builds_dir / SHARED_LIBS, renames=renames)

    # ---- the project ----
    src = work_dir / "src"
    if src.exists():
        shutil.rmtree(src)
    shutil.copytree(TEMPLATE_DIR, src)
    (src / "MMMSCSpec.h").write_text(_spec_header(
        name, num_in, num_out, controls, spec, graph_lib_name, bridge_lib_name, sorted(runtime)))

    sc = work_dir / "sc"
    if sc.exists():
        shutil.rmtree(sc)
    (sc / "Classes").mkdir(parents=True)
    (sc / "Classes" / f"{name}.sc").write_text(_sc_class(name, origin, num_in, num_out, controls, notes,
                                                         audio_args))
    (sc / "HelpSource" / "Classes").mkdir(parents=True)
    (sc / "HelpSource" / "Classes" / f"{name}.schelp").write_text(
        _sc_help(name, origin, num_in, num_out, controls, notes, audio_args, struct_info))

    (work_dir / "CMakeLists.txt").write_text(CMAKE_TEMPLATE.format(
        name=name, scx_ext=SCX_EXT, sc_tag=SC_TAG, mojo_dir=mojo_dir, shared_libs=SHARED_LIBS,
        runtime_libs=" ".join(f'"{n}"' for n in sorted(runtime)),
        sc_url=f"https://github.com/supercollider/supercollider/archive/refs/tags/{SC_TAG}.tar.gz",
        install_dir=_home_path(install_dir, "$ENV{HOME}")))
    (work_dir / "README.md").write_text(README_TEMPLATE.format(
        name=name, origin=f"{origin[0]} `{origin[1]}`", config=config, mojo_dir=mojo_dir,
        shared_libs=SHARED_LIBS, install_dir=_home_path(install_dir, "~"),
        export_command=export_command or _export_command(graph_name, package_name, gui_file, ugen_name,
                                                         instrument, num_in, num_out, resources, config)))
    if not build:
        _log(f"wrote the project to {work_dir} (not built; see its README.md)")
        return None

    # ---- build ----
    headers = _sc_headers(sc_path)
    cmake = pe._find_cmake()
    build_dir = pe._build_dir(work_dir)
    # Set every time: CMake keeps a cache variable's first value.
    pe._run([cmake, "-S", work_dir, "-B", build_dir, f"-DCMAKE_BUILD_TYPE={config}", f"-DSC_PATH={headers}",
             f"-DSC_EXTENSIONS_DIR={install_dir}"])
    pe._run([cmake, "--build", build_dir, "--config", config, "--parallel", str(os.cpu_count() or 4)])

    built = build_dir / name
    if not (built / f"{name}{SCX_EXT}").exists():
        raise RuntimeError(f"expected {built / (name + SCX_EXT)} after the build")
    dest = work_dir / "extension" / name
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(built, dest, symlinks=True)
    _log(f"built {dest}")

    if install:
        inst = install_dir / mojo_dir / name
        # Any other copy of this UGen, built with another Mojo version or installed
        # before the Mojo<version> folders, would define the same class twice.
        others = [install_dir / name] + [d / name for d in install_dir.glob("Mojo*") if d.name != mojo_dir]
        for old in others:
            if (old / f"{name}{SCX_EXT}").exists():
                _log(f"removing the earlier copy {old}")
                shutil.rmtree(old)
        if inst.exists():
            shutil.rmtree(inst)
        inst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(dest, inst, symlinks=True)
        shared = install_dir / mojo_dir / SHARED_LIBS
        _update_libs({n: builds_dir / SHARED_LIBS / n for n in runtime}, shared)
        _log(f"installed {inst} (and the Mojo runtime in {shared}); recompile the class library "
             "and reboot the server to use it")
    return dest


def _versioned_name(lib_name, version):
    """A runtime library's name with the Mojo version in it:
    libKGENCompilerRTShared.1.1.0.dylib on macOS, libKGENCompilerRTShared.so.1.1.0
    on Linux (where scsynth only loads files ending in .so as plug-ins)."""
    if IS_MAC:
        stem = lib_name[:-len(".dylib")] if lib_name.endswith(".dylib") else lib_name
        return f"{stem}.{version}.dylib"
    return f"{lib_name}.{version}"


def _relink(lib, renames, own_name=None):
    """Point `lib` at the renamed runtime libraries ({old name: new name}), give it
    the name `own_name` if there is one, and (macOS) re-sign it."""
    if IS_MAC:
        args = ["-id", f"@rpath/{own_name}"] if own_name else []
        for old, new in renames.items():
            args += ["-change", f"@rpath/{old}", f"@rpath/{new}"]
        subprocess.run(["install_name_tool", *args, str(lib)], check=True, capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(lib)], check=True, capture_output=True)
        return
    if not shutil.which("patchelf"):
        return  # _stage_bundle has already warned
    args = ["--set-soname", own_name] if own_name else []
    for old, new in renames.items():
        args += ["--replace-needed", old, new]
    subprocess.run(["patchelf", *args, str(lib)], check=True, capture_output=True)


def _mojo_version():
    """The version of the Mojo compiler the libraries are built with, like "1.1.0"."""
    mojo = shutil.which("mojo") or shutil.which("mojo", path=str(Path(sys.executable).parent))
    if mojo is None:
        raise RuntimeError("can't find mojo; run this in the MMMAudio pixi environment")
    out = subprocess.run([mojo, "--version"], capture_output=True, text=True).stdout
    m = re.search(r"Mojo\s+([0-9][\w.+-]*)", out)
    if not m:
        raise RuntimeError(f"can't read the Mojo version from `mojo --version`: {out.strip()!r}")
    return m.group(1)


def _update_libs(libs, folder, renames=None):
    """Copy {name: path} into `folder`, leaving its other files, and the ones that
    are already the same, alone. A changed file is replaced, not written over,
    so a server that has the old one loaded keeps running. With `renames`
    ({original name: new name}), each copy is pointed at its own folder and
    renamed, along with its links to the others."""
    folder.mkdir(parents=True, exist_ok=True)
    for lib_name, src in sorted(libs.items()):
        dest = folder / lib_name
        tmp = folder / f".{lib_name}.tmp"
        shutil.copy2(src, tmp)
        os.chmod(tmp, 0o755)
        if renames is not None:
            pe._make_relocatable(tmp)
            _relink(tmp, renames, own_name=lib_name)
        if dest.exists() and filecmp.cmp(tmp, dest, shallow=False):
            tmp.unlink()
        else:
            os.replace(tmp, dest)


# --------------------------------------------------------------------------
# Exporting a struct
# --------------------------------------------------------------------------

# export_struct_sc writes a graph that runs the struct here, as the package below.
STRUCT_GRAPHS_DIR = HERE / "struct_graphs"
STRUCT_PACKAGE = "Exporters.SCExporter.struct_graphs"


def export_struct_sc(struct_name, module="mmm_audio", ugen_name=None, method="next", params=None,
                     method_params=None, init_args=None, install=False, config="Release", build=True,
                     sc_path=None, install_dir=None):
    """Build an MMMAudio struct, like Osc or Freeverb, as a SuperCollider UGen.
    Each argument of the struct's `next` method (or another method of it)
    becomes an audio-rate argument of the UGen's `.ar`, in the same order, and
    its return value the UGen's output. Returns the extension folder (None with
    build=False).

    Args:
        struct_name: The struct, e.g. "Osc".
        module: The Mojo package or module that defines it, as you would import
            it: "mmm_audio" (the default), or e.g. "llm.test_export.QuadRingMod".
        ugen_name: The UGen's class name. By default "MMM" + struct_name, plus
            the method's name for a method other than next ("MMMOscNextBasicWaveforms"),
            since SuperCollider has its own Osc, Line, Phasor...
        method: The method to run each sample (default "next"), e.g.
            "next_basic_waveforms".
        params: Values for the struct's parameters, as Mojo code, e.g.
            {"num_chans": 2, "interp": "Interp.sinc"}. Others have their defaults.
        method_params: Values for the method's parameters, as Mojo code, e.g.
            {"osc_type": "OscType.saw"}. A parameter pack (`*osc_types`) takes
            a list: {"osc_types": ["OscType.sine", "OscType.saw"]}. Others have
            their defaults.
        init_args: Mojo expressions for `__init__` arguments that have no
            default, e.g. {"max_delay": "1.0"}. A World argument is given the
            graph's world.
        install, config, build, sc_path, install_dir: As for export_sc.

    An argument's channels come from its type: an MFloat[N], MBool[N] or MInt[N]
    takes N audio inputs, a Float64, Bool or Int one. A Bool is true above 0.
    """
    params = {k: str(v) for k, v in (params or {}).items()}
    method_params = dict(method_params or {})
    camel = "".join(w[:1].upper() + w[1:] for w in method.split("_"))
    name = ugen_name or "MMM" + struct_name[:1].upper() + struct_name[1:] + ("" if method == "next" else camel)
    text, where = _find_struct(struct_name, module)

    # The struct's parameters, with defaults replaced by `params`.
    struct_params = _struct_params(text, struct_name)
    values = _param_values(struct_params, params, f"{struct_name}", "params")
    struct_type = f"{struct_name}[{', '.join(f'{k}={v}' for k, v in params.items())}]" if struct_params \
        else struct_name

    # The method's parameters, with defaults replaced by `method_params`.
    method_param_list, args, returns = _method_signature(text, struct_name, method)
    packs = {p.lstrip("*") for p, _ in method_param_list if p.startswith("*")}
    for k, v in method_params.items():
        if k in packs:
            v = [x.strip() for x in v.split(",")] if isinstance(v, str) else list(v)
            if not v:
                raise ValueError(f"{struct_name}.{method}'s {k} needs at least one value")
            method_params[k] = v
        else:
            method_params[k] = str(v)
    method_values = _param_values({p.lstrip("*"): d for p, d in method_param_list}, method_params,
                                  f"{struct_name}.{method}", "method_params",
                                  example=lambda k: '["OscType.sine", ...]' if k in packs else "...")
    # A parameter pack goes first, by position; the others by name.
    method_brackets = [", ".join(v) for k, v in method_params.items() if k in packs]
    method_brackets += [f"{k}={v}" for k, v in method_params.items() if k not in packs]
    call_name = f"{method}[{', '.join(method_brackets)}]" if method_brackets else method

    # The method's arguments become audio inputs, and its result the outputs.
    audio_args, calls, used, channel = [], [], set(), 0
    for arg, type_, default in args:
        kind, width, scalar = _value_type(type_, values, f"{struct_name}.{method}'s argument {arg!r}")
        reads = [f"self.world[].sound_in({channel + i})" for i in range(width)]
        calls.append(f"{arg}={_mojo_read(kind, width, scalar, reads)}")
        channel += width
        sc_name = re.sub(r"\W+", "_", arg).strip("_") or "arg"
        sc_name = sc_name[0].lower() + sc_name[1:]
        if not sc_name[0].isalpha() or sc_name in RESERVED or sc_name in used:
            sc_name = "a_" + sc_name if not sc_name[0].isalpha() else sc_name + "_"
        used.add(sc_name)
        audio_args.append({"name": sc_name, "channels": width, "default": _default_number(default),
                           "doc": f"{struct_name}.{method}'s {arg} ({_resolved(type_, values)}"
                                  + (", true above 0)" if kind == "bool" else ")")})
    out_kind, num_out, out_scalar = _value_type(returns, values, f"{struct_name}.{method}'s return value")

    def listed(vals, given):
        return ", ".join(f"{k} = {', '.join(v) if isinstance(v, list) else v}" + ("" if k in given else " (default)")
                         for k, v in vals.items())
    struct_info = {"struct": struct_name, "method": method,
                   "params": listed(values, params), "method_params": listed(method_values, method_params),
                   "messages": _struct_messages(text)}

    init = _init_call(text, struct_name, init_args or {})
    imports = "from mmm_audio import *"
    if module != "mmm_audio":
        # From the file that defines it: a package's module of the same name would
        # shadow the struct.
        parts = where.with_suffix("").parts
        imports += f"\nfrom {'.'.join(parts[:-1] if parts[-1] == '__init__' else parts)} import {struct_name}"
    graph_name = f"{name}Struct"
    STRUCT_GRAPHS_DIR.mkdir(exist_ok=True)
    (STRUCT_GRAPHS_DIR / f"{graph_name}.mojo").write_text(STRUCT_GRAPH_TEMPLATE.format(
        imports=imports, graph=graph_name, struct=struct_name, module=module, method=method,
        call_name=call_name, struct_type=struct_type, init=init, num_out=num_out,
        call=",\n            ".join(calls), result=_mojo_to_float(out_kind, num_out, out_scalar, "out")))
    _log(f"exporting {module}.{struct_name}.{call_name} (from {where}) as {name}: "
         f"{channel} audio inputs, {num_out} output{'s' if num_out != 1 else ''}")
    for label, text_ in (("parameters", struct_info["params"]), (f"{method}'s parameters", struct_info["method_params"])):
        if text_:
            _log(f"  {label}: {text_}")

    cmd = [f"pixi run python Exporters/SCExporter/export_sc.py --struct {struct_name}"]
    if module != "mmm_audio":
        cmd.append(f"--module {module}")
    if ugen_name:
        cmd.append(f"--ugen_name {ugen_name}")
    if method != "next":
        cmd.append(f"--method {method}")
    if params:
        cmd.append("--params " + " ".join(f"{k}={v}" for k, v in params.items()))
    if method_params:
        cmd.append("--method_params " + " ".join(f"{k}={','.join(v) if isinstance(v, list) else v}"
                                                 for k, v in method_params.items()))
    if init_args:
        cmd.append("--init_args " + " ".join(f"'{k}={v}'" for k, v in init_args.items()))
    if config != "Release":
        cmd.append(f"--config {config}")
    return _export(graph_name, STRUCT_PACKAGE, None, name, None, None, num_out, (), install, config,
                   build, sc_path, install_dir, audio_args=audio_args, origin=("struct", f"{module}.{struct_name}"),
                   export_command=" \\\n    ".join(cmd), struct_info=struct_info)


def _struct_messages(text):
    """The messages the struct reads with its own Messengers, in order:
    [(key, send method)], like ("load_wavetable", "sendString"). The send method
    is None when the value's type can't be found."""
    sends = {"Float64": "sendFloat", "Int": "sendInt", "Bool": "sendBool", "String": "sendString"}
    fields = dict(re.findall(r"^\s*var\s+(\w+)\s*:\s*([\w\[\], ]+?)\s*$", text, re.M))
    found = {}
    for var in re.findall(r"^\s*var\s+(\w+)\s*:\s*Messenger\b", text, re.M):
        call = rf"self\.{var}\.(\w+)(?:\[([^\]]*)\])?\(\s*\"([^\"]+)\"\s*(?:,\s*(?:self\.)?(\w+))?"
        for how, brackets, key, value in re.findall(call, text):
            if how == "notify_trig":
                send = "sendTrig"
            elif "callback" in how:
                # The callback's argument type: def load(name: String) capturing
                fn = (brackets or "").split(",")[-1].strip()
                m = re.search(rf"def\s+{re.escape(fn)}\s*\(\s*\w+\s*:\s*([\w\[\]]+)", text) if fn else None
                type_ = m.group(1) if m else ""
                type_ = re.sub(r"^List\[(\w+)\]$", r"\1", type_) if how.endswith("_all") else type_
                send = sends.get(type_)
            else:
                type_ = fields.get(value, "").strip()
                type_ = re.sub(r"^List\[(\w+)\]$", r"\1", type_) if how.endswith("_all") else type_
                send = sends.get(type_)
            if send and how.endswith("_all") and send != "sendTrig":
                send += "s"
            found.setdefault(key, send)
    return list(found.items())


def _param_values(declared, given, owner, option, example=lambda k: "..."):
    """{parameter: value}: `given`'s, else the declared default. Raises for an
    unknown parameter, or one with neither."""
    unknown = set(given) - set(declared)
    if unknown:
        raise ValueError(f"{owner} has no parameter {', '.join(sorted(unknown))} "
                         f"(it has: {', '.join(declared) or 'none'})")
    values = {k: given.get(k, d) for k, d in declared.items()}
    missing = [k for k, v in values.items() if v is None]
    if missing:
        raise ValueError(f"{owner}'s parameter {', '.join(missing)} has no default: pass {option}="
                         + "{" + ", ".join(f"{k!r}: {example(k)}" for k in missing) + "}")
    return values


STRUCT_GRAPH_TEMPLATE = """\
# Generated by Exporters/SCExporter/export_sc.py (export_struct_sc) - do not edit.
# Runs {module}.{struct}.{call_name} as an MMMAudio graph: its arguments are the
# graph's audio inputs, in order, and its result the graph's outputs.
{imports}


struct {graph}(Movable, Copyable):
    var world: World
    var unit: {struct_type}

    def __init__(out self, world: World):
        self.world = world
        self.unit = {struct_type}({init})

    @always_inline
    def next(mut self) -> MFloat[{num_out}]:
        var out = self.unit.{call_name}(
            {call}
        )
        return {result}
"""


def _find_struct(struct_name, module):
    """The text of `struct struct_name` (up to the next top-level line) in
    `module`, and the file it is in."""
    for root in (Path.cwd(), REPO_ROOT):
        base = root / module.replace(".", "/")
        files = [base.with_suffix(".mojo")] if base.with_suffix(".mojo").exists() else \
            sorted(p for p in base.rglob("*.mojo") if "__mojocache__" not in p.parts) if base.is_dir() else []
        for f in files:
            text = f.read_text(encoding="utf-8")
            m = re.search(rf"^struct\s+{re.escape(struct_name)}\b", text, re.M)
            if m:
                end = re.search(r"\n(?=[^\s#])", text[m.end():])
                return text[m.start():m.end() + end.start() if end else len(text)], f.relative_to(root)
        if files:
            break
    raise FileNotFoundError(f"can't find struct {struct_name} in {module}")


def _bracketed(text, start):
    """The text between the bracket at text[start] and its partner, and the
    index after the partner."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] in "([{":
            depth += 1
        elif text[i] in ")]}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i], i + 1
    raise ValueError(f"unbalanced brackets in: {text[start:start + 80]}")


def _split_args(text):
    """Split a parameter list at its top-level commas."""
    parts, depth, cur = [], 0, ""
    for ch in text:
        depth += (ch in "([{") - (ch in ")]}")
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [" ".join(p.split()) for p in parts if p.strip()]


def _parse_param(p):
    """(name, type, default) from `name: Type = default`; type and default may be None."""
    m = re.fullmatch(r"(?:(?:mut|owned|var|ref|out|deinit)\s+)?(\*{0,2}\w+)\s*(?::\s*([^=]+?))?\s*(?:=\s*(.+))?", p)
    if not m:
        raise ValueError(f"can't read the parameter {p!r}")
    return m.group(1), m.group(2), m.group(3)


def _struct_params(text, struct_name):
    """{parameter: default (or None)} of `struct Name[...]`."""
    m = re.match(rf"struct\s+{re.escape(struct_name)}\s*", text)
    if text[m.end():m.end() + 1] != "[":
        return {}
    inside, _ = _bracketed(text, m.end())
    out = {}
    for p in _split_args(inside):
        if p in ("/", "*", "//"):
            continue
        name, _, default = _parse_param(p)
        out[name] = default
    return out


def _method_signature(text, struct_name, method):
    """The method's ([(param, default)], [(arg, type, default)], return type)."""
    m = re.search(rf"\n\s+def\s+{re.escape(method)}\s*(?=[\[(])", text)
    if not m:
        raise ValueError(f"{struct_name} has no method {method}")
    i = m.end()
    method_params = []
    if text[i] == "[":
        inside, i = _bracketed(text, i)
        method_params = [_parse_param(p)[::2] for p in _split_args(inside) if p not in ("/", "*", "//")]
    inside, i = _bracketed(text, text.index("(", i))
    ret = re.match(r"\s*(?:raises\s*)?->\s*([^:]+?)\s*:", text[i:])
    if not ret:
        raise ValueError(f"{struct_name}.{method} returns nothing, so it can't be a UGen")
    args = []
    for p in _split_args(inside):
        if re.fullmatch(r"(?:(?:mut|ref|out)\s+)?self", p) or p in ("/", "*", "//"):
            continue
        if re.match(r"(?:mut|ref|out|inout)\s", p):
            raise ValueError(f"{struct_name}.{method}'s argument {p!r} is written to, so it can't be an input")
        name, type_, default = _parse_param(p)
        if name.startswith("*") or type_ is None:
            raise ValueError(f"{struct_name}.{method}'s argument {p!r} can't be an input")
        args.append((name, type_, default))
    return method_params, args, ret.group(1)


def _value_type(type_, values, what):
    """("float" | "bool" | "int", channels, is a Float64/Bool/Int) for a Mojo type,
    with the struct's parameters (`self.num_chans`) replaced by their values."""
    t = re.sub(r"\s+", "", _resolved(type_, values))
    t = re.sub(r"^SIMD\[DType\.(float64|bool|int),", lambda m: {"float64": "MFloat[", "bool": "MBool[",
                                                                    "int": "MInt["}[m.group(1)], t)
    scalars = {"Float64": "float", "Bool": "bool", "Int": "int"}
    if t in scalars:
        return scalars[t], 1, True
    simd = {"MFloat": "float", "MBool": "bool", "MInt": "int"}
    if t in simd:
        return simd[t], 1, False
    m = re.fullmatch(r"(MFloat|MBool|MInt)\[(?:N=)?(\w+)\]", t)
    if m and m.group(2).isdigit():
        return simd[m.group(1)], int(m.group(2)), False
    raise ValueError(f"{what} is a {type_.strip()}: only Float64, Bool, Int, MFloat[N], MBool[N] and "
                     "MInt[N] can be audio")


def _resolved(type_, values):
    """A Mojo type with the struct's parameters (`self.num_chans`) replaced by their values."""
    return re.sub(r"\b(?:self|Self)\.(\w+)", lambda m: values.get(m.group(1)) or m.group(0), type_.strip())


def _mojo_read(kind, width, scalar, reads):
    """Mojo code for a value of the given type from audio input samples. A
    Bool is true above 0."""
    if kind == "bool":
        reads = [f"{r} > 0.0" for r in reads]
    elif kind == "int":
        reads = [f"Int({r})" for r in reads]
    if scalar:
        return reads[0]
    simd = {"float": "MFloat", "bool": "MBool", "int": "MInt"}[kind]
    return f"{simd}[{width}]({', '.join(reads)})"


def _mojo_to_float(kind, width, scalar, value):
    """Mojo code for `value` as the graph's MFloat[width] output."""
    if kind == "float":
        return f"MFloat[1]({value})" if scalar else value
    if kind == "bool" and scalar:
        return f"MFloat[1](1.0 if {value} else 0.0)"
    if scalar:
        return f"MFloat[1](Float64({value}))"
    return f"{value}.cast[DType.float64]()"


def _default_number(default):
    """The number in a Mojo default value like `MFloat[self.num_chans](100.0)`,
    `True` or `fill=False`, or None when there is no default."""
    if default is None:
        return None
    found = re.findall(r"\bTrue\b|\bFalse\b|(?<![\w.])[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?",
                       re.sub(r"\[[^\]]*\]", "", default))
    if not found:
        return 0.0
    return {"True": 1.0, "False": 0.0}.get(found[-1]) if found[-1] in ("True", "False") else float(found[-1])


def _init_call(text, struct_name, init_args):
    """The arguments of the struct's construction: the world, plus `init_args`."""
    m = re.search(r"\n\s+def\s+__init__\s*(?=\()", text)
    if not m:
        return ""
    inside, _ = _bracketed(text, m.end())
    call, missing = [], []
    for p in _split_args(inside):
        if re.fullmatch(r"(?:out|mut|ref)?\s*self", p) or p in ("/", "*", "//"):
            continue
        name, type_, default = _parse_param(p)
        if name in init_args:
            call.append(f"{name}={init_args[name]}")
        elif type_ and type_.strip() == "World":
            call.append(f"{name}=self.world")
        elif default is None:
            missing.append(name)
    if missing:
        raise ValueError(f"{struct_name}.__init__'s argument {', '.join(missing)} has no default: pass "
                         "init_args=" + "{" + ", ".join(f"{k!r}: '...'" for k in missing) + "}")
    unknown = set(init_args) - {c.split("=")[0] for c in call}
    if unknown:
        raise ValueError(f"{struct_name}.__init__ has no argument {', '.join(sorted(unknown))}")
    return ", ".join(call)


def _home_path(path, home):
    """`path` with the home folder written as `home`, so the project works for other users."""
    try:
        return f"{home}/{path.relative_to(Path.home()).as_posix()}"
    except ValueError:
        return path.as_posix()


def _log(msg):
    print(f"[export_sc] {msg}", flush=True)


def _sc_headers(sc_path):
    """A SuperCollider source folder with include/plugin_interface in it."""
    path = sc_path or os.environ.get("SC_PATH")
    if path:
        path = Path(path).expanduser().resolve()
        if not (path / "include" / "plugin_interface" / "SC_PlugIn.h").exists():
            raise FileNotFoundError(f"{path} is not a SuperCollider source folder "
                                    "(no include/plugin_interface/SC_PlugIn.h)")
        return path
    if not (SC_DIR / "include" / "plugin_interface" / "SC_PlugIn.h").exists():
        if SC_DIR.exists():
            shutil.rmtree(SC_DIR)
        _log(f"downloading SuperCollider's headers ({SC_TAG}) into {SC_DIR}")
        pe._run(["git", "clone", "--depth", "1", "--branch", SC_TAG, "--filter=blob:none", "--sparse",
                 SC_URL, SC_DIR])
        pe._run(["git", "-C", SC_DIR, "sparse-checkout", "set", "include"])
    return SC_DIR


# --------------------------------------------------------------------------
# Controls
# --------------------------------------------------------------------------
#
# A control is one control-rate input:
#   {"name": sclang argument name (set by _name_controls), "base": what to name it after,
#    "kind": "value" | "state" | "trigger", "default": float,
#    "sends": [{"type": "float" | "int" | "int_round" | "bool" | "list", "key", "list", "index"}],
#    "states": [[message, ...], ...], "doc": a description,
#    "range": (min, max, exp) for a GUI slider, whose value is min + n ** exp * (max - min)}
# Messages are as the GUI tracer records them: {"type", "key", "value"}.

def _gui_controls(spec):
    """The GUI's parameters and buttons, as controls, and notes on what they leave out."""
    controls, notes = [], []
    for p in spec["params"]:
        if p["kind"] == "float":
            sends = []
            for s in p.get("sends", []):
                if s["type"] == "list":
                    sends.append({"type": "list", "key": s["key"], "list": s["list"], "index": s["index"]})
                elif s["type"] == "int":
                    sends.append({"type": "int_round" if s.get("map") == "round" else "int", "key": s["key"]})
                elif s["type"] in ("float", "bool"):
                    sends.append({"type": s["type"], "key": s["key"]})
            keys = ", ".join(dict.fromkeys(s["key"] for s in sends))
            controls.append({"base": p["id"], "kind": "value", "default": float(p["default"]), "sends": sends,
                             "states": [], "range": (p["min"], p["max"], p.get("exp", 1.0)),
                             "doc": f"{p['min']:g} to {p['max']:g}, sends {keys}"})
        else:
            states = p.get("states") or []
            if p["kind"] == "bool":
                doc, default = "0 or 1", 1.0 if p["default"] else 0.0
            else:
                choices = p.get("choices") or [str(i) for i in range(len(states))]
                doc = ", ".join(f"{i} = {c}" for i, c in enumerate(choices))
                default = float(p["default"])
            controls.append({"base": p["id"], "kind": "state", "default": default, "sends": [],
                             "states": states, "doc": doc})

    def walk(node):
        if node.get("type") == "button":
            msgs = node.get("clicked") or node.get("pressed")
            if msgs:
                controls.append({"base": node["label"], "kind": "trigger", "default": 0.0, "sends": [],
                                 "states": [msgs],
                                 "doc": f"trigger: sends {', '.join(m['key'] for m in msgs)}"})
            elif node.get("randomize") or node.get("set"):
                notes.append(f"the '{node['label']}' button moves other controls, which a UGen can't do; "
                             "it is left out")
        elif node.get("type") == "file":
            notes.append(f"'{node['key']}' is a file path ({node['msg_type']} message): send it with "
                         f".send{node['msg_type'].capitalize()}")
        for child in node.get("children", []):
            walk(child)
    walk(spec["layout"])
    return controls, notes


def _keys_sent(spec):
    """Every message name the GUI's controls send."""
    keys = {s["key"] for p in spec["params"] for s in p.get("sends", [])}
    keys |= {m["key"] for p in spec["params"] for st in p.get("states", []) for m in st}
    keys |= {l["key"] for l in spec.get("lists", [])}

    def walk(node):
        for sig in ("clicked", "pressed", "released"):
            keys.update(m["key"] for m in node.get(sig, []))
        if node.get("type") == "file":
            keys.add(node["key"])
        for child in node.get("children", []):
            walk(child)
    walk(spec["layout"])
    return keys


MSG_TYPES = {"Float64": "float", "Int": "int", "Bool": "bool"}


def _source_controls(sources, spec, covered):
    """Controls for the values and triggers the graph's Messengers read that the
    GUI doesn't send: `messenger.update("key", self.x)` with x a Float64, Int or
    Bool, and `messenger.notify_trig("key")`."""
    init = {m["key"]: m.get("value") for m in spec.get("init", [])}
    controls, notes, seen = [], [], set(covered)
    structs = [s for src in sources for s in re.split(r"\n(?=struct\s)", src.read_text(encoding="utf-8"))]
    for text in structs:
        # self.m = Messenger(self.world, "synth1") prefixes its keys with "synth1.";
        # a namespace that is only known when the graph runs can't be followed.
        namespaces = {}
        for messenger, args in re.findall(r"self\.(\w+)\s*=\s*Messenger\(([^)]*)\)", text):
            args = [a.strip() for a in args.split(",")]
            ns = args[1].split("=")[-1].strip() if len(args) > 1 else "None"
            namespaces[messenger] = ns[1:-1] if ns.startswith('"') else ("" if ns == "None" else None)

        uses = re.finditer(r'self\.(\w+)\.(?:notify_trig\(\s*"([^"]+)"\s*\)'
                           r'|(?:notify_)?update\(\s*"([^"]+)"\s*,\s*self\.(\w+)\s*\))', text)
        for use in uses:
            messenger, trig_key, key, field = use.groups()
            ns = namespaces.get(messenger, "")
            if ns is None:
                notes.append(f"'{trig_key or key}' is read by a Messenger whose namespace is set when the graph "
                             f"runs: send it with its full name, \"<namespace>.{trig_key or key}\"")
                continue
            key = f"{ns}.{trig_key or key}" if ns else trig_key or key
            if key in seen:
                continue
            seen.add(key)
            if trig_key:
                controls.append({"base": key, "kind": "trigger", "default": 0.0, "sends": [],
                                 "states": [[{"type": "trig", "key": key}]], "doc": f"trigger: sends {key}"})
                continue
            decl = re.search(rf"\bvar\s+{field}\s*:\s*([\w.]+(?:\[[^\]]*\])?)", text)
            type_ = decl.group(1) if decl else "?"
            if type_ not in MSG_TYPES:
                kind = {"String": "String", "List[String]": "Strings", "List[Float64]": "Floats",
                        "List[Int]": "Ints", "List[Bool]": "Bools"}.get(type_, "Floats")
                notes.append(f"'{key}' is a {type_}: send it with .send{kind}")
                continue
            msg_type = MSG_TYPES[type_]
            if key in init:
                default = float(init[key])
            else:
                value = re.search(rf"self\.{field}\s*=\s*(True|False|[-+]?\d[\d.]*(?:[eE][-+]?\d+)?)\b", text)
                default = {"True": 1.0, "False": 0.0}.get(value.group(1), None) if value else 0.0
                if default is None:
                    default = float(value.group(1))
            controls.append({"base": key, "kind": "value", "default": default,
                             "sends": [{"type": msg_type, "key": key}],
                             "states": [], "doc": f"{type_}, sends {key}"})
    return controls, notes


def _name_controls(controls):
    """Give each control a distinct sclang argument name."""
    used = set()
    for c in controls:
        name = re.sub(r"\W+", "_", c["base"]).strip("_") or "control"
        if not name[0].isalpha():
            name = "c" + name
        name = name[0].lower() + name[1:]
        if name in RESERVED:
            name += "_"
        base, n = name, 2
        while name in used:
            name, n = f"{base}{n}", n + 1
        used.add(name)
        c["name"] = name


# --------------------------------------------------------------------------
# The C++ spec
# --------------------------------------------------------------------------

def _cpp_string(s):
    return json.dumps(s)


def _cpp_double(v):
    return repr(float(v))


class _Arrays:
    """Collects the static arrays MMMSCSpec.h declares, and names them."""

    def __init__(self):
        self.lines, self.n = [], 0

    def add(self, ctype, items):
        if not items:
            return "nullptr"
        self.n += 1
        name = f"a{self.n}"
        if len(items) == 1:
            self.lines.append(f"static const {ctype} {name}[] = {{ {items[0]} }};")
        else:
            self.lines.append(f"static const {ctype} {name}[] = {{\n    " + ",\n    ".join(items) + "\n};")
        return name

    def msg(self, m):
        t = m["type"]
        value = m.get("value")
        values = value if isinstance(value, list) else ([] if value is None else [value])
        floats = ints = flags = strings = "nullptr"
        if t in ("float", "floats"):
            floats = self.add("double", [_cpp_double(v) for v in values])
        elif t in ("int", "ints"):
            ints = self.add("int64_t", [f"INT64_C({int(round(float(v)))})" for v in values])
        elif t in ("bool", "bools", "trigs"):
            flags = self.add("uint8_t", ["1" if v else "0" for v in values])
        elif t in ("string", "strings"):
            strings = self.add("char*", [_cpp_string(str(v)) for v in values])
        enum = {"float": "Float", "floats": "Floats", "int": "Int", "ints": "Ints", "bool": "Bool",
                "bools": "Bools", "trig": "Trig", "trigs": "Trigs", "string": "String",
                "strings": "Strings"}[t]
        count = 0 if t == "trig" else len(values)
        return f"{{ MsgType::{enum}, {_cpp_string(m['key'])}, {count}, {floats}, {ints}, {flags}, {strings} }}"

    def msgs(self, msgs):
        return self.add("Msg", [self.msg(m) for m in msgs]), len(msgs)


def _spec_header(name, num_in, num_out, controls, spec, graph_lib_name, bridge_lib_name, runtime_libs):
    arrays = _Arrays()
    init, num_init = arrays.msgs(spec.get("init", []))

    send_types = {"float": "Float", "int": "Int", "int_round": "IntRound", "bool": "Bool", "list": "ListElement"}
    items = []
    for c in controls:
        sends = arrays.add("Send", [
            f"{{ SendType::{send_types[s['type']]}, {_cpp_string(s['key'])}, {s.get('list', 0)}, {s.get('index', 0)} }}"
            for s in c["sends"]])
        states = arrays.add("MsgList", ["{{ {}, {} }}".format(*arrays.msgs(st)) for st in c["states"]])
        kind = {"value": "Value", "state": "State", "trigger": "Trigger"}[c["kind"]]
        items.append(f"{{ {_cpp_string(c['name'])}, ControlKind::{kind}, {sends}, {len(c['sends'])}, "
                     f"{states}, {len(c['states'])} }}")
    controls_array = arrays.add("Control", items)

    lists = spec.get("lists", [])
    lists_array = arrays.add("ListInit", [
        f"{{ {_cpp_string(l['key'])}, {len(l['values'])}, {arrays.add('double', [_cpp_double(v) for v in l['values']])} }}"
        for l in lists])

    runtime = ", ".join(_cpp_string(n) for n in runtime_libs) or "nullptr"
    body = "\n".join(arrays.lines)
    return f"""\
// Generated by Exporters/SCExporter/export_sc.py - do not edit.
#pragma once

#include "MMMSCTypes.h"

namespace MMMSC {{

static constexpr const char* name = {_cpp_string(name)};
static constexpr int numIn = {num_in};
static constexpr int numOut = {num_out};
static constexpr const char* bridgeLib = {_cpp_string(bridge_lib_name)};
static constexpr const char* graphLib = {_cpp_string(graph_lib_name)};
static constexpr const char* runtimeLibs[] = {{ {runtime} }};
// The folder, beside this UGen's, that holds runtimeLibs.
static constexpr const char* sharedLibDir = {_cpp_string(SHARED_LIBS)};

{body}

// Sent once the graph is built.
static const Msg* const initMsgs = {init};
static constexpr int numInitMsgs = {num_init};

// The control-rate inputs, after the audio inputs.
static const Control* const controls = {controls_array};
static constexpr int numControls = {len(controls)};

static const ListInit* const lists = {lists_array};
static constexpr int numLists = {len(lists)};

}} // namespace MMMSC
"""


# --------------------------------------------------------------------------
# sclang
# --------------------------------------------------------------------------

def _sc_number(v):
    v = float(v)
    s = f"{v:.10g}"
    return f"({s})" if v < 0 else s


def _sc_class(name, origin, num_in, num_out, controls, notes, audio_args=None):
    if audio_args is not None:
        args = [f"{a['name']} = {_sc_number(a['default'] or 0)}" for a in audio_args]
    else:
        args = [] if num_in == 0 else ["in"]
    args += [f"{c['name']} = {_sc_number(c['default'])}" for c in controls]
    args.append("id = \\mmm")
    control_list = ", ".join(c["name"] for c in controls)
    if audio_args:
        # A one-channel argument given an array expands into several UGens, as usual.
        ins = " ++ ".join(f"[mmmAudioRate.({a['name']})]" if a["channels"] == 1 else
                          f"{a['name']}.asArray.wrapExtend({a['channels']}).collect(mmmAudioRate)"
                          for a in audio_args)
        build = ("var mmmAudioRate = { |x| x.asArray.collect { |c| if(c.rate == \\audio) { c } { K2A.ar(c) } }.unbubble };\n"
                 f"\t\t^this.multiNewList(['audio', id] ++ {ins}"
                 + (f" ++ [{control_list}])" if controls else ")"))
    elif num_in:
        build = (f"var ins = (in ? 0).asArray.wrapExtend({num_in}).collect {{ |x| if(x.rate == \\audio) {{ x }} {{ K2A.ar(x) }} }};\n"
                 f"\t\t^this.multiNewList(['audio', id] ++ ins ++ [{control_list}])")
    else:
        build = f"^this.multiNewList(['audio', id, {control_list}])"

    if audio_args is not None:
        docs = [f"//   {a['name']}: audio rate, {a['doc']}" for a in audio_args]
    else:
        docs = [f"//   in: {num_in} audio channel{'s' if num_in != 1 else ''}"] if num_in else []
    docs += [f"//   {c['name']}: {c['doc']}" for c in controls]
    docs.append("//   id: names this UGen, for the send methods, when a SynthDef has more than one")
    note_lines = "".join(f"// {line}\n" for n in notes for line in textwrap.wrap(n, 90))

    return f"""\
// Generated by Exporters/SCExporter/export_sc.py from the MMMAudio {origin[0]} {origin[1]} - do not edit.
//
// {name}.ar arguments (controls are read once per block):
{chr(10).join(docs)}
//
// Send any other message to a running Synth with the class methods: {name}.sendFloat(synth,
// "key", 1.0), sendFloats, sendInt, sendInts, sendBool, sendBools, sendTrig, sendTrigs,
// sendString and sendStrings. Add `id: \\name` if the SynthDef has more than one {name}.
{note_lines}
{name} : MultiOutUGen {{
	classvar ugenIndices; // SynthDef name -> (id -> the UGen's index), for SynthDefs built in this session
	var <id;

	*ar {{ |{', '.join(args)}|
		{build}
	}}

	init {{ |argID ... theInputs|
		id = argID.asSymbol;
		inputs = theInputs;
		^this.initOutputs({num_out}, rate)
	}}

	// Remember where this UGen ends up in its SynthDef, for the send methods. (This is
	// also called when the UGen is first added, before init has set id.)
	synthIndex_ {{ |index|
		var defName;
		super.synthIndex_(index);
		if(id.notNil and: {{ synthDef.notNil and: {{ synthDef.name.notNil }} }}) {{
			defName = synthDef.name.asSymbol;
			ugenIndices = ugenIndices ?? {{ IdentityDictionary() }};
			ugenIndices[defName] = ugenIndices[defName] ?? {{ IdentityDictionary() }};
			ugenIndices[defName][id] = index;
			synthDef.metadata = synthDef.metadata ?? {{ () }};
			synthDef.metadata[\\{name}] = synthDef.metadata[\\{name}] ?? {{ () }};
			synthDef.metadata[\\{name}][id] = index;
		}};
	}}

	*sendFloat {{ |synth, key, value, id = \\mmm| this.prSend(synth, id, \\float, key, value.asFloat) }}
	*sendFloats {{ |synth, key, values, id = \\mmm| this.prSend(synth, id, \\floats, key, *values.asArray.collect(_.asFloat)) }}
	*sendInt {{ |synth, key, value, id = \\mmm| this.prSend(synth, id, \\int, key, value.asInteger) }}
	*sendInts {{ |synth, key, values, id = \\mmm| this.prSend(synth, id, \\ints, key, *values.asArray.collect(_.asInteger)) }}
	*sendBool {{ |synth, key, value, id = \\mmm| this.prSend(synth, id, \\bool, key, this.prFlag(value)) }}
	*sendBools {{ |synth, key, values, id = \\mmm| this.prSend(synth, id, \\bools, key, *values.asArray.collect {{ |v| this.prFlag(v) }}) }}
	*sendTrig {{ |synth, key, id = \\mmm| this.prSend(synth, id, \\trig, key) }}
	*sendTrigs {{ |synth, key, values, id = \\mmm| this.prSend(synth, id, \\trigs, key, *values.asArray.collect {{ |v| this.prFlag(v) }}) }}
	*sendString {{ |synth, key, value, id = \\mmm| this.prSend(synth, id, \\string, key, value.asString) }}
	*sendStrings {{ |synth, key, values, id = \\mmm| this.prSend(synth, id, \\strings, key, *values.asArray.collect(_.asString)) }}

	// The UGen's index in `synth`'s SynthDef, which unit commands are addressed to.
	*ugenIndex {{ |synth, id = \\mmm|
		var defName = synth.defName.asSymbol, index, desc;
		id = id.asSymbol;
		index = ugenIndices !? {{ ugenIndices[defName] !? {{ ugenIndices[defName][id] }} }};
		index = index ?? {{
			desc = SynthDescLib.global[defName];
			desc !? {{ desc.metadata !? {{ desc.metadata[\\{name}] !? {{ desc.metadata[\\{name}][id] }} }} }}
		}};
		index ?? {{ Error("{name}: SynthDef '%' has no {name} with id '%'".format(defName, id)).throw }};
		^index
	}}

	*prFlag {{ |value| ^if(value.isKindOf(Boolean)) {{ value.binaryValue }} {{ value.asInteger }} }}

	*prSend {{ |synth, id, cmd, key ... values|
		synth.server.sendMsg('/u_cmd', synth.nodeID, this.ugenIndex(synth, id), cmd, key.asString, *values)
	}}
}}
"""


def _sc_float(v):
    s = _sc_number(v)
    return s if any(ch in s for ch in ".en") else s.replace(")", ".0)") if s.endswith(")") else s + ".0"


def _sc_value(c):
    """sclang code for a value in the control's range: a random one, warped as the
    GUI's slider is, or its default when the range isn't known."""
    if c["kind"] == "trigger":
        return "1"
    if c["kind"] == "state":
        return f"{len(c['states'])}.rand" if len(c["states"]) > 1 else _sc_number(c["default"])
    is_int = any(s["type"] in ("int", "int_round") for s in c["sends"])
    if any(s["type"] == "bool" for s in c["sends"]) and not is_int:
        return "2.rand"
    if "range" not in c:
        return _sc_number(c["default"])
    lo, hi, exp = c["range"]
    if is_int:
        lo, hi = round(lo), round(hi)
    if exp == 1:
        # rrand with two integers gives an integer, so a float range ends in a float.
        return f"rrand({_sc_number(lo)}, {_sc_number(hi) if is_int else _sc_float(hi)})"
    value = f"1.0.rand.pow({_sc_number(exp)}).linlin(0, 1, {_sc_number(lo)}, {_sc_number(hi)})"
    return value + ".round" if is_int else value


def _sc_struct_example(name, num_out, audio_args, messages=()):
    """The help file's example for a struct's UGen: every argument at its default, and a
    test signal for those without one, then how to send each message the struct reads."""
    signal = "Decay2.ar(Impulse.ar(1), 0.01, 0.3) * PinkNoise.ar"
    ugen_args = [f"{a['name']}: {signal if a['default'] is None else _sc_number(a['default'])}"
                 for a in audio_args]
    call = f"{name}.ar({', '.join(ugen_args)})"
    if len(call) > 70:
        call = f"{name}.ar(\n\t\t" + ",\n\t\t".join(ugen_args) + "\n\t)"
    out = {1: " ! 2", 2: ""}.get(num_out, ".sum ! 2")
    return "\n".join(["s.boot;", "",
                      "// Every argument is audio rate: pass a signal, or a number.",
                      "(",
                      "x = {",
                      f"\tvar sig = {call};",
                      f"\tsig * 0.1{out}",
                      "}.play;",
                      ")", ""]
                     + (["// The messages it reads:"] + [_sc_send_line(name, k, send) for k, send in messages]
                        + [""] if messages else [])
                     + ["x.free;"])


def _sc_send_line(name, key, send):
    """An example line sending the message `key` with the class method `send`."""
    values = {"sendFloat": "0.5", "sendInt": "1", "sendBool": "true", "sendString": '"text"',
              "sendFloats": "[0.25, 0.5]", "sendInts": "[1, 2]", "sendBools": "[true, false]",
              "sendStrings": '["a", "b"]'}
    if send is None:
        return f'// {name}.sendFloat(x, "{key}", value);  // or sendInt, sendString...: the type it reads'
    if send == "sendTrig":
        return f'{name}.sendTrig(x, "{key}");'
    return f'{name}.{send}(x, "{key}", {values[send]});'


def _sc_example(name, num_in, controls):
    """The help file's example: a SynthDef with every input, and a line that sets them all."""
    # Triggers are `t_` arguments, which go back to 0 after the block they are set in.
    arg = {c["name"]: ("t_" if c["kind"] == "trigger" else "") + c["name"] for c in controls}
    def_args = ["out = 0"] + [f"{arg[c['name']]} = {_sc_number(c['default'])}" for c in controls]
    ugen_args = (["SoundIn.ar([0, 1])"] if num_in else []) + [f"{c['name']}: {arg[c['name']]}" for c in controls]
    call = f"{name}.ar({', '.join(ugen_args)})"
    if len(call) > 80:
        call = f"{name}.ar(\n\t\t" + ",\n\t\t".join(ugen_args) + "\n\t)"
    lines = ["s.boot;", "", "(",
             f"SynthDef(\\{name}, {{ |{', '.join(def_args)}|",
             f"\tvar sig = {call};",
             "\tOut.ar(out, sig);",
             "}).add;", ")", "",
             f"x = Synth(\\{name});"]
    if controls:
        lines += ["", "// Set every argument to a value in its range (random ones, for the GUI's sliders):"]
        pairs = [f"\\{arg[c['name']]}, {_sc_value(c)}" for c in controls]
        one_line = f"x.set({', '.join(pairs)});"
        if len(one_line) <= 100:
            lines.append(one_line)
        else:
            width = max(len(p) for p in pairs) + 1
            lines += ["(", "x.set("] + [f"\t{(p + (',' if i < len(pairs) - 1 else '')).ljust(width)} // {c['doc']}"
                                        for i, (p, c) in enumerate(zip(pairs, controls))] + [");", ")"]
    lines += ["", "// Send any message, as MMMAudio.py's send_* methods do:",
              f"{name}.sendFloat(x, \"key\", 1.0);", f"{name}.sendString(x, \"key\", \"text\");",
              "", "x.free;"]
    return "\n".join(lines)


def _schelp_text(text):
    """Prose for a .schelp file: `::` would start or end a tag."""
    return text.replace("::", "\\::")


def _help_arg(c):
    """A .schelp description of a control input."""
    def keys(names):
        names = [f"code::{k}::" for k in dict.fromkeys(names)]
        return ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else names[0]

    if c["kind"] == "trigger":
        return (f"A trigger: when it goes from 0 or less to above 0, it sends "
                f"{keys(m['key'] for m in c['states'][0])}. In a SynthDef, a code::t_:: argument "
                "does this for each code::set::.")
    if c["kind"] == "state":
        return f"A state ({_schelp_text(c['doc'])}): sends what the GUI sends for it."
    sent = {"float": "a float", "int": "an integer", "int_round": "an integer (rounded)",
            "bool": "a bool (true at 0.5 and above)"}
    sends = "; ".join(f"element {s['index']} of the float list {keys([s['key']])}" if s["type"] == "list"
                      else f"{sent[s['type']]} as {keys([s['key']])}" for s in c["sends"])
    if "range" in c:
        return f"{c['range'][0]:g} to {c['range'][1]:g}. Sends {sends}."
    return f"Sends {sends}."


def _sc_help(name, origin, num_in, num_out, controls, notes, audio_args=None, struct_info=None):
    """HelpSource/Classes/<name>.schelp, in SuperCollider's help format (SCDoc)."""
    t = _schelp_text
    send_methods = [
        ("sendFloat", "a float", "value", "A number."),
        ("sendFloats", "a list of floats", "values", "An array of numbers."),
        ("sendInt", "an int", "value", "A number, made an integer."),
        ("sendInts", "a list of ints", "values", "An array of numbers, made integers."),
        ("sendBool", "a bool", "value", "code::true::, code::false::, or a number (0 is false)."),
        ("sendBools", "a list of bools", "values", "An array of booleans or numbers."),
        ("sendTrig", "a trigger", None, None),
        ("sendTrigs", "a list of triggers", "values", "An array of booleans or numbers: which triggers fire."),
        ("sendString", "a string", "value", "A string. Numbers are sent as text."),
        ("sendStrings", "a list of strings", "values", "An array of strings."),
    ]
    kind, path = origin
    plural = lambda n, word: f"{n} {word}{'s' if n != 1 else ''}"
    lines = [f"TITLE:: {name}",
             f"summary:: The MMMAudio {kind} {path} as a UGen",
             "categories:: UGens>MMMAudio",
             "",
             "DESCRIPTION::"]
    if audio_args is not None:
        struct, method = struct_info["struct"], struct_info["method"]
        lines += [(f"The MMMAudio struct code::{path}::'s code::{method}:: method, exported by MMMAudio's "
                   "SCExporter. Each argument is an argument of the method, at audio rate: numbers and "
                   f"control-rate signals are made audio rate. It has {plural(num_out, 'output')}.")
                  if audio_args else
                  (f"The MMMAudio struct code::{path}::'s code::{method}:: method, exported by MMMAudio's "
                   f"SCExporter. It has no inputs, and {plural(num_out, 'output')}."),
                  ""]
        params = [t(f"{struct}'s parameters: {struct_info['params']}.") if struct_info["params"]
                  else f"{struct} has no parameters."]
        if struct_info["method_params"]:
            params.append(t(f"{method}'s parameters: {struct_info['method_params']}."))
        lines += [" ".join(params)]
        if struct_info["messages"]:
            lines += ["", f"It reads these messages: {', '.join(f'code::{k}::' for k, _ in struct_info['messages'])}. "
                      "Send them to a running Synth with the class methods, like "
                      "link::#*sendString#sendString::."]
        lines += ["",
                  "Each Synth builds its own copy on the server's non-real-time thread, and outputs silence "
                  "until it is ready."]
    else:
        lines += [f"The MMMAudio graph code::{path}::, exported by MMMAudio's SCExporter. "
                  + (f"It processes {plural(num_in, 'audio input')} into "
                     if num_in else "It is an instrument with no audio inputs, and has ")
                  + f"{plural(num_out, 'output')}.",
                  "",
                  "The values the graph's GUI sends (its sliders, check boxes and buttons), and the "
                  "numbers and triggers the graph reads with a Messenger, are control-rate inputs. They are "
                  "read once per block and sent to the graph when they change. Any other message is sent to a "
                  "running Synth with the class methods, like link::#*sendString#sendString::.",
                  "",
                  "Each Synth builds its own graph on the server's non-real-time thread, and outputs silence "
                  "until it is ready. Messages sent right after the Synth is created reach the new graph."]
    if notes:
        lines += ["", "The export left these out:", "list::"] + [f"## {t(n)}" for n in notes] + ["::"]
    lines += ["", "CLASSMETHODS::", "", "METHOD:: ar"]
    for a in audio_args or []:
        default = "none (0)" if a["default"] is None else _sc_number(a["default"])
        channels = (f" {a['channels']} channels: a shorter array is repeated to fill them."
                    if a["channels"] > 1 else "")
        lines += [f"ARGUMENT:: {a['name']}", t(f"Audio rate. {a['doc']}.") + channels + f" Default: {default}."]
    if num_in and audio_args is None:
        lines += ["ARGUMENT:: in",
                  f"The audio input: {num_in} channel{'s' if num_in != 1 else ''}. A shorter array is "
                  "repeated to fill them, and a control-rate signal is made audio rate."]
    for c in controls:
        lines += [f"ARGUMENT:: {c['name']}", _help_arg(c) + f" Default: {_sc_number(c['default'])}."]
    lines += ["ARGUMENT:: id",
              f"A name for this UGen, for the send methods, when a SynthDef has more than one {name}.",
              f"returns:: An array of {num_out} audio channels." if num_out != 1 else "returns:: An audio channel."]
    # A struct without a Messenger reads no messages, so its UGen's send methods are left out.
    sends = audio_args is None or bool(struct_info["messages"])
    for method, what, value, value_doc in (send_methods if sends else []):
        lines += ["", f"METHOD:: {method}",
                  f"Sends {what} to the graph in a running Synth, as MMMAudio.py's code::send_"
                  f"{method[4:].lower()}:: does.",
                  "ARGUMENT:: synth", f"The link::Classes/Synth:: running a SynthDef with a {name}.",
                  "ARGUMENT:: key", "The message's name, a String or Symbol."]
        if value:
            lines += [f"ARGUMENT:: {value}", value_doc]
        lines += ["ARGUMENT:: id", f"The {name}'s code::id::, when the SynthDef has more than one."]
    if sends:
        lines += ["", "METHOD:: ugenIndex",
                  f"The {name}'s index in the Synth's SynthDef, which the send methods address their "
                  "code::/u_cmd:: messages to. It is found for SynthDefs built in this session, or "
                  "loaded from a file with their metadata.",
                  "ARGUMENT:: synth", f"The link::Classes/Synth:: running a SynthDef with a {name}.",
                  "ARGUMENT:: id", f"The {name}'s code::id::."]
    private = ["prFlag", "prSend"] + ([] if sends else [m[0] for m in send_methods] + ["ugenIndex"])
    lines += ["",
              "PRIVATE:: " + ", ".join(private),
              "",
              "INSTANCEMETHODS::",
              "",
              "METHOD:: id",
              "The code::id:: this UGen was made with.",
              "",
              "PRIVATE:: init, synthIndex",
              "",
              "EXAMPLES::",
              "",
              "code::",
              _sc_example(name, num_in, controls) if audio_args is None else
              _sc_struct_example(name, num_out, audio_args, struct_info["messages"]),
              "::",
              ""]
    return "\n".join(lines)


# --------------------------------------------------------------------------
# CMake and README
# --------------------------------------------------------------------------

CMAKE_TEMPLATE = """\
# Generated by Exporters/SCExporter/export_sc.py - do not edit.
# Everything it needs is in this folder, in ../{shared_libs} (the Mojo runtime), or downloaded.
cmake_minimum_required(VERSION 3.20)
project({name} CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "")

# Only SuperCollider's plug-in headers are used. They are downloaded on the
# first configure, unless SC_PATH names a SuperCollider source folder.
set(SC_PATH "" CACHE PATH "A SuperCollider source folder (with include/plugin_interface)")
if(NOT SC_PATH)
    include(FetchContent)
    # SOURCE_SUBDIR has no CMakeLists.txt, so this only downloads.
    FetchContent_Declare(supercollider URL {sc_url} SOURCE_SUBDIR include
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_MakeAvailable(supercollider)
    set(SC_PATH "${{supercollider_SOURCE_DIR}}")
endif()

add_library({name} MODULE "${{CMAKE_CURRENT_SOURCE_DIR}}/src/MMMUGen.cpp")
target_include_directories({name} PRIVATE
    "${{CMAKE_CURRENT_SOURCE_DIR}}/src"
    "${{SC_PATH}}/include/plugin_interface"
    "${{SC_PATH}}/include/common")
# Only the server's entry points are exported, so several of these plug-ins can be
# loaded into one server without sharing code.
set_target_properties({name} PROPERTIES PREFIX "" SUFFIX "{scx_ext}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_link_libraries({name} PRIVATE ${{CMAKE_DL_LIBS}})

# After each build, put the extension together in build/{name}/: the plug-in, its
# class, and (in "ignore", which SuperCollider skips) the Mojo libraries and the
# files the graph loads.
set(EXTENSION_DIR "${{CMAKE_BINARY_DIR}}/{name}")
add_custom_command(TARGET {name} POST_BUILD
    COMMAND "${{CMAKE_COMMAND}}" -E rm -rf "${{EXTENSION_DIR}}"
    COMMAND "${{CMAKE_COMMAND}}" -E copy_directory "${{CMAKE_CURRENT_SOURCE_DIR}}/sc" "${{EXTENSION_DIR}}"
    COMMAND "${{CMAKE_COMMAND}}" -E copy "$<TARGET_FILE:{name}>" "${{EXTENSION_DIR}}/"
    COMMAND "${{CMAKE_COMMAND}}" -E copy_directory "${{CMAKE_CURRENT_SOURCE_DIR}}/bundle/libs" "${{EXTENSION_DIR}}/ignore"
    COMMAND "${{CMAKE_COMMAND}}" -E copy_directory "${{CMAKE_CURRENT_SOURCE_DIR}}/bundle/resources" "${{EXTENSION_DIR}}/ignore/resources"
    VERBATIM)

# `cmake --install build` replaces build/{name}/'s copy in {mojo_dir}/ in the MMMAudio
# folder of the user Extensions folder, creating those folders if they aren't there, and
# puts the Mojo runtime, which all UGens built with this Mojo version share, in
# {mojo_dir}/{shared_libs}/.
set(SC_EXTENSIONS_DIR "{install_dir}" CACHE PATH "The folder cmake --install puts the extension in")
set(MMM_SHARED_LIBS "${{CMAKE_CURRENT_SOURCE_DIR}}/../{shared_libs}" CACHE PATH
    "The folder holding the Mojo runtime libraries")
install(CODE "file(REMOVE_RECURSE \\"${{SC_EXTENSIONS_DIR}}/{mojo_dir}/{name}\\")")
install(DIRECTORY "${{EXTENSION_DIR}}" DESTINATION "${{SC_EXTENSIONS_DIR}}/{mojo_dir}" USE_SOURCE_PERMISSIONS)
foreach(lib {runtime_libs})
    install(PROGRAMS "${{MMM_SHARED_LIBS}}/${{lib}}" DESTINATION "${{SC_EXTENSIONS_DIR}}/{mojo_dir}/{shared_libs}")
endforeach()
"""

README_TEMPLATE = """\
# {name}

Generated by `Exporters/SCExporter/export_sc.py`. It is replaced on every export, so don't edit it.

A CMake project for a SuperCollider UGen running the MMMAudio {origin}, built with
{mojo_dir}. It uses the Mojo runtime libraries in `../{shared_libs}/`, which every UGen built
with this Mojo version shares. You can move it, with its parent folder or wherever
you point `-DMMM_SHARED_LIBS=...` at those libraries; it doesn't need the MMMAudio
repository to build. Run the commands below from this folder.

Needs CMake 3.20 or newer and a C++17 compiler (on macOS, Xcode's command line tools).
Inside the MMMAudio repository, `pixi run cmake ...` uses the pixi environment's CMake.

## Build

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE={config}
cmake --build build --config {config}
```

The first command downloads SuperCollider's plug-in headers, unless you point it at a
SuperCollider source folder with `-DSC_PATH=/path/to/supercollider`. After moving this
folder, delete `build/` first.

The extension is put together in `build/{name}/`.

## Install

```sh
cmake --install build --config {config}
```

This copies `build/{name}/` to `{install_dir}/{mojo_dir}/{name}`, replacing any earlier copy
there, and the Mojo runtime libraries to `{install_dir}/{mojo_dir}/{shared_libs}/` (configure
with `-DSC_EXTENSIONS_DIR=...` to install somewhere else). The UGen loads them from there, so
copy both if you install by hand. Remove any copy of {name} built with another Mojo version.
Then recompile the class library and reboot the server.

## What's in here

- `src/`: the UGen's C++. `MMMSCSpec.h` describes this graph's inputs and setup messages.
- `sc/`: the UGen's sclang class (`Classes/{name}.sc`) and help file
  (`HelpSource/Classes/{name}.schelp`), which has an example.
- `bundle/`: the compiled Mojo graph and its engine, plus files the graph loads.

Changes to the Mojo code, the Qt GUI script, or files the graph loads need a new
export, from the MMMAudio folder:

```sh
{export_command}
```
"""


def _export_command(graph_name, package_name, gui_file, ugen_name, instrument, num_in, num_out,
                    resources, config):
    """The command line that repeats this export, run from the MMMAudio folder."""
    def rel(p):
        try:
            return Path(p).resolve().relative_to(REPO_ROOT).as_posix()
        except ValueError:
            return Path(p).resolve().as_posix()
    cmd = ["pixi run python Exporters/SCExporter/export_sc.py", f"--graph_name {graph_name}",
           f"--package_name {package_name}"]
    if gui_file:
        cmd.append(f"--gui_file {rel(gui_file)}")
    if ugen_name:
        cmd.append(f"--ugen_name {ugen_name}")
    cmd.append("--instrument" if instrument else f"--effect --num_in {num_in}")
    cmd.append(f"--num_out {num_out}")
    if resources:
        cmd.append("--resources " + " ".join(rel(r) for r in resources))
    if config != "Release":
        cmd.append(f"--config {config}")
    return " \\\n    ".join(cmd)


def main():
    parser = argparse.ArgumentParser(
        description="Export an MMMAudio graph, or one struct (--struct), as a SuperCollider UGen.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            example, from the MMMAudio folder:
              pixi run python Exporters/SCExporter/export_sc.py \\
                  --graph_name FM4 --package_name examples \\
                  --gui_file examples/FM4.py --install
              pixi run python Exporters/SCExporter/export_sc.py --struct Freeverb --install"""))
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument("--graph_name", help="the graph to export, as for MMMAudio")
    what.add_argument("--struct", help="a struct to export instead, like Osc: its next() arguments become "
                                       "audio-rate inputs")
    parser.add_argument("--package_name", help="the folder holding the graph (default: the GUI script's, else examples)")
    parser.add_argument("--gui_file", help="an MMMAudio Qt GUI script whose controls become control-rate inputs")
    parser.add_argument("--ugen_name", help="the UGen's class name (default: graph_name, capitalized)")
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--instrument", action="store_true", default=None, help="no audio inputs")
    kind.add_argument("--effect", dest="instrument", action="store_false", help="audio inputs")
    parser.add_argument("--num_in", type=int, help="audio inputs (effects only)")
    parser.add_argument("--num_out", type=int, help="outputs")
    parser.add_argument("--resources", nargs="+", default=[],
                        help="extra files or folders to bundle (files the graph names are found automatically)")
    parser.add_argument("--install", action="store_true", help="copy into the MMMAudio folder of the user Extensions folder")
    parser.add_argument("--install_dir", help="install into this folder instead (implies --install)")
    parser.add_argument("--config", default="Release", choices=["Release", "Debug"])
    parser.add_argument("--no_build", dest="build", action="store_false",
                        help="only write the project into builds/Mojo<version>/<Name>/; build it later "
                             "with its README's commands")
    parser.add_argument("--sc_path", help="a SuperCollider source folder to take the plug-in headers from")
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
    args = parser.parse_args()

    if args.struct:
        pairs = lambda items: dict(i.split("=", 1) for i in items)
        export_struct_sc(args.struct, args.module, ugen_name=args.ugen_name, method=args.method,
                         params=pairs(args.params), method_params=pairs(args.method_params),
                         init_args=pairs(args.init_args), install=args.install,
                         config=args.config, build=args.build, sc_path=args.sc_path,
                         install_dir=args.install_dir)
        return

    export_sc(args.graph_name, args.package_name, args.gui_file, ugen_name=args.ugen_name,
              instrument=args.instrument, num_in=args.num_in, num_out=args.num_out,
              resources=args.resources, install=args.install, config=args.config, build=args.build,
              sc_path=args.sc_path, install_dir=args.install_dir)


if __name__ == "__main__":
    main()
