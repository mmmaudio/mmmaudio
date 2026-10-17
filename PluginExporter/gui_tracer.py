"""Runs an MMMAudio Qt GUI script with stand-ins for PySide6 and MMMAudio and
describes what it built, so it can be rebuilt as a JUCE plugin editor.

    python gui_tracer.py path/to/Gui.py out.json

Nothing real is started: `MMMAudio` records the messages it is asked to send,
and the Qt classes record the widgets, layouts and signal connections. After
the script has run (its `app.exec()` returns straight away), every connected
callback is called with probe values to find out which messages it sends.

The output JSON holds:
    mmm_audio:  the arguments `MMMAudio(...)` was constructed with
    title, width, height: from the main window
    params:     host-automatable parameters (sliders, check boxes, combo boxes, XY pads)
    lists:      list messages that parameters fill in one element each (an XY pad sending [x, y])
    init:       messages the script sends during setup that no control owns
    layout:     a tree of vbox/hbox/param/label/button/file/xy nodes
    warnings:   anything that could not be translated
"""

import json
import math
import re
import runpy
import sys
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

WARNINGS = []


def warn(msg):
    WARNINGS.append(msg)


# --------------------------------------------------------------------------
# Message recording
# --------------------------------------------------------------------------

class Recorder:
    """Collects messages sent through the fake MMMAudio. `probe()` swaps in a
    fresh list so a callback's messages can be captured on their own."""

    def __init__(self):
        self.current = []
        self.setup = self.current
        self.dialogs = []      # file dialogs opened by the current probe
        self.set_values = []   # (Handle, value) set by the current probe

    def probe(self, fn, *args):
        saved = self.current
        self.current, self.dialogs, self.set_values = [], [], []
        try:
            fn(*args)
            return self.current, self.dialogs, self.set_values, None
        except Exception as e:  # the callback relies on something we don't fake
            return self.current, self.dialogs, self.set_values, e
        finally:
            self.current = saved


REC = Recorder()
FILE_SENTINEL = "__MMM_PLUGIN_FILE__"


def _msg(kind, key, value=None):
    m = {"type": kind, "key": str(key)}
    if value is not None:
        m["value"] = value
    REC.current.append(m)


class FakeMMMAudio:
    instances = []
    ctor_args = None

    def __init__(self, blocksize=64, num_input_channels=2, num_output_channels=2,
                 in_device="default", out_device="default", graph_name="FeedbackDelays",
                 package_name="examples", audio_init_timeout=10.0, **_):
        FakeMMMAudio.ctor_args = dict(
            blocksize=blocksize, num_input_channels=num_input_channels,
            num_output_channels=num_output_channels, in_device=in_device,
            out_device=out_device, graph_name=graph_name, package_name=package_name)
        self.sample_rate = types.SimpleNamespace(value=48000)
        FakeMMMAudio.instances.append(self)

    def send_bool(self, key, value): _msg("bool", key, bool(value))
    def send_bools(self, key, values): _msg("bools", key, [bool(v) for v in values])
    def send_float(self, key, value): _msg("float", key, float(value))
    def send_floats(self, key, values): _msg("floats", key, [float(v) for v in values])
    def send_int(self, key, value): _msg("int", key, int(value))
    def send_ints(self, key, values): _msg("ints", key, [int(v) for v in values])
    def send_trig(self, key): _msg("trig", key)
    def send_trigs(self, key, values): _msg("trigs", key, [bool(v) for v in values])

    def send_string(self, key, value):
        _msg("string", key, None if value is None else str(value))

    def send_strings(self, key, values): _msg("strings", key, [str(v) for v in values])

    @classmethod
    def exit_all(cls): pass

    @classmethod
    def get_audio_devices(cls, print_them=True): return ({}, {})

    def __getattr__(self, name):  # start_audio, stop_audio, plot, ...
        return lambda *a, **k: None


# --------------------------------------------------------------------------
# Qt stand-ins
# --------------------------------------------------------------------------

class Signal:
    def __init__(self, *types_, **_):
        self.slots = []

    def connect(self, fn, *_):
        self.slots.append(fn)

    def emit(self, *args):
        for s in self.slots:
            s(*args)

    def disconnect(self, *_):
        self.slots.clear()

    # `Signal(float, float)` declared on a class becomes per-instance
    def __set_name__(self, owner, name):
        self.name = name

    def __get__(self, obj, objtype=None):
        if obj is None:
            return self
        sigs = obj.__dict__.setdefault("_signals", {})
        if self.name not in sigs:
            sigs[self.name] = Signal()
        return sigs[self.name]


class Anything:
    """Swallows any attribute access or call (Qt enums, painters, fonts...)."""

    def __init__(self, *a, **k): pass
    def __getattr__(self, name): return Anything()
    def __call__(self, *a, **k): return Anything()
    def __or__(self, other): return self
    __ror__ = __or__
    def __bool__(self): return False
    def __iter__(self): return iter(())
    def __int__(self): return 0
    def __float__(self): return 0.0
    def __index__(self): return 0


class AnyAttrMeta(type):
    """Class-level Qt constants (`QSlider.TicksBelow`, `QSizePolicy.Expanding`)."""

    def __getattr__(cls, name):
        if name.startswith("__"):
            raise AttributeError(name)
        return Anything()


class QObjectBase(metaclass=AnyAttrMeta):
    _signal_names = ()

    def __init__(self, *args, **kwargs):
        self._signals = {}
        self.layout_ = None
        self.title = None
        self.size = None
        self.min_size = None
        self.shown = False
        self.central = None
        self.checkable = False
        self.checked = False
        self.text = ""

    def _sig(self, name):
        if name not in self._signals:
            self._signals[name] = Signal()
        return self._signals[name]

    def __getattr__(self, name):
        if name.startswith("__"):
            raise AttributeError(name)
        if name in type(self)._signal_names:
            return self._sig(name)
        return lambda *a, **k: None

    # QWidget API the scripts use
    def setLayout(self, layout): self.layout_ = layout
    def layout(self): return self.layout_
    def setWindowTitle(self, t): self.title = str(t)
    def resize(self, w, h=None):
        if h is None and hasattr(w, "__len__"):
            w, h = w
        self.size = (int(w), int(h))
    def setMinimumSize(self, w, h=None): self.min_size = (int(w), int(h))
    def setFixedSize(self, w, h=None): self.min_size = (int(w), int(h))
    def show(self): self.shown = True
    def setCentralWidget(self, w): self.central = w
    def width(self): return (self.size or self.min_size or (300, 300))[0]
    def height(self): return (self.size or self.min_size or (300, 300))[1]


class QWidget(QObjectBase):
    pass


class QMainWindow(QWidget):
    pass


class QGroupBox(QWidget):
    def __init__(self, title="", *a, **k):
        super().__init__()
        self.text = str(title)


class QFrame(QWidget):
    pass


class QLabel(QWidget):
    def __init__(self, text="", *a, **k):
        super().__init__()
        self.text = str(text)

    def setText(self, t): self.text = str(t)


class QAbstractButton(QWidget):
    _signal_names = ("clicked", "pressed", "released", "toggled", "stateChanged",
                     "checkStateChanged")

    def __init__(self, text="", *a, **k):
        super().__init__()
        self.text = str(text) if not isinstance(text, QObjectBase) else ""

    def setText(self, t): self.text = str(t)
    def setCheckable(self, c): self.checkable = bool(c)
    def setChecked(self, c): self.checked = bool(c)
    def isChecked(self): return self.checked


class QPushButton(QAbstractButton):
    pass


class QCheckBox(QAbstractButton):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.checkable = True

    def setCheckState(self, s): self.checked = bool(int(s) if not isinstance(s, Anything) else 0)


class QRadioButton(QCheckBox):
    pass


class QComboBox(QWidget):
    _signal_names = ("currentIndexChanged", "currentTextChanged", "activated", "textActivated")

    def __init__(self, *a, **k):
        super().__init__()
        self.items = []
        self.index = 0

    def addItem(self, t, *a): self.items.append(str(t))
    def addItems(self, ts): self.items.extend(str(t) for t in ts)
    def setCurrentIndex(self, i): self.index = int(i)
    def setCurrentText(self, t):
        if str(t) in self.items:
            self.index = self.items.index(str(t))
    def currentIndex(self): return self.index
    def currentText(self): return self.items[self.index] if self.items else ""


class QAbstractSlider(QWidget):
    _signal_names = ("valueChanged", "sliderMoved", "sliderReleased", "sliderPressed")

    def __init__(self, *a, **k):
        super().__init__()
        self.min, self.max, self.val = 0, 99, 0

    def setMinimum(self, v): self.min = v
    def setMaximum(self, v): self.max = v
    def setRange(self, a, b): self.min, self.max = a, b
    def setValue(self, v): self.val = v
    def value(self): return self.val
    def minimum(self): return self.min
    def maximum(self): return self.max


class QSlider(QAbstractSlider):
    pass


class QDial(QAbstractSlider):
    pass


class QSpinBox(QAbstractSlider):
    pass


class QDoubleSpinBox(QAbstractSlider):
    def __init__(self, *a, **k):
        super().__init__()
        self.max = 99.99


class QLayout:
    def __init__(self, *a, **k):
        self.items = []

    def addWidget(self, w, *a, **k): self.items.append(("widget", w))
    def addLayout(self, l, *a, **k): self.items.append(("layout", l))
    def addStretch(self, *a, **k): pass
    def addSpacing(self, *a, **k): pass
    def __getattr__(self, name):
        if name.startswith("__"):
            raise AttributeError(name)
        return lambda *a, **k: None


class QVBoxLayout(QLayout):
    pass


class QHBoxLayout(QLayout):
    pass


class QGridLayout(QLayout):
    def addWidget(self, w, row=0, col=0, *a, **k): self.items.append(("widget", w, row, col))
    def addLayout(self, l, row=0, col=0, *a, **k): self.items.append(("layout", l, row, col))


class QFormLayout(QLayout):
    def addRow(self, a, b=None):
        if b is None:
            self.items.append(("widget", a) if isinstance(a, QObjectBase) else ("layout", a))
        else:
            if isinstance(a, str):
                a = QLabel(a)
            row = QHBoxLayout()
            row.items = [("widget", a), ("widget" if isinstance(b, QObjectBase) else "layout", b)]
            self.items.append(("layout", row))


class QApplication:
    def __init__(self, *a, **k): pass
    def exec(self): return 0
    exec_ = exec
    @staticmethod
    def instance(): return None
    def __getattr__(self, name): return lambda *a, **k: None
    def __setattr__(self, name, value): pass


class QFileDialog:
    @staticmethod
    def getOpenFileName(*a, **k):
        REC.dialogs.append("open")
        return (FILE_SENTINEL, "")

    @staticmethod
    def getSaveFileName(*a, **k):
        REC.dialogs.append("save")
        return (FILE_SENTINEL, "")

    @staticmethod
    def getExistingDirectory(*a, **k):
        REC.dialogs.append("dir")
        return FILE_SENTINEL


class QTimer(Anything):
    @staticmethod
    def singleShot(*a, **k): pass


# --------------------------------------------------------------------------
# mmm_python.GUI stand-ins
# --------------------------------------------------------------------------

class ControlSpec:
    def __init__(self, min: float = 0.0, max: float = 1.0, exp: float = 1.0):
        self.min, self.max, self.exp = float(min), float(max), float(exp)

    def normalize(self, val):
        n = (val - self.min) / (self.max - self.min)
        return min(max(n, 0.0), 1.0) ** (1.0 / self.exp)

    def unnormalize(self, n):
        return self.min + (min(max(n, 0.0), 1.0) ** self.exp) * (self.max - self.min)


class Handle(QWidget):
    def __init__(self, label, spec=None, default=0.0, callback=None, orientation=None,
                 resolution=1000, display_resolution=2, run_callback_on_init=False):
        super().__init__()
        self.label = str(label)
        self.spec = spec or ControlSpec()
        self.default = float(default)
        self.callback = callback
        self.display_resolution = int(display_resolution)
        self.value = min(max(self.default, self.spec.min), self.spec.max)
        if run_callback_on_init and callback:
            callback(self.value)

    def get_value(self): return self.value

    def set_value(self, value):
        self.value = value
        REC.set_values.append((self, float(value)))
        if self.callback:
            self.callback(value)


class Slider2D(QWidget):
    valueChanged = Signal(float, float)
    pressed = Signal(bool)

    def __init__(self, width=300, height=300, parent=None):
        super().__init__()
        self.min_size = (int(width), int(height))
        self._x = self._y = 0.5

    def get_values(self): return self._x, self._y

    def set_values(self, x, y):
        self._x, self._y = x, y
        self.valueChanged.emit(x, y)


class Unsupported(QWidget):
    kind = "unsupported"


class MPlot(Unsupported):
    kind = "MPlot"


class MWaveform(Unsupported):
    kind = "MWaveform"


# --------------------------------------------------------------------------
# Module installation
# --------------------------------------------------------------------------

def _module(name, attrs, fallback=None):
    """A stand-in module. `fallback(attr_name)` supplies anything not in `attrs`."""
    m = types.ModuleType(name)
    m.__dict__.update(attrs)
    if fallback is not None:
        def __getattr__(attr):
            if attr.startswith("__"):
                raise AttributeError(attr)
            value = fallback(attr)
            setattr(m, attr, value)
            return value
        m.__getattr__ = __getattr__
    sys.modules[name] = m
    return m


def install_fakes():
    widgets = {n: v for n, v in globals().items()
               if isinstance(v, type) and (n.startswith("Q") and n != "QObjectBase")}
    # Unknown widget classes become empty QWidgets the translator reports as skipped.
    qtw = _module("PySide6.QtWidgets", widgets, fallback=lambda n: type(n, (QWidget,), {}))
    qtc = _module("PySide6.QtCore", {"Qt": Anything(), "Signal": Signal, "Slot": lambda *a, **k: (lambda f: f),
                                     "QTimer": QTimer, "QObject": QWidget, "QThread": Anything,
                                     "QPointF": Anything, "QSize": Anything, "QRect": Anything},
                  fallback=lambda n: Anything())
    qtg = _module("PySide6.QtGui", {}, fallback=lambda n: Anything)
    _module("PySide6", {"QtWidgets": qtw, "QtCore": qtc, "QtGui": qtg})
    for alias in ("PyQt6", "PyQt5"):
        _module(alias, {"QtWidgets": qtw, "QtCore": qtc, "QtGui": qtg})
        sys.modules[alias + ".QtWidgets"] = qtw
        sys.modules[alias + ".QtCore"] = qtc
        sys.modules[alias + ".QtGui"] = qtg

    # The real GUI module star-imports Qt widgets, and scripts lean on that
    # through `from mmm_python import *`.
    gui = _module("mmm_python.GUI", {**widgets, "Qt": qtc.Qt, "Signal": Signal,
                                     "ControlSpec": ControlSpec, "Handle": Handle,
                                     "Slider2D": Slider2D, "MPlot": MPlot, "MWaveform": MWaveform})
    mmm = _module("mmm_python.MMMAudio", {"MMMAudio": FakeMMMAudio,
                                         "list_audio_devices": lambda *a, **k: None})

    # The real package's __init__ starts pulling in PySide6, numpy plotting,
    # HID... so build the package namespace by hand from the harmless parts.
    pkg = types.ModuleType("mmm_python")
    pkg.__path__ = [str(REPO_ROOT / "mmm_python")]
    sys.modules["mmm_python"] = pkg
    for sub in ("functions", "Patterns", "constants", "Scheduler", "OSCServer"):
        try:
            mod = __import__(f"mmm_python.{sub}", fromlist=["*"])
            pkg.__dict__.update({k: v for k, v in mod.__dict__.items() if not k.startswith("_")})
        except Exception:
            pass
    for mod in (gui, mmm):
        pkg.__dict__.update({k: v for k, v in mod.__dict__.items() if not k.startswith("__")})
    pkg.GUI = gui
    import asyncio
    pkg.asyncio = asyncio
    pkg.sleep = asyncio.sleep


# --------------------------------------------------------------------------
# Translation
# --------------------------------------------------------------------------

class Builder:
    def __init__(self):
        self.params = []
        self.ids = set()
        self.owned_keys = set()
        self.handle_ids = {}
        self.lists = []

    def new_id(self, base):
        base = re.sub(r"[^A-Za-z0-9_]", "_", base) or "param"
        pid, n = base, 2
        while pid in self.ids:
            pid, n = f"{base}_{n}", n + 1
        self.ids.add(pid)
        return pid

    def add_param(self, p, keys):
        self.params.append(p)
        self.owned_keys.update(keys)
        return p["id"]

    # ---- per-widget ----

    def handle(self, h):
        spec = h.spec
        if h.callback is None:
            warn(f"slider '{h.label}' has no callback; skipped")
            return None
        probes = [spec.min, spec.unnormalize(0.37), spec.max]
        sends = None
        for v in probes:
            msgs, _, _, err = REC.probe(h.callback, v)
            if err is not None:
                warn(f"slider '{h.label}': callback raised {err!r}; skipped")
                return None
            shape = [(m["type"], m["key"]) for m in msgs]
            if sends is None:
                sends = [{"type": t, "key": k, "map": None} for t, k in shape]
            elif [(s["type"], s["key"]) for s in sends] != shape:
                warn(f"slider '{h.label}': sends different messages for different values; skipped")
                return None
            for s, m in zip(sends, msgs):
                if s["type"] not in ("float", "int", "bool"):
                    warn(f"slider '{h.label}': sends a {s['type']} message; skipped")
                    return None
                if s["type"] == "float":
                    mapping = "identity" if math.isclose(m["value"], v, rel_tol=1e-6, abs_tol=1e-9) else None
                elif s["type"] == "int":
                    mapping = "int" if m["value"] == int(v) else ("round" if m["value"] == round(v) else None)
                else:
                    mapping = "bool"
                if mapping is None:
                    warn(f"slider '{h.label}': '{s['key']}' is a function of the slider value "
                         "that can't be translated; sending the raw value")
                    mapping = "identity" if s["type"] == "float" else "int"
                if s["map"] not in (None, mapping):
                    mapping = s["map"]
                s["map"] = mapping
        if not sends:
            warn(f"slider '{h.label}' sends no messages; skipped")
            return None
        pid = self.new_id(sends[0]["key"])
        self.handle_ids[id(h)] = pid
        decimals = 0 if all(s["map"] in ("int", "round") for s in sends) else h.display_resolution
        return self.add_param({
            "id": pid, "name": h.label, "kind": "float",
            "min": spec.min, "max": spec.max, "exp": spec.exp,
            "default": min(max(h.default, spec.min), spec.max),
            "decimals": decimals, "sends": sends,
        }, [s["key"] for s in sends])

    def two_state(self, w, label):
        """Check boxes and checkable buttons: find the messages for on and off."""
        for sig, on, off in (("toggled", (True,), (False,)),
                             ("stateChanged", (2,), (0,)),
                             ("checkStateChanged", (2,), (0,)),
                             ("clicked", (True,), (False,))):
            slots = w._signals.get(sig)
            if not slots or not slots.slots:
                continue
            states = []
            for args in (off, on):
                msgs = []
                for slot in slots.slots:
                    m, _, _, err = REC.probe(slot, *args)
                    if err is not None:
                        m, _, _, err = REC.probe(slot)
                    if err is not None:
                        warn(f"'{label}': callback raised {err!r}; skipped")
                        return None
                    msgs.extend(m)
                states.append(msgs)
            if not states[0] and not states[1]:
                continue
            keys = {m["key"] for s in states for m in s}
            pid = self.new_id(next(iter(sorted(keys))) if keys else label)
            return self.add_param({"id": pid, "name": label, "kind": "bool",
                                   "default": bool(w.checked), "states": states}, keys)
        warn(f"'{label}': no connected callback sends messages; skipped")
        return None

    def push_button(self, w):
        label = w.text or "button"
        if w.checkable:
            pid = self.two_state(w, label)
            return {"type": "param", "param": pid, "widget": "toggle_button"} if pid else None

        node = {"type": "button", "label": label}
        for sig in ("clicked", "pressed", "released"):
            s = w._signals.get(sig)
            if not s or not s.slots:
                continue
            msgs, dialogs, set_values, file_msg = [], [], [], None
            for slot in s.slots:
                m, d, sv, err = REC.probe(slot)
                if err is not None:
                    m, d, sv, err = REC.probe(slot, False)
                if err is not None:
                    warn(f"button '{label}': {sig} callback raised {err!r}; skipped")
                    continue
                msgs += m
                dialogs += d
                set_values += sv
            for m in msgs:
                if m.get("value") == FILE_SENTINEL:
                    file_msg = m
            if file_msg is not None:
                mode = "save" if "save" in dialogs else ("dir" if "dir" in dialogs else "open")
                self.owned_keys.add(file_msg["key"])
                return {"type": "file", "label": label, "key": file_msg["key"],
                        "msg_type": file_msg["type"], "mode": mode}
            if set_values:
                # A button that moves sliders: either always to the same place
                # (a preset) or somewhere random each time.
                again = REC.probe(s.slots[0])[2] or REC.probe(s.slots[0], False)[2]
                ids = [self.handle_ids.get(id(h)) for h, _ in set_values]
                if all(ids):
                    same = len(again) == len(set_values) and all(
                        math.isclose(a[1], b[1]) for a, b in zip(again, set_values))
                    if same:
                        node["set"] = {pid: v for pid, (_, v) in zip(ids, set_values)}
                    else:
                        node["randomize"] = ids
                msgs = [m for m in msgs if m["key"] not in self.owned_keys]
            if msgs:
                node[sig] = msgs
        if len(node) == 2:
            warn(f"button '{label}' does nothing translatable; skipped")
            return None
        return node

    def combo(self, w):
        if not w.items:
            warn("combo box with no items; skipped")
            return None
        for sig, arg in (("currentIndexChanged", "index"), ("activated", "index"),
                         ("currentTextChanged", "text"), ("textActivated", "text")):
            s = w._signals.get(sig)
            if not s or not s.slots:
                continue
            states = []
            for i, t in enumerate(w.items):
                msgs = []
                for slot in s.slots:
                    m, _, _, err = REC.probe(slot, i if arg == "index" else t)
                    if err is not None:
                        warn(f"combo box: callback raised {err!r}; skipped")
                        return None
                    msgs += m
                states.append(msgs)
            keys = {m["key"] for st in states for m in st}
            if not keys:
                continue
            pid = self.new_id(sorted(keys)[0])
            return self.add_param({"id": pid, "name": sorted(keys)[0], "kind": "choice",
                                   "choices": w.items, "default": w.index, "states": states}, keys)
        warn("combo box sends no messages; skipped")
        return None

    def raw_slider(self, w):
        s = w._signals.get("valueChanged")
        if not s or not s.slots:
            warn(f"{type(w).__name__} with no valueChanged callback; skipped")
            return None
        h = Handle(type(w).__name__, ControlSpec(float(w.min), float(w.max), 1.0), float(w.val),
                   callback=lambda v: [slot(type(w.min)(v) if isinstance(w.min, int) else v) for slot in s.slots],
                   display_resolution=0 if isinstance(w.min, int) else 2)
        return self.handle(h)

    def new_list(self, msg, values):
        """A list message that parameters fill in element by element (see slider2d)."""
        self.lists.append({"type": msg["type"], "key": msg["key"], "values": values})
        return len(self.lists) - 1

    def slider2d(self, w):
        node = {"type": "xy", "width": w.min_size[0], "height": w.min_size[1]}
        vc = w._signals.get("valueChanged")
        if vc and vc.slots:
            # Probe with x = 0.25, y = 0.75 and look for those values in what gets sent:
            # either on their own (send_float("x", x)) or inside a list (send_floats("xy", [x, y])).
            probe = {"x": 0.25, "y": 0.75}
            a, _, _, e1 = REC.probe(vc.emit, probe["x"], probe["y"])
            sends = {"x": [], "y": []}
            keys = set()
            defaults = dict(zip(("x", "y"), w.get_values()))
            for m in (a if e1 is None else []):
                v = m.get("value")
                if isinstance(v, list) and m["type"] == "floats":
                    hits = [(axis, i) for i, e in enumerate(v) for axis in probe
                            if isinstance(e, (int, float)) and math.isclose(e, probe[axis])]
                    if not hits:
                        continue
                    values = list(v)
                    for axis, i in hits:
                        values[i] = defaults[axis]
                    li = self.new_list(m, values)
                    for axis, i in hits:
                        sends[axis].append({"type": "list", "list": li, "index": i, "key": m["key"]})
                    keys.add(m["key"])
                elif isinstance(v, (int, float)) and not isinstance(v, bool):
                    for axis in probe:
                        if math.isclose(v, probe[axis]):
                            sends[axis].append({"type": m["type"], "key": m["key"], "map": "identity"})
                            keys.add(m["key"])
            if sends["x"] and sends["y"]:
                for axis in ("x", "y"):
                    key = sends[axis][0]["key"]
                    shared = sends["x"][0]["key"] == sends["y"][0]["key"]
                    name = f"{key} {axis}" if shared else key
                    pid = self.new_id(name)
                    node[axis] = self.add_param({
                        "id": pid, "name": name, "kind": "float", "min": 0.0, "max": 1.0,
                        "exp": 1.0, "default": defaults[axis], "decimals": 3,
                        "sends": sends[axis]}, keys)
            else:
                warn("Slider2D valueChanged callback doesn't send x and y (as floats or in a float list); skipped")
        pr = w._signals.get("pressed")
        if pr and pr.slots:
            off, _, _, e1 = REC.probe(pr.emit, False)
            on, _, _, e2 = REC.probe(pr.emit, True)
            if e1 is None and e2 is None and (on or off):
                keys = {m["key"] for m in on + off}
                pid = self.new_id(sorted(keys)[0])
                node["pressed"] = self.add_param({"id": pid, "name": sorted(keys)[0], "kind": "bool",
                                                  "default": False, "states": [off, on]}, keys)
        return node if ("x" in node or "pressed" in node) else None

    # ---- tree walk ----

    def widget(self, w):
        if isinstance(w, Handle):
            pid = self.handle(w)
            return {"type": "param", "param": pid, "widget": "slider"} if pid else None
        if isinstance(w, Slider2D):
            return self.slider2d(w)
        if isinstance(w, QCheckBox):
            pid = self.two_state(w, w.text or "toggle")
            return {"type": "param", "param": pid, "widget": "toggle"} if pid else None
        if isinstance(w, QPushButton):
            return self.push_button(w)
        if isinstance(w, QComboBox):
            pid = self.combo(w)
            return {"type": "param", "param": pid, "widget": "combo"} if pid else None
        if isinstance(w, QAbstractSlider):
            pid = self.raw_slider(w)
            return {"type": "param", "param": pid, "widget": "slider"} if pid else None
        if isinstance(w, QLabel):
            text = w.text
            bold = bool(re.search(r"<(b|strong|h\d)>", text, re.I))
            text = re.sub(r"<[^>]+>", "", text).strip()
            return {"type": "label", "text": text, "bold": bold} if text else None
        if isinstance(w, Unsupported):
            warn(f"{w.kind} widgets aren't supported in plugins; skipped")
            return None
        if isinstance(w, QMainWindow) and w.central is not None:
            return self.widget(w.central)
        if w.layout_ is not None:
            node = self.layout(w.layout_)
            if node and isinstance(w, QGroupBox) and w.text:
                node["children"].insert(0, {"type": "label", "text": w.text, "bold": True})
            return node
        if type(w) not in (QWidget, QFrame):
            warn(f"{type(w).__name__} isn't supported; skipped")
        return None

    def layout(self, l):
        if isinstance(l, QGridLayout):
            rows = {}
            for item in l.items:
                rows.setdefault(item[2], []).append(item)
            children = []
            for r in sorted(rows):
                row = QHBoxLayout()
                row.items = [it[:2] for it in sorted(rows[r], key=lambda it: it[3])]
                children.append(self.layout(row))
            return {"type": "vbox", "children": [c for c in children if c]}
        kind = "hbox" if isinstance(l, QHBoxLayout) else "vbox"
        children = []
        for item in l.items:
            node = self.widget(item[1]) if item[0] == "widget" else self.layout(item[1])
            if node:
                children.append(node)
        return {"type": kind, "children": children} if children else None


def find_window():
    """The top-level window: the last shown widget, else the last with a layout."""
    roots = [w for w in ALL_WIDGETS if w.shown] or [w for w in ALL_WIDGETS if w.layout_ or w.central]
    return roots[-1] if roots else None


ALL_WIDGETS = []
_orig_init = QObjectBase.__init__


def _tracking_init(self, *a, **k):
    _orig_init(self, *a, **k)
    ALL_WIDGETS.append(self)


QObjectBase.__init__ = _tracking_init


def trace(gui_file):
    gui_file = Path(gui_file).resolve()
    install_fakes()
    sys.path.insert(0, str(gui_file.parent))
    sys.path.insert(0, str(REPO_ROOT))
    sys.argv = [str(gui_file)]
    try:
        runpy.run_path(str(gui_file), run_name="__main__")
    except SystemExit:
        pass

    setup_msgs = list(REC.setup)
    b = Builder()
    window = find_window()
    layout = b.widget(window) if window else None
    if layout is None:
        warn("no window with controls was found")
        layout = {"type": "vbox", "children": []}
    if layout["type"] not in ("vbox", "hbox"):
        layout = {"type": "vbox", "children": [layout]}

    # Setup messages the controls don't own still need to reach the graph; the
    # last one sent to each key wins.
    init = {}
    for m in setup_msgs:
        if m["key"] not in b.owned_keys and m.get("value") != FILE_SENTINEL:
            init[(m["type"], m["key"])] = m
    size = (window.size or window.min_size) if window else None
    return {
        "mmm_audio": FakeMMMAudio.ctor_args,
        "title": (window.title if window else None),
        "width": size[0] if size else None,
        "height": size[1] if size else None,
        "params": b.params,
        "lists": b.lists,
        "init": list(init.values()),
        "layout": layout,
        "warnings": WARNINGS,
    }


if __name__ == "__main__":
    gui_file, out_file = sys.argv[1], sys.argv[2]
    result = trace(gui_file)
    Path(out_file).write_text(json.dumps(result, indent=2))
