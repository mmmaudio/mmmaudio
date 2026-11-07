// Loads MMMAudioPluginBridge (the Mojo engine) and the graph library that
// ships inside the plugin bundle, and wraps the bridge's C functions.
// See ../MMMAudioPluginBridge.h for the C API.
#pragma once

#include <JuceHeader.h>
#include <cstdint>

#if JUCE_MAC || JUCE_LINUX || JUCE_BSD
 #include <dlfcn.h>
#endif

class MMMBridge
{
public:
    using Handle = intptr_t;

    // The libraries are never closed: the Mojo runtime keeps threads and
    // globals alive, and other instances of the plug-in share it.
    MMMBridge() = default;

    // Where the bundled .dylib/.so files live:
    //   macOS: <bundle>/Contents/Frameworks
    //   Linux: next to the plug-in binary, in "<binary name>_mmm"
    static juce::File libraryDirectory()
    {
        auto exe = juce::File::getSpecialLocation (juce::File::currentExecutableFile);
       #if JUCE_MAC
        return exe.getParentDirectory().getSiblingFile ("Frameworks");
       #else
        return exe.getParentDirectory().getChildFile (exe.getFileNameWithoutExtension() + "_mmm");
       #endif
    }

    // Copies of the files the graph opens by relative path.
    static juce::File resourceDirectory()
    {
       #if JUCE_MAC
        return libraryDirectory().getSiblingFile ("Resources").getChildFile ("MMMAudio");
       #else
        return libraryDirectory().getChildFile ("resources");
       #endif
    }

    bool load (const juce::String& bridgeFileName, const juce::StringArray& preload)
    {
        auto dir = libraryDirectory();

        // On Linux the Mojo runtime is found by SONAME once it is loaded, so
        // load it globally first. On macOS the libraries' rpaths point at
        // their own folder, so this is harmless.
        for (auto& name : preload)
            dlopen (dir.getChildFile (name).getFullPathName().toRawUTF8(), RTLD_NOW | RTLD_GLOBAL);

        auto path = dir.getChildFile (bridgeFileName).getFullPathName();
        lib = dlopen (path.toRawUTF8(), RTLD_NOW | RTLD_LOCAL);
        if (lib == nullptr)
        {
            error = "could not load " + path + ": " + juce::String (dlerror());
            return false;
        }

        bool ok = true;
        auto get = [&] (auto& fn, const char* name)
        {
            fn = reinterpret_cast<std::remove_reference_t<decltype (fn)>> (dlsym (lib, name));
            if (fn == nullptr) { ok = false; error = juce::String ("missing symbol ") + name; }
        };

        get (create, "mmm_plugin_new");
        get (destroy, "mmm_plugin_free");
        get (setResourceDir, "mmm_plugin_set_resource_dir");
        get (setSampleRate, "mmm_plugin_set_sample_rate");
        get (setBlockSize, "mmm_plugin_set_block_size");
        get (next, "mmm_plugin_next");
        get (sendBool, "mmm_plugin_send_bool");
        get (sendBools, "mmm_plugin_send_bools");
        get (sendFloat, "mmm_plugin_send_float");
        get (sendFloats, "mmm_plugin_send_floats");
        get (sendInt, "mmm_plugin_send_int");
        get (sendInts, "mmm_plugin_send_ints");
        get (sendTrig, "mmm_plugin_send_trig");
        get (sendTrigs, "mmm_plugin_send_trigs");
        get (sendString, "mmm_plugin_send_string");
        get (sendStrings, "mmm_plugin_send_strings");
        return ok;
    }

    // Send one message described as {"type", "key", "value"} - the format the
    // GUI tracer records.
    void send (Handle h, const juce::var& msg) const
    {
        auto type = msg["type"].toString();
        auto key = msg["key"].toString();
        const auto& v = msg["value"];
        auto k = key.toRawUTF8();

        if (type == "float")       sendFloat (h, k, (double) v);
        else if (type == "int")    sendInt (h, k, (int64_t) (juce::int64) v);
        else if (type == "bool")   sendBool (h, k, (bool) v ? 1 : 0);
        else if (type == "trig")   sendTrig (h, k);
        else if (type == "string") sendString (h, k, v.toString().toRawUTF8());
        else if (auto* arr = v.getArray())
        {
            auto n = (intptr_t) arr->size();
            if (type == "floats")
            {
                std::vector<double> xs; for (auto& x : *arr) xs.push_back ((double) x);
                sendFloats (h, k, xs.data(), n);
            }
            else if (type == "ints")
            {
                std::vector<int64_t> xs; for (auto& x : *arr) xs.push_back ((int64_t) (juce::int64) x);
                sendInts (h, k, xs.data(), n);
            }
            else if (type == "bools" || type == "trigs")
            {
                std::vector<uint8_t> xs; for (auto& x : *arr) xs.push_back ((bool) x ? 1 : 0);
                (type == "bools" ? sendBools : sendTrigs) (h, k, xs.data(), n);
            }
            else if (type == "strings")
            {
                juce::StringArray strs; for (auto& x : *arr) strs.add (x.toString());
                std::vector<const char*> ptrs; for (auto& s : strs) ptrs.push_back (s.toRawUTF8());
                sendStrings (h, k, ptrs.data(), n);
            }
        }
    }

    juce::String error;

    Handle (*create) (const char*, double, intptr_t, intptr_t, intptr_t) = nullptr;
    void (*destroy) (Handle) = nullptr;
    void (*setResourceDir) (const char*) = nullptr;
    int (*setSampleRate) (Handle, double) = nullptr;
    int (*setBlockSize) (Handle, intptr_t) = nullptr;
    int (*next) (Handle, const float*, float*, intptr_t) = nullptr;
    void (*sendBool) (Handle, const char*, int) = nullptr;
    void (*sendBools) (Handle, const char*, const uint8_t*, intptr_t) = nullptr;
    void (*sendFloat) (Handle, const char*, double) = nullptr;
    void (*sendFloats) (Handle, const char*, const double*, intptr_t) = nullptr;
    void (*sendInt) (Handle, const char*, int64_t) = nullptr;
    void (*sendInts) (Handle, const char*, const int64_t*, intptr_t) = nullptr;
    void (*sendTrig) (Handle, const char*) = nullptr;
    void (*sendTrigs) (Handle, const char*, const uint8_t*, intptr_t) = nullptr;
    void (*sendString) (Handle, const char*, const char*) = nullptr;
    void (*sendStrings) (Handle, const char*, const char* const*, intptr_t) = nullptr;

private:
    void* lib = nullptr;
};
