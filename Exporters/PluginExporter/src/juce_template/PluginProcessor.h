// A generic JUCE processor around one MMMAudio graph. Everything specific to
// the graph comes from MMMPluginSpec.h, which export_plugin.py generates.
#pragma once

#include <JuceHeader.h>
#include "MMMBridge.h"

class MMMAudioProcessor : public juce::AudioProcessor
{
public:
    MMMAudioProcessor();
    ~MMMAudioProcessor() override;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    using AudioProcessor::processBlock;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override;
    bool acceptsMidi() const override;
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram (int) override {}
    const juce::String getProgramName (int) override { return {}; }
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    // Send a message ({"type","key","value"}) from the message thread. Safe
    // while audio runs; held back until the engine exists.
    void sendFromUI (const juce::var& msg);

    // A file chosen in the editor: remembered in the plug-in state and sent
    // as a string message (again whenever the graph is rebuilt).
    void setFile (const juce::String& key, const juce::String& path);
    juce::String getFile (const juce::String& key) const;

    juce::var spec;   // parsed from MMMPluginSpec.h; must precede apvts
    juce::AudioProcessorValueTreeState apvts;
    juce::String loadError;

private:
    struct ParamLink
    {
        std::atomic<float>* raw = nullptr;
        juce::String kind;               // float, bool, choice
        // type "list": write element `index` of lists[list] instead of sending
        struct Send { std::string key; juce::String type, map; int list = -1, index = 0; };
        std::vector<Send> sends;         // float params
        juce::Array<juce::var> states;   // bool/choice params: messages per state
        float last = std::numeric_limits<float>::quiet_NaN();
    };

    // A float list message several parameters fill in, one element each (an
    // XY pad sending [x, y]). Sent once per block when any element changed.
    struct ListSend
    {
        std::string key;
        std::vector<double> values;
        bool dirty = false;
    };

    static BusesProperties makeBuses();
    void sendParams (MMMBridge::Handle h);
    void sendMidi (MMMBridge::Handle h, const juce::MidiMessage& m);
    void sendSetup (MMMBridge::Handle h);

    MMMBridge bridge;
    std::atomic<MMMBridge::Handle> handle { 0 };
    std::vector<ParamLink> links;
    std::vector<ListSend> lists;

    std::vector<float> interleavedIn, interleavedOut;
    int maxBlock = 0;

    juce::CriticalSection uiLock;
    juce::Array<juce::var> pendingUI;
    juce::StringPairArray files;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MMMAudioProcessor)
};
