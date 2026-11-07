"""Writes an exported plugin's editor as plain JUCE code, from the "layout" tree
gui_tracer.py makes of the Qt GUI.

Every control becomes a named member of MMMAudioEditor (`freqSlider`,
`playToggle`...) built from the widgets in juce_template/MMMWidgets.h, and the
layout becomes explicit `setBounds` calls in `resized()`. The result looks like
the Qt GUI and is meant to be edited by hand: restyle it, move things, swap in
your own components.

`write_editor` writes builds/<target>/Source/PluginEditor.h/.cpp. It records a
hash of what it wrote, and on the next export it only replaces the files if
they still match it, so hand edits survive re-exporting.
"""

import hashlib
import json
import re
import unicodedata
from pathlib import Path

GAP = 6      # space between controls; must match `gap` in the generated header
MARGIN = 12  # space around the editor; must match `margin`

# (height, minimum width) of each kind of control.
SIZES = {
    "slider": (26, 300),
    "toggle": (24, 120),
    "toggle_button": (28, 120),
    "combo": (26, 240),
    "label": (24, 100),
    "button": (28, 120),
    "file": (28, 240),
}

STAMP = ".generated"  # in Source/: the hash of each file as last written


# --------------------------------------------------------------------------
# Layout tree
# --------------------------------------------------------------------------

class Leaf:
    def __init__(self, member, decl, height, min_width, setup=()):
        self.member, self.decl = member, decl
        self.height, self.min_width = height, min_width
        self.setup = list(setup)  # extra constructor lines

    def pref_height(self):
        return self.height

    def pref_width(self):
        return self.min_width


class Box:
    def __init__(self, horizontal, children):
        self.horizontal, self.children = horizontal, children

    def pref_height(self):
        hs = [c.pref_height() for c in self.children]
        if self.horizontal:
            return max(hs, default=0)
        return sum(hs) + GAP * max(0, len(hs) - 1)

    def pref_width(self):
        ws = [c.pref_width() for c in self.children]
        if self.horizontal:
            return sum(ws) + 2 * GAP * max(0, len(ws) - 1)
        return max(ws, default=0)


def cpp_str(s):
    """A C++ expression for the juce::String `s`."""
    s = str(s)
    if s.isascii():
        return json.dumps(s)
    return f"juce::String::fromUTF8 ({json.dumps(s, ensure_ascii=False)})"


def camel(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()  # "Délai" -> "Delai"
    words = re.findall(r"[A-Za-z0-9]+", text)
    if not words:
        return ""
    name = words[0].lower() + "".join(w[:1].upper() + w[1:] for w in words[1:])
    return name if not name[0].isdigit() else "c" + name


class Builder:
    def __init__(self, spec):
        self.params = {p["id"]: p for p in spec.get("params", [])}
        self.leaves = []
        self.used = set()

    def name(self, base, suffix):
        base = camel(base)[:24] or suffix.lower()
        name, n = base + suffix, 2
        while name in self.used:
            name, n = f"{base}{suffix}{n}", n + 1
        self.used.add(name)
        return name

    def leaf(self, *args, **kwargs):
        leaf = Leaf(*args, **kwargs)
        self.leaves.append(leaf)
        return leaf

    def build(self, node):
        t = node.get("type")
        if t in ("vbox", "hbox"):
            kids = [k for k in (self.build(c) for c in node.get("children", [])) if k is not None]
            return Box(t == "hbox", kids)

        if t == "param":
            pid = node["param"]
            if pid not in self.params:
                return None
            label = self.params[pid].get("name", pid)
            widget = node.get("widget", "slider")
            h, w = SIZES.get(widget, SIZES["slider"])
            if widget in ("toggle", "toggle_button"):
                as_button = "true" if widget == "toggle_button" else "false"
                return self.leaf(self.name(pid, "Toggle"),
                                 f"mmm::ToggleRow {{NAME}} {{ plugin.apvts, {cpp_str(pid)}, {cpp_str(label)}, {as_button} }};", h, w)
            if widget == "combo":
                return self.leaf(self.name(pid, "Combo"),
                                 f"mmm::ComboRow {{NAME}} {{ plugin.apvts, {cpp_str(pid)}, {cpp_str(label)} }};", h, w)
            return self.leaf(self.name(pid, "Slider"),
                             f"mmm::SliderRow {{NAME}} {{ plugin.apvts, {cpp_str(pid)}, {cpp_str(label)} }};", h, w)

        if t == "label":
            h, w = SIZES["label"]
            leaf = self.leaf(self.name(" ".join(str(node.get("text", "")).split()[:3]), "Label"),
                             f"juce::Label {{NAME}} {{ {{}}, {cpp_str(node.get('text', ''))} }};", h, w)
            if node.get("bold"):
                leaf.setup.append(f"{leaf.member}.setFont (juce::Font (juce::FontOptions (16.0f)).boldened());")
            return leaf

        if t in ("button", "file"):
            h, w = SIZES[t]
            # The messages it sends, as the tracer found them.
            spec_json = json.dumps(node, separators=(",", ":"))
            cls, suffix = ("mmm::ActionButton", "Button") if t == "button" else ("mmm::FileRow", "File")
            return self.leaf(self.name(node.get("label", t), suffix),
                             f'{cls} {{NAME}} {{ plugin, juce::JSON::parse (R"MMM({spec_json})MMM") }};', h, w)

        if t == "xy":
            h = max(100, int(node.get("height") or 250))
            w = max(100, int(node.get("width") or 250))
            ids = ", ".join(cpp_str(node.get(k, "")) for k in ("x", "y", "pressed"))
            return self.leaf(self.name(node.get("x", "xy").removesuffix("_x"), "Pad"),
                             f"mmm::XYPad {{NAME}} {{ plugin.apvts, {ids} }};", h, w)

        return None


# --------------------------------------------------------------------------
# resized()
# --------------------------------------------------------------------------

class Emitter:
    def __init__(self):
        self.lines = []
        self.count = 0

    def var(self, base):
        self.count += 1
        return f"{base}{self.count}"

    def put(self, depth, line):
        self.lines.append("    " * depth + line)

    def place(self, node, area, depth, take):
        """Lay `node` out in the slice `take` (an expression) of `area`."""
        if isinstance(node, Leaf):
            self.put(depth, f"{node.member}.setBounds ({take});")
            return
        if not node.children:
            return
        inner = self.var("col" if node.horizontal else "row")
        self.put(depth, "{")
        self.put(depth + 1, f"auto {inner} = {take};")
        self.box(node, inner, depth + 1)
        self.put(depth, "}")

    def box(self, node, area, depth):
        kids = node.children
        if not node.horizontal:
            for i, c in enumerate(kids):
                take = f"{area}.removeFromTop ({c.pref_height()})"
                self.place(c, area, depth, take)
                if i + 1 < len(kids):
                    self.put(depth, f"{area}.removeFromTop (gap);")
            return

        # Columns share the width in proportion to the width each one wants.
        total = max(1, sum(c.pref_width() for c in kids))
        if len(kids) > 1:
            self.put(depth, f"const int avail{self.count} = {area}.getWidth() - 2 * gap * {len(kids) - 1};")
        avail = f"avail{self.count}"
        for i, c in enumerate(kids):
            last = i + 1 == len(kids)
            take = area if last else f"{area}.removeFromLeft ({avail} * {c.pref_width()} / {total})"
            if isinstance(c, Leaf):
                take = f"{take}.withHeight ({c.height})"
            self.place(c, area, depth, take)
            if not last:
                self.put(depth, f"{area}.removeFromLeft (2 * gap);")


# --------------------------------------------------------------------------
# Files
# --------------------------------------------------------------------------

HEADER = """\
// {title}'s editor, generated by export_plugin.py from {source}.
// It's yours to edit: re-exporting only replaces it while it is unchanged
// (or with --reset_editor). Each control is a member below and attaches to its
// parameter by id, so restyling or moving it doesn't change what it controls.
#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"
#include "MMMWidgets.h"

class MMMAudioEditor : public juce::AudioProcessorEditor
{{
public:
    explicit MMMAudioEditor (MMMAudioProcessor&);
    ~MMMAudioEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    MMMAudioProcessor& plugin;   // (AudioProcessorEditor already has a `processor`)

    // Restyles every control: swap in your own juce::LookAndFeel_V4 subclass.
    juce::LookAndFeel_V4 lookAndFeel;

{members}

    juce::Label errorLabel;

    static constexpr int margin = {margin}, gap = {gap};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MMMAudioEditor)
}};
"""

SOURCE = """\
#include "PluginEditor.h"

MMMAudioEditor::MMMAudioEditor (MMMAudioProcessor& p)
    : AudioProcessorEditor (&p), plugin (p)
{{
    setLookAndFeel (&lookAndFeel);

{setup}
    if (plugin.loadError.isNotEmpty())
    {{
        errorLabel.setText (plugin.loadError, juce::dontSendNotification);
        errorLabel.setColour (juce::Label::textColourId, juce::Colours::orangered);
        addAndMakeVisible (errorLabel);
    }}

    const int errorHeight = plugin.loadError.isNotEmpty() ? 40 : 0;
    setResizable (true, true);
    setResizeLimits ({min_width}, {height} + errorHeight, 3000, 3000);
    setSize ({width}, {height} + errorHeight);
}}

MMMAudioEditor::~MMMAudioEditor()
{{
    setLookAndFeel (nullptr);
}}

void MMMAudioEditor::paint (juce::Graphics& g)
{{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}}

void MMMAudioEditor::resized()
{{
    auto area = getLocalBounds().reduced (margin);
    if (errorLabel.isVisible())
        errorLabel.setBounds (area.removeFromBottom (40));

{layout}
}}
"""


def generate(spec, source="the plugin's parameters"):
    """Return {file name: text} for the editor described by `spec`."""
    b = Builder(spec)
    root = b.build(spec.get("layout") or {"type": "vbox", "children": []})
    if not isinstance(root, Box):
        root = Box(False, [root] if root else [])

    members = "\n".join("    " + leaf.decl.replace("{NAME}", leaf.member) for leaf in b.leaves)
    setup = "".join(f"    addAndMakeVisible ({leaf.member});\n" for leaf in b.leaves)
    setup += "".join(f"    {line}\n" for leaf in b.leaves for line in leaf.setup)

    e = Emitter()
    e.box(root, "area", 1)

    pref_w = root.pref_width() + 2 * MARGIN
    width = max(int(spec.get("width") or 0), pref_w, 300)
    height = root.pref_height() + 2 * MARGIN
    title = spec.get("title") or "The plugin"
    return {
        "PluginEditor.h": HEADER.format(title=title, source=source, members=members or "    // (no controls)",
                                        margin=MARGIN, gap=GAP),
        "PluginEditor.cpp": SOURCE.format(setup=setup, layout="\n".join(e.lines) or "    juce::ignoreUnused (area);",
                                          min_width=min(width, pref_w), width=width, height=height),
    }


def _sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def write_editor(source_dir, spec, source="the plugin's parameters", reset=False, log=print):
    """Write the editor into `source_dir`, unless its files were edited since they were
    generated (pass reset=True to replace them anyway). Returns True if it wrote them."""
    source_dir = Path(source_dir)
    source_dir.mkdir(parents=True, exist_ok=True)
    files = generate(spec, source)
    stamp_file = source_dir / STAMP
    try:
        stamp = json.loads(stamp_file.read_text())
    except (OSError, ValueError):
        stamp = {}

    edited = [n for n in files if (source_dir / n).exists()
              and _sha((source_dir / n).read_text(encoding="utf-8")) != stamp.get(n)]
    if edited and not reset:
        log(f"keeping the edited editor in {source_dir} ({', '.join(edited)}); "
            "pass --reset_editor to regenerate it from the GUI")
        return False

    for n, text in files.items():
        (source_dir / n).write_text(text, encoding="utf-8")
    stamp_file.write_text(json.dumps({n: _sha(t) for n, t in files.items()}, indent=1))
    log(f"wrote the editor to {source_dir}")
    return True
