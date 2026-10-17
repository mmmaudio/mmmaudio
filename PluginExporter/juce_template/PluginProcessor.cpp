#include "PluginProcessor.h"
#include "PluginEditor.h"
#include "MMMPluginSpec.h"

juce::AudioProcessor::BusesProperties MMMAudioProcessor::makeBuses()
{
    BusesProperties buses;
    if (MMMSpec::numIn > 0)
        buses = buses.withInput ("Input", juce::AudioChannelSet::canonicalChannelSet (MMMSpec::numIn), true);
    return buses.withOutput ("Output", juce::AudioChannelSet::canonicalChannelSet (MMMSpec::numOut), true);
}

namespace
{
    // ControlSpec's curve: value = min + (max - min) * norm^exp
    juce::NormalisableRange<float> controlSpecRange (float lo, float hi, float exp)
    {
        return { lo, hi,
                 [exp] (float s, float e, float n) { return s + (e - s) * std::pow (n, exp); },
                 [exp] (float s, float e, float v) { return std::pow (juce::jlimit (0.0f, 1.0f, (v - s) / (e - s)), 1.0f / exp); },
                 nullptr };
    }

    juce::AudioProcessorValueTreeState::ParameterLayout makeParameters (const juce::var& spec)
    {
        juce::AudioProcessorValueTreeState::ParameterLayout layout;

        for (auto& p : *spec["params"].getArray())
        {
            juce::ParameterID id { p["id"].toString(), 1 };
            auto name = p["name"].toString();
            auto kind = p["kind"].toString();

            if (kind == "float")
            {
                int decimals = p["decimals"];
                auto attrs = juce::AudioParameterFloatAttributes()
                                 .withStringFromValueFunction ([decimals] (float v, int) { return juce::String (v, decimals); });
                layout.add (std::make_unique<juce::AudioParameterFloat> (
                    id, name, controlSpecRange (p["min"], p["max"], p["exp"]), (float) p["default"], attrs));
            }
            else if (kind == "bool")
            {
                layout.add (std::make_unique<juce::AudioParameterBool> (id, name, (bool) p["default"]));
            }
            else if (kind == "choice")
            {
                juce::StringArray choices;
                for (auto& c : *p["choices"].getArray())
                    choices.add (c.toString());
                layout.add (std::make_unique<juce::AudioParameterChoice> (id, name, choices, (int) p["default"]));
            }
        }
        return layout;
    }
}

MMMAudioProcessor::MMMAudioProcessor()
    : AudioProcessor (makeBuses()),
      spec (juce::JSON::parse (juce::String::fromUTF8 (MMMSpec::json))),
      apvts (*this, nullptr, "MMMState", makeParameters (spec))
{
    if (auto* ls = spec["lists"].getArray())
        for (auto& l : *ls)
        {
            ListSend list;
            list.key = l["key"].toString().toStdString();
            if (auto* vals = l["values"].getArray())
                for (auto& v : *vals)
                    list.values.push_back ((double) v);
            lists.push_back (std::move (list));
        }

    for (auto& p : *spec["params"].getArray())
    {
        ParamLink link;
        link.raw = apvts.getRawParameterValue (p["id"].toString());
        link.kind = p["kind"].toString();
        if (auto* sends = p["sends"].getArray())
            for (auto& s : *sends)
                link.sends.push_back ({ s["key"].toString().toStdString(), s["type"].toString(), s["map"].toString(),
                                        (int) s.getProperty ("list", -1), (int) s.getProperty ("index", 0) });
        if (auto* states = p["states"].getArray())
            link.states = *states;
        links.push_back (std::move (link));
    }

    juce::StringArray runtime;
    for (auto* lib : MMMSpec::runtimeLibs)
        runtime.add (lib);

    if (! bridge.load (MMMSpec::bridgeLib, runtime))
    {
        loadError = bridge.error;
        DBG (loadError);
    }
}

MMMAudioProcessor::~MMMAudioProcessor()
{
    if (auto h = handle.exchange (0))
        bridge.destroy (h);
}

const juce::String MMMAudioProcessor::getName() const { return MMMSpec::name; }
// Every plug-in takes MIDI, so any graph can respond to notes and controllers - see sendMidi.
bool MMMAudioProcessor::acceptsMidi() const { return true; }

bool MMMAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    if (layouts.getMainOutputChannels() != MMMSpec::numOut)
        return false;
    if (MMMSpec::numIn > 0)
        return layouts.getMainInputChannels() == MMMSpec::numIn || layouts.getMainInputChannelSet().isDisabled();
    return true;
}

void MMMAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    if (! loadError.isEmpty())
        return;

    maxBlock = juce::jmax (1, samplesPerBlock);
    interleavedIn.assign ((size_t) (maxBlock * juce::jmax (1, MMMSpec::numIn)), 0.0f);
    interleavedOut.assign ((size_t) (maxBlock * MMMSpec::numOut), 0.0f);

    // Building the graph may load files; point relative paths at our copies.
    bridge.setResourceDir (MMMBridge::resourceDirectory().getFullPathName().toRawUTF8());

    auto h = handle.load();
    if (h == 0)
    {
        auto graph = MMMBridge::libraryDirectory().getChildFile (MMMSpec::graphLib).getFullPathName();
        h = bridge.create (graph.toRawUTF8(), sampleRate, maxBlock, MMMSpec::numIn, MMMSpec::numOut);
        if (h == 0)
        {
            loadError = "could not create the MMMAudio graph from " + graph;
            return;
        }
    }
    else
    {
        bridge.setBlockSize (h, maxBlock);
        bridge.setSampleRate (h, sampleRate);   // rebuilds the graph only if the rate changed
    }

    // A new (or rebuilt) graph starts from its defaults, so it gets every
    // setup message and parameter value again.
    sendSetup (h);
    for (auto& link : links)
        link.last = std::numeric_limits<float>::quiet_NaN();

    const juce::ScopedLock sl (uiLock);
    handle.store (h);
    for (auto& msg : pendingUI)
        bridge.send (h, msg);
    pendingUI.clear();
}

void MMMAudioProcessor::sendSetup (MMMBridge::Handle h)
{
    for (auto& msg : *spec["init"].getArray())
        bridge.send (h, msg);

    const juce::ScopedLock sl (uiLock);
    for (auto& key : files.getAllKeys())
        bridge.sendString (h, key.toRawUTF8(), files[key].toRawUTF8());
}

void MMMAudioProcessor::sendParams (MMMBridge::Handle h)
{
    for (auto& link : links)
    {
        auto v = link.raw->load();
        if (v == link.last)
            continue;
        link.last = v;

        if (link.kind == "float")
        {
            for (auto& s : link.sends)
            {
                if (s.type == "float")     bridge.sendFloat (h, s.key.c_str(), v);
                else if (s.type == "int")  bridge.sendInt (h, s.key.c_str(), s.map == "round" ? (int64_t) std::llround (v) : (int64_t) v);
                else if (s.type == "bool") bridge.sendBool (h, s.key.c_str(), v >= 0.5f ? 1 : 0);
                else if (s.type == "list" && juce::isPositiveAndBelow (s.list, (int) lists.size()))
                {
                    auto& list = lists[(size_t) s.list];
                    if (juce::isPositiveAndBelow (s.index, (int) list.values.size()))
                    {
                        list.values[(size_t) s.index] = v;
                        list.dirty = true;
                    }
                }
            }
        }
        else
        {
            auto state = juce::jlimit (0, juce::jmax (0, link.states.size() - 1), (int) std::lround (v));
            if (auto* msgs = link.states[state].getArray())
                for (auto& msg : *msgs)
                    bridge.send (h, msg);
        }
    }

    // Each list goes out once, with every element set this block.
    for (auto& list : lists)
        if (list.dirty)
        {
            list.dirty = false;
            bridge.sendFloats (h, list.key.c_str(), list.values.data(), (intptr_t) list.values.size());
        }
}

// Forwards one MIDI event to the graph as an Int list message. Every message
// sent under a name during a block is pooled, so a graph reads them all, in
// order, with Messenger.notify_update_all into a List[List[Int]]:
//
//   "note_on"          [note, velocity, channel]
//   "note_off"         [note, velocity, channel]   (includes note ons with velocity 0)
//   "cc"               [controller, value, channel]
//   "pitch_bend"       [value, channel]            (0 to 16383, 8192 is no bend)
//   "poly_aftertouch"  [note, pressure, channel]
//   "channel_pressure" [pressure, channel]
//   "program_change"   [program, channel]
//
// Channels are 1 to 16. Anything else (sysex, clock, ...) is ignored.
void MMMAudioProcessor::sendMidi (MMMBridge::Handle h, const juce::MidiMessage& m)
{
    const int64_t chan = m.getChannel();
    auto send = [&] (const char* key, std::initializer_list<int64_t> vals)
    {
        bridge.sendInts (h, key, vals.begin(), (intptr_t) vals.size());
    };

    if (m.isNoteOn())                send ("note_on", { m.getNoteNumber(), m.getVelocity(), chan });
    else if (m.isNoteOff())          send ("note_off", { m.getNoteNumber(), m.getVelocity(), chan });
    else if (m.isController())       send ("cc", { m.getControllerNumber(), m.getControllerValue(), chan });
    else if (m.isPitchWheel())       send ("pitch_bend", { m.getPitchWheelValue(), chan });
    else if (m.isAftertouch())       send ("poly_aftertouch", { m.getNoteNumber(), m.getAfterTouchValue(), chan });
    else if (m.isChannelPressure())  send ("channel_pressure", { m.getChannelPressureValue(), chan });
    else if (m.isProgramChange())    send ("program_change", { m.getProgramChangeNumber(), chan });
}

void MMMAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi)
{
    juce::ScopedNoDenormals noDenormals;

    auto h = handle.load();
    const int numFrames = buffer.getNumSamples();
    const int numIn = juce::jmin (getTotalNumInputChannels(), MMMSpec::numIn);
    const int numOut = juce::jmin (buffer.getNumChannels(), MMMSpec::numOut);

    if (h == 0 || maxBlock == 0)
    {
        buffer.clear();
        return;
    }

    sendParams (h);

    for (int start = 0; start < numFrames; start += maxBlock)
    {
        const int n = juce::jmin (maxBlock, numFrames - start);

        // The graph reads messages at the top of each block it renders, so
        // each event goes in with the chunk it falls in.
        for (const auto meta : midi)
            if (meta.samplePosition >= start && meta.samplePosition < start + n)
                sendMidi (h, meta.getMessage());

        // JUCE gives one array per channel; the engine wants frames interleaved.
        const float* in = nullptr;
        if (numIn > 0)
        {
            std::fill (interleavedIn.begin(), interleavedIn.end(), 0.0f);
            for (int c = 0; c < numIn; ++c)
            {
                auto* src = buffer.getReadPointer (c, start);
                for (int i = 0; i < n; ++i)
                    interleavedIn[(size_t) (i * MMMSpec::numIn + c)] = src[i];
            }
            in = interleavedIn.data();
        }

        bridge.next (h, in, interleavedOut.data(), n);

        for (int c = 0; c < numOut; ++c)
        {
            auto* dst = buffer.getWritePointer (c, start);
            for (int i = 0; i < n; ++i)
                dst[i] = interleavedOut[(size_t) (i * MMMSpec::numOut + c)];
        }
    }

    for (int c = numOut; c < buffer.getNumChannels(); ++c)
        buffer.clear (c, 0, numFrames);
}

void MMMAudioProcessor::sendFromUI (const juce::var& msg)
{
    const juce::ScopedLock sl (uiLock);
    if (auto h = handle.load())
        bridge.send (h, msg);
    else
        pendingUI.add (msg);
}

void MMMAudioProcessor::setFile (const juce::String& key, const juce::String& path)
{
    {
        const juce::ScopedLock sl (uiLock);
        files.set (key, path);
    }
    auto* msg = new juce::DynamicObject();
    msg->setProperty ("type", "string");
    msg->setProperty ("key", key);
    msg->setProperty ("value", path);
    sendFromUI (juce::var (msg));
}

juce::String MMMAudioProcessor::getFile (const juce::String& key) const
{
    const juce::ScopedLock sl (uiLock);
    return files[key];
}

void MMMAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    auto state = apvts.copyState();
    juce::ValueTree fileTree ("Files");
    {
        const juce::ScopedLock sl (uiLock);
        for (auto& key : files.getAllKeys())
            fileTree.setProperty (key, files[key], nullptr);
    }
    state.removeChild (state.getChildWithName ("Files"), nullptr);
    state.appendChild (fileTree, nullptr);

    if (auto xml = state.createXml())
        copyXmlToBinary (*xml, destData);
}

void MMMAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    auto xml = getXmlFromBinary (data, sizeInBytes);
    if (xml == nullptr || ! xml->hasTagName (apvts.state.getType()))
        return;

    auto state = juce::ValueTree::fromXml (*xml);
    auto fileTree = state.getChildWithName ("Files");
    for (int i = 0; i < fileTree.getNumProperties(); ++i)
    {
        auto key = fileTree.getPropertyName (i).toString();
        setFile (key, fileTree[key].toString());
    }
    state.removeChild (fileTree, nullptr);
    apvts.replaceState (state);
}

juce::AudioProcessorEditor* MMMAudioProcessor::createEditor()
{
    return new MMMAudioEditor (*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new MMMAudioProcessor();
}
