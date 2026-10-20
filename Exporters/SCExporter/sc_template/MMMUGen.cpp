// A SuperCollider UGen that runs an MMMAudio graph through MMMAudioPluginBridge
// (see Exporters/PluginExporter/MMMAudioPluginBridge.h for its C API).
//
// Everything specific to one graph (its name, channel counts, controls and
// setup messages) is in MMMSCSpec.h, which export_sc.py writes.
//
// Inputs, in order: the graph's audio inputs (audio rate), then one control
// per MMMSC::controls entry, read once per block. Unit commands (/u_cmd) send
// any other message: "float", "floats", "int", "ints", "bool", "bools",
// "trig", "trigs", "string" and "strings", each followed by the message name
// and its values.
//
// The Mojo libraries are loaded once, when the server loads this plug-in: the
// graph and its engine from the "ignore" folder next to it (scsynth and sclang
// skip folders of that name), and the Mojo runtime, which every UGen built with
// the same Mojo version shares, from ../shared_libraries. The runtime's file
// names carry the Mojo version, so UGens built with different versions each
// load their own.
//
// Building the graph allocates memory and may read files, so it happens on the
// server's non-real-time thread, as do unit commands and freeing the graph.
// Those all go through the same queue, so they run in the order they were
// made: a unit command sent right after the Synth starts reaches the new graph.
// Until the graph is built, the UGen outputs silence.

#include "SC_PlugIn.hpp"
#include "MMMSCSpec.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <type_traits>

#include <dlfcn.h>

static InterfaceTable* ft;

// Everything here has internal linkage: several of these plug-ins can be loaded
// into one server, and identically named symbols (like the template functions
// registerUnit instantiates for MMMUnit) would otherwise be shared between them.
namespace {

class MMMUnit;

using MMMSC::Msg;
using MMMSC::MsgType;
using Handle = intptr_t;

// ---- the bridge --------------------------------------------------------------

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

    // Load the runtime from ../<sharedLibDir>, then the libraries in the
    // "ignore" folder beside this plug-in.
    bool load() {
        Dl_info info;
        if (!dladdr((void*)&ft, &info) || info.dli_fname == nullptr) {
            Print("%s: could not find where the plug-in was loaded from\n", MMMSC::name);
            return false;
        }
        std::string self = info.dli_fname;
        std::string extension = self.substr(0, self.find_last_of('/'));
        std::string dir = extension + "/ignore";
        std::string runtimeDir = extension.substr(0, extension.find_last_of('/')) + "/"
                                 + MMMSC::sharedLibDir;
        graphPath = dir + "/" + MMMSC::graphLib;
        resourceDir = dir + "/resources";

        // Load the runtime first, so a missing library is reported by name.
        // Once loaded, it is found by its (versioned) name, and the libraries'
        // rpaths point at its folder anyway. RTLD_LOCAL keeps one Mojo
        // version's symbols from standing in for another's.
        for (const char* name : MMMSC::runtimeLibs) {
            if (name == nullptr)
                continue;
            std::string path = runtimeDir + "/" + name;
            if (dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL) == nullptr) {
                Print("%s: could not load the Mojo runtime library %s: %s\n", MMMSC::name, path.c_str(),
                      dlerror());
                return false;
            }
        }

        std::string path = dir + "/" + MMMSC::bridgeLib;
        void* lib = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (lib == nullptr) {
            Print("%s: could not load %s: %s\n", MMMSC::name, path.c_str(), dlerror());
            return false;
        }

        bool ok = true;
        auto get = [&](auto& fn, const char* symbol) {
            fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(dlsym(lib, symbol));
            if (fn == nullptr) {
                Print("%s: %s is missing %s\n", MMMSC::name, path.c_str(), symbol);
                ok = false;
            }
        };
        get(create, "mmm_plugin_new");
        get(destroy, "mmm_plugin_free");
        get(setResourceDir, "mmm_plugin_set_resource_dir");
        get(next, "mmm_plugin_next");
        get(sendBool, "mmm_plugin_send_bool");
        get(sendBools, "mmm_plugin_send_bools");
        get(sendFloat, "mmm_plugin_send_float");
        get(sendFloats, "mmm_plugin_send_floats");
        get(sendInt, "mmm_plugin_send_int");
        get(sendInts, "mmm_plugin_send_ints");
        get(sendTrig, "mmm_plugin_send_trig");
        get(sendTrigs, "mmm_plugin_send_trigs");
        get(sendString, "mmm_plugin_send_string");
        get(sendStrings, "mmm_plugin_send_strings");
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
};

Bridge bridge;

// What the unit shares with its asynchronous commands. It outlives the unit:
// the command that frees the graph frees it, after every command queued
// before it has run.
struct Engine {
    MMMUnit* unit;   // touched only on the real-time thread; null once the unit is gone
    Handle handle;   // set on the non-real-time thread
    double sampleRate;
    int blockSize;
};

// A unit command's message, copied out of the OSC packet: the key, values and
// strings live in the same allocation, after the struct.
struct QueuedMsg {
    Engine* engine;
    Msg msg;
};

void doNothing(World*, void*) {}
void freeData(World* world, void* data) { RTFree(world, data); }

bool isList(MsgType t) {
    return t == MsgType::Bools || t == MsgType::Floats || t == MsgType::Ints || t == MsgType::Trigs
        || t == MsgType::Strings;
}

bool isText(MsgType t) { return t == MsgType::String || t == MsgType::Strings; }

// Reads one OSC argument as text; numbers are formatted. `out` may be null to
// only measure it. Returns the length without the terminating NUL.
size_t readText(sc_msg_iter& args, char* out, size_t space) {
    char tag = args.nextTag('s');
    if (tag == 's') {
        const char* s = args.gets("");
        size_t len = std::strlen(s);
        if (out != nullptr)
            std::memcpy(out, s, std::min(len + 1, space));
        return len;
    }
    double v = args.getd();
    char buf[32];
    int len = std::snprintf(buf, sizeof buf, "%.17g", v);
    if (out != nullptr)
        std::memcpy(out, buf, std::min((size_t)len + 1, space));
    return (size_t)len;
}

// ---- the UGen ------------------------------------------------------------------

class MMMUnit : public SCUnit {
public:
    MMMUnit();
    ~MMMUnit();

    void adopt(Handle h);
    void queue(MsgType type, sc_msg_iter* args);

private:
    void next(int nSamples);
    void sendControls();
    void sendState(const MMMSC::MsgList& list);
    void clearOutputs(int nSamples);

    Engine* engine = nullptr;
    Handle handle = 0; // nonzero once the graph is built
    int blockSize;
    float* inBuf = nullptr;  // interleaved, for the bridge
    float* outBuf = nullptr;
    float* lastValues = nullptr; // each control's value when it was last sent
    double* listValues = nullptr; // MMMSC::lists, laid end to end
    bool* listDirty = nullptr;
};

// Stage 2 (non-real-time): build the graph and send it its setup messages.
bool createGraph(World*, void* data) {
    auto* e = static_cast<Engine*>(data);
    // The resource folder is process-wide, and several MMMAudio UGens may be
    // loaded; graphs are only built on this thread, so set it each time.
    bridge.setResourceDir(bridge.resourceDir.c_str());
    e->handle = bridge.create(bridge.graphPath.c_str(), e->sampleRate, e->blockSize, MMMSC::numIn, MMMSC::numOut);
    if (e->handle == 0) {
        Print("%s: could not build the MMMAudio graph from %s\n", MMMSC::name, bridge.graphPath.c_str());
        return false;
    }
    for (int i = 0; i < MMMSC::numInitMsgs; ++i)
        bridge.send(e->handle, MMMSC::initMsgs[i]);
    return true;
}

// Stage 3 (real-time): hand the graph to the unit, if it is still running.
bool adoptGraph(World*, void* data) {
    auto* e = static_cast<Engine*>(data);
    if (e->unit != nullptr)
        e->unit->adopt(e->handle);
    return false;
}

bool destroyGraph(World*, void* data) {
    auto* e = static_cast<Engine*>(data);
    if (e->handle != 0)
        bridge.destroy(e->handle);
    return false;
}

bool sendQueued(World*, void* data) {
    auto* q = static_cast<QueuedMsg*>(data);
    if (q->engine->handle != 0)
        bridge.send(q->engine->handle, q->msg);
    return false;
}

MMMUnit::MMMUnit() {
    mCalcFunc = make_calc_function<MMMUnit, &MMMUnit::next>();
    blockSize = bufferSize();

    int numLists = 0;
    for (int i = 0; i < MMMSC::numLists; ++i)
        numLists += MMMSC::lists[i].size;

    inBuf = (float*)RTAlloc(mWorld, sizeof(float) * std::max(1, blockSize * MMMSC::numIn));
    outBuf = (float*)RTAlloc(mWorld, sizeof(float) * std::max(1, blockSize * MMMSC::numOut));
    lastValues = (float*)RTAlloc(mWorld, sizeof(float) * std::max(1, MMMSC::numControls));
    listValues = (double*)RTAlloc(mWorld, sizeof(double) * std::max(1, numLists));
    listDirty = (bool*)RTAlloc(mWorld, sizeof(bool) * std::max(1, MMMSC::numLists));
    engine = (Engine*)RTAlloc(mWorld, sizeof(Engine));
    if (!inBuf || !outBuf || !lastValues || !listValues || !listDirty || !engine) {
        Print("%s: out of real-time memory\n", MMMSC::name);
        if (engine != nullptr) {
            RTFree(mWorld, engine);
            engine = nullptr;
        }
        mCalcFunc = ft->fClearUnitOutputs;
        clearOutputs(1);
        return;
    }

    new (engine) Engine { this, 0, fullSampleRate(), blockSize };
    if (bridge.loaded)
        DoAsynchronousCommand(mWorld, nullptr, nullptr, engine, createGraph, adoptGraph, nullptr, doNothing, 0,
                              nullptr);
    clearOutputs(1);
}

MMMUnit::~MMMUnit() {
    if (engine != nullptr) {
        engine->unit = nullptr;
        if (bridge.loaded)
            DoAsynchronousCommand(mWorld, nullptr, nullptr, engine, destroyGraph, nullptr, nullptr, freeData, 0,
                                  nullptr);
        else
            RTFree(mWorld, engine);
    }
    for (void* p : { (void*)inBuf, (void*)outBuf, (void*)lastValues, (void*)listValues, (void*)listDirty })
        if (p != nullptr)
            RTFree(mWorld, p);
}

void MMMUnit::adopt(Handle h) {
    handle = h;
    // A new graph starts from its defaults, so every control is sent again.
    std::fill(lastValues, lastValues + MMMSC::numControls, std::numeric_limits<float>::quiet_NaN());
    double* v = listValues;
    for (int i = 0; i < MMMSC::numLists; ++i) {
        std::copy(MMMSC::lists[i].values, MMMSC::lists[i].values + MMMSC::lists[i].size, v);
        v += MMMSC::lists[i].size;
        listDirty[i] = false;
    }
}

void MMMUnit::clearOutputs(int nSamples) {
    for (int c = 0; c < MMMSC::numOut; ++c)
        std::fill(out(c), out(c) + nSamples, 0.f);
}

void MMMUnit::sendState(const MMMSC::MsgList& list) {
    for (int i = 0; i < list.count; ++i)
        bridge.send(handle, list.msgs[i]);
}

void MMMUnit::sendControls() {
    using MMMSC::ControlKind;
    using MMMSC::SendType;

    for (int i = 0; i < MMMSC::numControls; ++i) {
        const auto& c = MMMSC::controls[i];
        const float v = in0(MMMSC::numIn + i);
        float& last = lastValues[i];

        if (c.kind == ControlKind::Trigger) {
            // Like SuperCollider's triggers: fires when the input goes from <= 0 to > 0.
            if (v > 0.f && !(last > 0.f))
                sendState(c.states[0]);
            last = v;
            continue;
        }
        if (v == last)
            continue;
        last = v;

        if (c.kind == ControlKind::State) {
            int state = std::clamp((int)std::lround(v), 0, c.numStates - 1);
            sendState(c.states[state]);
            continue;
        }
        for (int s = 0; s < c.numSends; ++s) {
            const auto& send = c.sends[s];
            switch (send.type) {
            case SendType::Float:    bridge.sendFloat(handle, send.key, v); break;
            case SendType::Int:      bridge.sendInt(handle, send.key, (int64_t)v); break;
            case SendType::IntRound: bridge.sendInt(handle, send.key, (int64_t)std::llround(v)); break;
            case SendType::Bool:     bridge.sendBool(handle, send.key, v >= 0.5f ? 1 : 0); break;
            case SendType::ListElement: {
                double* values = listValues;
                for (int l = 0; l < send.list; ++l)
                    values += MMMSC::lists[l].size;
                values[send.index] = v;
                listDirty[send.list] = true;
                break;
            }
            }
        }
    }

    // Each list goes out once, with every element set this block.
    double* values = listValues;
    for (int l = 0; l < MMMSC::numLists; ++l) {
        if (listDirty[l]) {
            listDirty[l] = false;
            bridge.sendFloats(handle, MMMSC::lists[l].key, values, MMMSC::lists[l].size);
        }
        values += MMMSC::lists[l].size;
    }
}

void MMMUnit::next(int nSamples) {
    if (handle == 0) {
        clearOutputs(nSamples);
        return;
    }

    sendControls();

    for (int start = 0; start < nSamples; start += blockSize) {
        const int n = std::min(blockSize, nSamples - start);

        // SuperCollider gives one buffer per channel; the bridge wants frames interleaved.
        for (int c = 0; c < MMMSC::numIn; ++c) {
            const float* src = in(c) + start;
            for (int i = 0; i < n; ++i)
                inBuf[i * MMMSC::numIn + c] = src[i];
        }

        bridge.next(handle, MMMSC::numIn > 0 ? inBuf : nullptr, outBuf, n);

        for (int c = 0; c < MMMSC::numOut; ++c) {
            float* dst = out(c) + start;
            for (int i = 0; i < n; ++i)
                dst[i] = outBuf[i * MMMSC::numOut + c];
        }
    }
}

// Copy a unit command's message, then send it from the non-real-time thread,
// after the graph is built and before it is freed.
void MMMUnit::queue(MsgType type, sc_msg_iter* args) {
    if (engine == nullptr || !bridge.loaded)
        return;
    const char* key = args->gets();
    if (key == nullptr) {
        Print("%s: a unit command needs a message name\n", MMMSC::name);
        return;
    }

    // Measure the values first, on a copy of the iterator.
    int count = 0;
    size_t textBytes = 0;
    if (type != MsgType::Trig) {
        sc_msg_iter probe = *args;
        while (probe.remain() > 0 && (isList(type) || count < 1)) {
            if (isText(type))
                textBytes += readText(probe, nullptr, 0) + 1;
            else
                probe.getd();
            ++count;
        }
        if (count == 0) {
            Print("%s: '%s' needs a value\n", MMMSC::name, key);
            return;
        }
    }

    size_t keyBytes = std::strlen(key) + 1;
    size_t valueBytes = 0;
    switch (type) {
    case MsgType::Float: case MsgType::Floats: valueBytes = sizeof(double) * count; break;
    case MsgType::Int: case MsgType::Ints:     valueBytes = sizeof(int64_t) * count; break;
    case MsgType::String: case MsgType::Strings: valueBytes = sizeof(char*) * count; break;
    default:                                   valueBytes = sizeof(uint8_t) * count; break;
    }

    // [QueuedMsg][values, 8-byte aligned][key][strings]
    size_t valuesAt = (sizeof(QueuedMsg) + 7) & ~size_t(7);
    size_t keyAt = valuesAt + valueBytes;
    size_t textAt = keyAt + keyBytes;
    char* block = (char*)RTAlloc(mWorld, textAt + textBytes);
    if (block == nullptr) {
        Print("%s: out of real-time memory for '%s'\n", MMMSC::name, key);
        return;
    }

    auto* q = new (block) QueuedMsg { engine, Msg { type, block + keyAt, count, nullptr, nullptr, nullptr, nullptr } };
    std::memcpy(block + keyAt, key, keyBytes);
    void* values = block + valuesAt;
    char* text = block + textAt;
    for (int i = 0; i < count; ++i) {
        switch (type) {
        case MsgType::Float: case MsgType::Floats:
            static_cast<double*>(values)[i] = args->getd();
            break;
        case MsgType::Int: case MsgType::Ints:
            static_cast<int64_t*>(values)[i] = (int64_t)std::llround(args->getd());
            break;
        case MsgType::String: case MsgType::Strings: {
            static_cast<char**>(values)[i] = text;
            size_t len = readText(*args, text, block + textAt + textBytes - text);
            text += len + 1;
            break;
        }
        default:
            static_cast<uint8_t*>(values)[i] = args->getd() != 0.0 ? 1 : 0;
            break;
        }
    }
    switch (type) {
    case MsgType::Float: case MsgType::Floats:   q->msg.floats = static_cast<double*>(values); break;
    case MsgType::Int: case MsgType::Ints:       q->msg.ints = static_cast<int64_t*>(values); break;
    case MsgType::String: case MsgType::Strings: q->msg.strings = static_cast<char**>(values); break;
    default:                                     q->msg.flags = static_cast<uint8_t*>(values); break;
    }

    DoAsynchronousCommand(mWorld, nullptr, nullptr, q, sendQueued, nullptr, nullptr, freeData, 0, nullptr);
}

template <MsgType type> void unitCommand(MMMUnit* unit, sc_msg_iter* args) { unit->queue(type, args); }

} // namespace

PluginLoad(MMMAudioUGen) {
    ft = inTable;
    bridge.loaded = bridge.load();
    registerUnit<MMMUnit>(ft, MMMSC::name, false);

    DefineUnitCmd(MMMSC::name, "bool", (UnitCmdFunc)&unitCommand<MsgType::Bool>);
    DefineUnitCmd(MMMSC::name, "bools", (UnitCmdFunc)&unitCommand<MsgType::Bools>);
    DefineUnitCmd(MMMSC::name, "float", (UnitCmdFunc)&unitCommand<MsgType::Float>);
    DefineUnitCmd(MMMSC::name, "floats", (UnitCmdFunc)&unitCommand<MsgType::Floats>);
    DefineUnitCmd(MMMSC::name, "int", (UnitCmdFunc)&unitCommand<MsgType::Int>);
    DefineUnitCmd(MMMSC::name, "ints", (UnitCmdFunc)&unitCommand<MsgType::Ints>);
    DefineUnitCmd(MMMSC::name, "trig", (UnitCmdFunc)&unitCommand<MsgType::Trig>);
    DefineUnitCmd(MMMSC::name, "trigs", (UnitCmdFunc)&unitCommand<MsgType::Trigs>);
    DefineUnitCmd(MMMSC::name, "string", (UnitCmdFunc)&unitCommand<MsgType::String>);
    DefineUnitCmd(MMMSC::name, "strings", (UnitCmdFunc)&unitCommand<MsgType::Strings>);
}
