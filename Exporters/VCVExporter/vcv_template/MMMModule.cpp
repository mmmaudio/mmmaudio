// A VCV Rack module that runs an MMMAudio graph through MMMAudioPluginBridge
// (see Exporters/PluginExporter/MMMAudioPluginBridge.h for its C API).
//
// Everything specific to one graph (its name, ports, knobs, buttons and setup
// messages, and where they sit on the panel) is in MMMVCVSpec.h, which
// export_vcv.py writes.
//
// Rack calls process() once per sample. The module collects `blockSize`
// samples, then runs the graph on them, so the output lags the input by
// `blockSize` samples (set from the module's right-click menu). Knobs and
// buttons are read once per block and sent to the graph when they change,
// as the Qt GUI would send them.
//
// Audio is +-5 V in Rack and +-1 in MMMAudio, so inputs are divided by 5 and
// outputs multiplied by 5.
//
// The Mojo libraries are loaded once, when Rack loads the plugin: the runtime,
// the graph and its engine, all from the plugin's "bundle/libs" folder. The
// runtime's file names carry the Mojo version, so plugins built with different
// versions each load their own.

#include <rack.hpp>
#include "MMMVCVSpec.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include <dlfcn.h>

using namespace rack;

Plugin* pluginInstance;

// Everything here has internal linkage, so several of these plug-ins can be
// loaded into Rack without sharing code.
namespace {

using MMMVCV::ControlKind;
using MMMVCV::Msg;
using MMMVCV::MsgType;
using MMMVCV::SendType;
using MMMVCV::ControlWidget;
using MMMVCV::DisplayMap;
using Handle = intptr_t;

// The graph is built for blocks of up to this many frames; the module runs it on
// shorter ones.
constexpr int kMaxBlock = 64;
constexpr int kBlockSizes[] = { 1, 4, 16, 32, 64 };
constexpr float kVolts = 5.f;

// ---- the bridge --------------------------------------------------------------

template <typename F>
bool getSymbol(void* lib, F& fn, const char* symbol, const std::string& path) {
    fn = reinterpret_cast<F>(dlsym(lib, symbol));
    if (fn == nullptr) {
        WARN("%s: %s is missing %s", MMMVCV::name, path.c_str(), symbol);
        return false;
    }
    return true;
}

struct Bridge {
    Handle (*create)(const char*, double, intptr_t, intptr_t, intptr_t) = nullptr;
    void (*destroy)(Handle) = nullptr;
    void (*setResourceDir)(const char*) = nullptr;
    int (*next)(Handle, const float*, float*, intptr_t) = nullptr;
    void (*sendBool)(Handle, const char*, int) = nullptr;
    void (*sendBools)(Handle, const char*, const uint8_t*, intptr_t) = nullptr;
    void (*sendFloat)(Handle, const char*, double) = nullptr;
    void (*sendFloats)(Handle, const char*, const double*, intptr_t) = nullptr;
    void (*sendInt)(Handle, const char*, int64_t) = nullptr;
    void (*sendInts)(Handle, const char*, const int64_t*, intptr_t) = nullptr;
    void (*sendTrig)(Handle, const char*) = nullptr;
    void (*sendTrigs)(Handle, const char*, const uint8_t*, intptr_t) = nullptr;
    void (*sendString)(Handle, const char*, const char*) = nullptr;
    void (*sendStrings)(Handle, const char*, const char* const*, intptr_t) = nullptr;

    bool loaded = false;
    std::string graphPath;   // the graph library
    std::string resourceDir; // copies of the files the graph opens by relative path

    // Load the runtime, then the graph's engine, from `bundle`/libs.
    bool load(const std::string& bundle) {
        std::string dir = bundle + "/libs";
        graphPath = dir + "/" + MMMVCV::graphLib;
        resourceDir = bundle + "/resources";

        // Load the runtime first, so a missing library is reported by name.
        // RTLD_LOCAL keeps one Mojo version's symbols from standing in for another's.
        for (const char* name : MMMVCV::runtimeLibs) {
            if (name == nullptr)
                continue;
            std::string path = dir + "/" + name;
            if (dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL) == nullptr) {
                WARN("%s: could not load the Mojo runtime library %s: %s", MMMVCV::name, path.c_str(), dlerror());
                return false;
            }
        }

        std::string path = dir + "/" + MMMVCV::bridgeLib;
        void* lib = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (lib == nullptr) {
            WARN("%s: could not load %s: %s", MMMVCV::name, path.c_str(), dlerror());
            return false;
        }

        bool ok = true;
        ok &= getSymbol(lib, create, "mmm_plugin_new", path);
        ok &= getSymbol(lib, destroy, "mmm_plugin_free", path);
        ok &= getSymbol(lib, setResourceDir, "mmm_plugin_set_resource_dir", path);
        ok &= getSymbol(lib, next, "mmm_plugin_next", path);
        ok &= getSymbol(lib, sendBool, "mmm_plugin_send_bool", path);
        ok &= getSymbol(lib, sendBools, "mmm_plugin_send_bools", path);
        ok &= getSymbol(lib, sendFloat, "mmm_plugin_send_float", path);
        ok &= getSymbol(lib, sendFloats, "mmm_plugin_send_floats", path);
        ok &= getSymbol(lib, sendInt, "mmm_plugin_send_int", path);
        ok &= getSymbol(lib, sendInts, "mmm_plugin_send_ints", path);
        ok &= getSymbol(lib, sendTrig, "mmm_plugin_send_trig", path);
        ok &= getSymbol(lib, sendTrigs, "mmm_plugin_send_trigs", path);
        ok &= getSymbol(lib, sendString, "mmm_plugin_send_string", path);
        ok &= getSymbol(lib, sendStrings, "mmm_plugin_send_strings", path);
        return ok;
    }

    void send(Handle h, const Msg& m) const {
        switch (m.type) {
        case MsgType::Bool:    sendBool(h, m.key, m.flags[0]); break;
        case MsgType::Bools:   sendBools(h, m.key, m.flags, m.count); break;
        case MsgType::Float:   sendFloat(h, m.key, m.floats[0]); break;
        case MsgType::Floats:  sendFloats(h, m.key, m.floats, m.count); break;
        case MsgType::Int:     sendInt(h, m.key, m.ints[0]); break;
        case MsgType::Ints:    sendInts(h, m.key, m.ints, m.count); break;
        case MsgType::Trig:    sendTrig(h, m.key); break;
        case MsgType::Trigs:   sendTrigs(h, m.key, m.flags, m.count); break;
        case MsgType::String:  sendString(h, m.key, m.strings[0]); break;
        case MsgType::Strings: sendStrings(h, m.key, m.strings, m.count); break;
        }
    }

    // Build a graph and send it its setup messages. The resource folder is
    // process-wide, so building is serialized.
    Handle build(double sampleRate) {
        static std::mutex mutex;
        std::lock_guard<std::mutex> lock(mutex);
        setResourceDir(resourceDir.c_str());
        Handle h = create(graphPath.c_str(), sampleRate, kMaxBlock, MMMVCV::numIn, MMMVCV::numOut);
        if (h == 0) {
            WARN("%s: could not build the MMMAudio graph from %s", MMMVCV::name, graphPath.c_str());
            return 0;
        }
        for (int i = 0; i < MMMVCV::numInitMsgs; ++i)
            send(h, MMMVCV::initMsgs[i]);
        return h;
    }
};

Bridge bridge;

// A knob for a GUI slider with a curve: the knob turns from 0 to 1, and shows
// min + n^exp * (max - min), as the slider does.
struct CurveQuantity : ParamQuantity {
    float lo = 0.f, hi = 1.f, ex = 1.f;
    bool integer = false;

    float getDisplayValue() override {
        float v = lo + std::pow(math::clamp(getValue(), 0.f, 1.f), ex) * (hi - lo);
        return integer ? std::round(v) : v;
    }

    void setDisplayValue(float v) override {
        if (hi == lo)
            return;
        setValue(std::pow(math::clamp((v - lo) / (hi - lo), 0.f, 1.f), 1.f / ex));
    }
};

// A knob that sends its own value (-1 to 1, for an exported struct) but shows it
// as the struct maps it, the way MMMAudio's linlin, linexp and lincurve do.
struct MapQuantity : ParamQuantity {
    DisplayMap mode = DisplayMap::Lin;
    float inLo = -1.f, inHi = 1.f, outLo = 0.f, outHi = 1.f, curve = 1.f;

    // linlin and linexp ignore a reversed input range; lincurve flips for one.
    bool flips() { return mode == DisplayMap::Curve && inLo > inHi; }
    float c() { return math::clamp(curve, 1e-5f, 8192.f); }

    float getDisplayValue() override {
        float n = math::clamp((getValue() - std::min(inLo, inHi)) / std::abs(inHi - inLo), 0.f, 1.f);
        if (flips())
            n = 1.f - n;
        switch (mode) {
        case DisplayMap::Exp:
            return outLo * std::pow(outHi / outLo, n);
        case DisplayMap::Curve:
            return outLo <= outHi ? outLo + std::pow(n, c()) * (outHi - outLo)
                                  : outHi + (1.f - std::pow(n, 1.f / c())) * (outLo - outHi);
        default:
            return outLo + n * (outHi - outLo);
        }
    }

    void setDisplayValue(float v) override {
        if (outHi == outLo)
            return;
        float n;
        switch (mode) {
        case DisplayMap::Exp:
            n = v > 0.f ? std::log(v / outLo) / std::log(outHi / outLo) : 0.f;
            break;
        case DisplayMap::Curve:
            n = outLo <= outHi ? std::pow(math::clamp((v - outLo) / (outHi - outLo), 0.f, 1.f), 1.f / c())
                               : std::pow(math::clamp(1.f - (v - outHi) / (outLo - outHi), 0.f, 1.f), c());
            break;
        default:
            n = (v - outLo) / (outHi - outLo);
        }
        n = math::clamp(n, 0.f, 1.f);
        if (flips())
            n = 1.f - n;
        setValue(std::min(inLo, inHi) + n * std::abs(inHi - inLo));
    }
};

bool hasCurve(const MMMVCV::Control& c) { return c.kind == ControlKind::Value && c.exp != 1.f; }

// ---- the module ----------------------------------------------------------------

struct MMMModule : Module {
    Handle handle = 0; // nonzero once the graph is built
    double graphSampleRate = 0.0;
    int blockSize = MMMVCV::defaultBlockSize;
    int requestedBlockSize = MMMVCV::defaultBlockSize; // set from the menu, applied between blocks
    int pos = 0;
    std::vector<float> inBuf, outBuf; // interleaved, for the bridge
    std::vector<float> lastValues;    // each control's value when it was last sent
    std::vector<bool> fresh;          // controls to send whatever their value
    std::vector<double> listValues;   // MMMVCV::lists, laid end to end
    std::vector<bool> listDirty;

    MMMModule() {
        config(MMMVCV::numControls, MMMVCV::numIn, MMMVCV::numOut, 0);
        for (int i = 0; i < MMMVCV::numControls; ++i)
            configControl(i, MMMVCV::controls[i]);
        for (int i = 0; i < MMMVCV::numIn; ++i)
            configInput(i, MMMVCV::inPorts[i].name);
        for (int i = 0; i < MMMVCV::numOut; ++i)
            configOutput(i, MMMVCV::outPorts[i].name);
        for (int i = 0; i < std::min(MMMVCV::numIn, MMMVCV::numOut); ++i)
            configBypass(i, i);

        inBuf.assign(kMaxBlock * std::max(1, MMMVCV::numIn), 0.f);
        outBuf.assign(kMaxBlock * std::max(1, MMMVCV::numOut), 0.f);
        lastValues.assign(MMMVCV::numControls, 0.f);
        fresh.assign(MMMVCV::numControls, true);
        int numListValues = 0;
        for (int i = 0; i < MMMVCV::numLists; ++i)
            numListValues += MMMVCV::lists[i].size;
        listValues.assign(numListValues, 0.0);
        listDirty.assign(MMMVCV::numLists, false);

        rebuild(APP->engine->getSampleRate());
    }

    ~MMMModule() override {
        if (handle != 0)
            bridge.destroy(handle);
    }

    void configControl(int i, const MMMVCV::Control& c) {
        switch (c.widget) {
        case ControlWidget::Knob:
            if (hasCurve(c)) {
                float n = c.max == c.min ? 0.f : std::pow(math::clamp((c.defaultValue - c.min) / (c.max - c.min), 0.f, 1.f),
                                                          1.f / c.exp);
                CurveQuantity* q = configParam<CurveQuantity>(i, 0.f, 1.f, n, c.name);
                q->lo = c.min;
                q->hi = c.max;
                q->ex = c.exp;
                q->integer = c.integer;
            } else if (c.display != DisplayMap::None) {
                MapQuantity* q = configParam<MapQuantity>(i, c.min, c.max, c.defaultValue, c.name);
                q->mode = c.display;
                q->inLo = c.map[0];
                q->inHi = c.map[1];
                q->outLo = c.map[2];
                q->outHi = c.map[3];
                q->curve = c.map[4];
            } else {
                ParamQuantity* q = configParam(i, c.min, c.max, c.defaultValue, c.name);
                q->snapEnabled = c.integer;
            }
            break;
        case ControlWidget::SnapKnob: {
            std::vector<std::string> labels(c.choices, c.choices + c.numStates);
            configSwitch(i, 0.f, (float)(c.numStates - 1), c.defaultValue, c.name, labels);
            break;
        }
        case ControlWidget::Latch:
            configSwitch(i, 0.f, 1.f, c.defaultValue, c.name, { "Off", "On" });
            break;
        case ControlWidget::Momentary:
        case ControlWidget::Button:
            configButton(i, c.name);
            break;
        }
    }

    // Build a graph for `sampleRate`, replacing the current one. Called when no
    // block is running: from the constructor, or while the engine is paused for
    // a sample rate change.
    void rebuild(double sampleRate) {
        if (!bridge.loaded)
            return;
        Handle old = handle;
        handle = bridge.build(sampleRate);
        graphSampleRate = sampleRate;
        if (old != 0)
            bridge.destroy(old);
        // A new graph starts from its defaults, so every control is sent again.
        std::fill(fresh.begin(), fresh.end(), true);
        double* v = listValues.data();
        for (int i = 0; i < MMMVCV::numLists; ++i) {
            std::copy(MMMVCV::lists[i].values, MMMVCV::lists[i].values + MMMVCV::lists[i].size, v);
            v += MMMVCV::lists[i].size;
            listDirty[i] = false;
        }
        pos = 0;
        std::fill(outBuf.begin(), outBuf.end(), 0.f);
    }

    void onSampleRateChange(const SampleRateChangeEvent& e) override {
        if (e.sampleRate != graphSampleRate)
            rebuild(e.sampleRate);
    }

    void sendState(const MMMVCV::MsgList& list) {
        for (int i = 0; i < list.count; ++i)
            bridge.send(handle, list.msgs[i]);
    }

    // A button that moves other knobs, as the GUI's randomize and preset buttons do.
    void moveKnobs(const MMMVCV::Control& c) {
        for (int i = 0; i < c.numRandomize; ++i)
            getParamQuantity(c.randomize[i])->randomize();
        for (int i = 0; i < c.numSets; ++i)
            params[c.sets[i].control].setValue(c.sets[i].value);
    }

    void sendControls() {
        for (int i = 0; i < MMMVCV::numControls; ++i) {
            const MMMVCV::Control& c = MMMVCV::controls[i];
            const float v = params[i].getValue();
            const bool changed = fresh[i] || v != lastValues[i];
            const bool wasOn = !fresh[i] && lastValues[i] > 0.f;
            lastValues[i] = v;
            fresh[i] = false;

            if (c.kind == ControlKind::Trigger) {
                // Fires when the button goes down.
                if (v > 0.f && !wasOn) {
                    sendState(c.states[0]);
                    moveKnobs(c);
                }
                continue;
            }
            if (!changed)
                continue;

            if (c.kind == ControlKind::State) {
                int state = math::clamp((int)std::lround(v), 0, c.numStates - 1);
                sendState(c.states[state]);
                continue;
            }
            double value = hasCurve(c) ? c.min + std::pow(math::clamp(v, 0.f, 1.f), c.exp) * (c.max - c.min) : v;
            for (int s = 0; s < c.numSends; ++s) {
                const MMMVCV::Send& send = c.sends[s];
                switch (send.type) {
                case SendType::Float:    bridge.sendFloat(handle, send.key, value); break;
                case SendType::Int:      bridge.sendInt(handle, send.key, (int64_t)value); break;
                case SendType::IntRound: bridge.sendInt(handle, send.key, (int64_t)std::llround(value)); break;
                case SendType::Bool:     bridge.sendBool(handle, send.key, value >= 0.5 ? 1 : 0); break;
                case SendType::ListElement: {
                    double* values = listValues.data();
                    for (int l = 0; l < send.list; ++l)
                        values += MMMVCV::lists[l].size;
                    values[send.index] = value;
                    listDirty[send.list] = true;
                    break;
                }
                }
            }
        }

        // Each list goes out once, with every element set this block.
        double* values = listValues.data();
        for (int l = 0; l < MMMVCV::numLists; ++l) {
            if (listDirty[l]) {
                listDirty[l] = false;
                bridge.sendFloats(handle, MMMVCV::lists[l].key, values, MMMVCV::lists[l].size);
            }
            values += MMMVCV::lists[l].size;
        }
    }

    void process(const ProcessArgs& args) override {
        for (int c = 0; c < MMMVCV::numIn; ++c)
            inBuf[pos * MMMVCV::numIn + c] = inputs[c].isConnected() ? inputs[c].getVoltage() / kVolts
                                                                     : MMMVCV::inPorts[c].unplugged;
        for (int c = 0; c < MMMVCV::numOut; ++c)
            outputs[c].setVoltage(outBuf[pos * MMMVCV::numOut + c] * kVolts);

        if (++pos < blockSize)
            return;
        pos = 0;
        if (handle != 0) {
            sendControls();
            bridge.next(handle, MMMVCV::numIn > 0 ? inBuf.data() : nullptr, outBuf.data(), blockSize);
        }
        if (requestedBlockSize != blockSize) {
            blockSize = requestedBlockSize;
            std::fill(outBuf.begin(), outBuf.end(), 0.f);
        }
    }

    json_t* dataToJson() override {
        json_t* root = json_object();
        json_object_set_new(root, "blockSize", json_integer(requestedBlockSize));
        return root;
    }

    void dataFromJson(json_t* root) override {
        json_t* size = json_object_get(root, "blockSize");
        if (size == nullptr)
            return;
        for (int s : kBlockSizes)
            if (s == (int)json_integer_value(size))
                requestedBlockSize = s;
    }
};

// ---- the panel -----------------------------------------------------------------

// Text drawn on the panel (Rack's SVG renderer doesn't draw SVG text).
struct PanelLabel : TransparentWidget {
    std::string text;
    float fontSize = 9.f;

    void draw(const DrawArgs& args) override {
        std::shared_ptr<window::Font> font = APP->window->uiFont;
        if (!font || font->handle < 0)
            return;
        nvgFontFaceId(args.vg, font->handle);
        nvgFontSize(args.vg, fontSize);
        nvgFillColor(args.vg, settings::preferDarkPanels ? nvgRGB(0xd6, 0xdd, 0xe4) : nvgRGB(0x1c, 0x24, 0x2d));
        nvgTextAlign(args.vg, NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE);
        nvgText(args.vg, box.size.x / 2, box.size.y / 2, text.c_str(), nullptr);
    }
};

void addLabel(Widget* parent, const std::string& text, float xMm, float yMm, float widthMm, float fontSize) {
    PanelLabel* label = new PanelLabel;
    label->text = text;
    label->fontSize = fontSize;
    label->box.size = mm2px(Vec(widthMm, 4.f));
    label->box.pos = mm2px(Vec(xMm, yMm)).minus(label->box.size.div(2));
    parent->addChild(label);
}

struct MMMWidget : ModuleWidget {
    MMMWidget(MMMModule* module) {
        setModule(module);
        setPanel(createPanel(asset::plugin(pluginInstance, std::string("res/") + MMMVCV::slug + ".svg"),
                             asset::plugin(pluginInstance, std::string("res/") + MMMVCV::slug + "-dark.svg")));

        float width = MMMVCV::panelHp * 5.08f;
        addLabel(this, MMMVCV::title, width / 2, MMMVCV::titleY, width - 2.f, 12.f);

        for (int i = 0; i < MMMVCV::numControls; ++i) {
            const MMMVCV::Control& c = MMMVCV::controls[i];
            Vec at = mm2px(Vec(c.x, c.y));
            switch (c.widget) {
            case ControlWidget::Knob:      addParam(createParamCentered<RoundBlackKnob>(at, module, i)); break;
            case ControlWidget::SnapKnob:  addParam(createParamCentered<RoundBlackSnapKnob>(at, module, i)); break;
            case ControlWidget::Latch:     addParam(createParamCentered<VCVLatch>(at, module, i)); break;
            case ControlWidget::Momentary:
            case ControlWidget::Button:    addParam(createParamCentered<VCVButton>(at, module, i)); break;
            }
            addLabel(this, c.label, c.x, c.y + MMMVCV::labelOffset, MMMVCV::cellWidth, 8.f);
        }
        for (int i = 0; i < MMMVCV::numIn; ++i) {
            const MMMVCV::Port& p = MMMVCV::inPorts[i];
            addInput(createInputCentered<ThemedPJ301MPort>(mm2px(Vec(p.x, p.y)), module, i));
            addLabel(this, p.label, p.x, p.y - 6.5f, MMMVCV::portWidth, 8.f);
        }
        for (int i = 0; i < MMMVCV::numOut; ++i) {
            const MMMVCV::Port& p = MMMVCV::outPorts[i];
            addOutput(createOutputCentered<ThemedPJ301MPort>(mm2px(Vec(p.x, p.y)), module, i));
            addLabel(this, p.label, p.x, p.y - 6.5f, MMMVCV::portWidth, 8.f);
        }
    }

    void appendContextMenu(Menu* menu) override {
        MMMModule* module = getModule<MMMModule>();
        if (module == nullptr)
            return;
        menu->addChild(new MenuSeparator);
        if (!bridge.loaded)
            menu->addChild(createMenuLabel("The Mojo libraries didn't load: see Rack's log.txt"));
        else if (module->handle == 0)
            menu->addChild(createMenuLabel("The graph didn't build: see Rack's log.txt"));
        menu->addChild(createSubmenuItem("Block size", string::f("%d (latency)", module->requestedBlockSize),
            [=](Menu* sub) {
                for (int s : kBlockSizes) {
                    sub->addChild(createCheckMenuItem(string::f("%d sample%s", s, s == 1 ? "" : "s"), "",
                        [=]() { return module->requestedBlockSize == s; },
                        [=]() { module->requestedBlockSize = s; }));
                }
            }));
    }
};

} // namespace

Model* modelMMM = createModel<MMMModule, MMMWidget>(MMMVCV::slug);

void init(Plugin* p) {
    pluginInstance = p;
    bridge.loaded = bridge.load(p->path + "/bundle");
    p->addModel(modelMMM);
}
