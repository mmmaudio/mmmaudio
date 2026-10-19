// The controls an exported editor is made of, one per kind of Qt widget the
// GUI tracer understands. Each one attaches itself to its parameter (or sends
// its messages), so an editor only has to create and position them.
#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"

namespace mmm
{
    using APVTS = juce::AudioProcessorValueTreeState;

    // A QSlider: name, horizontal slider, value box.
    struct SliderRow : juce::Component
    {
        SliderRow (APVTS& state, const juce::String& id, const juce::String& name)
        {
            label.setText (name, juce::dontSendNotification);
            label.setJustificationType (juce::Justification::centredLeft);
            slider.setSliderStyle (juce::Slider::LinearHorizontal);
            slider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 72, 20);
            addAndMakeVisible (label);
            addAndMakeVisible (slider);
            if (state.getParameter (id) != nullptr)
                attachment = std::make_unique<APVTS::SliderAttachment> (state, id, slider);
        }

        void resized() override
        {
            auto r = getLocalBounds();
            label.setBounds (r.removeFromLeft (juce::jlimit (80, 150, getWidth() / 3)));
            slider.setBounds (r);
        }

        juce::Label label;
        juce::Slider slider;
        std::unique_ptr<APVTS::SliderAttachment> attachment;
    };

    // A QCheckBox, or a checkable QPushButton (asButton).
    struct ToggleRow : juce::Component
    {
        ToggleRow (APVTS& state, const juce::String& id, const juce::String& name, bool asButton)
        {
            if (asButton)
            {
                auto b = std::make_unique<juce::TextButton> (name);
                b->setClickingTogglesState (true);
                button = std::move (b);
            }
            else
            {
                button = std::make_unique<juce::ToggleButton> (name);
            }
            addAndMakeVisible (*button);
            if (state.getParameter (id) != nullptr)
                attachment = std::make_unique<APVTS::ButtonAttachment> (state, id, *button);
        }

        void resized() override { button->setBounds (getLocalBounds()); }

        std::unique_ptr<juce::Button> button;
        std::unique_ptr<APVTS::ButtonAttachment> attachment;
    };

    // A QComboBox: name and a drop-down of the parameter's choices.
    struct ComboRow : juce::Component
    {
        ComboRow (APVTS& state, const juce::String& id, const juce::String& name)
        {
            label.setText (name, juce::dontSendNotification);
            addAndMakeVisible (label);
            addAndMakeVisible (combo);
            if (auto* p = state.getParameter (id))
            {
                combo.addItemList (p->getAllValueStrings(), 1);
                attachment = std::make_unique<APVTS::ComboBoxAttachment> (state, id, combo);
            }
        }

        void resized() override
        {
            auto r = getLocalBounds();
            label.setBounds (r.removeFromLeft (juce::jlimit (80, 150, getWidth() / 3)));
            combo.setBounds (r);
        }

        juce::Label label;
        juce::ComboBox combo;
        std::unique_ptr<APVTS::ComboBoxAttachment> attachment;
    };

    // A QPushButton: sends fixed messages on click/press/release, or moves
    // parameters (FM4's "randomize"). `node` is the button's entry in the spec.
    struct ActionButton : juce::TextButton
    {
        ActionButton (MMMAudioProcessor& p, const juce::var& node)
            : juce::TextButton (node["label"].toString()), processor (p), spec (node)
        {
            onClick = [this] { clicked(); };
            onStateChange = [this]
            {
                const bool down = isDown();
                if (down != wasDown)
                    sendAll (spec[down ? "pressed" : "released"]);
                wasDown = down;
            };
        }

        void sendAll (const juce::var& msgs)
        {
            if (auto* arr = msgs.getArray())
                for (auto& m : *arr)
                    processor.sendFromUI (m);
        }

        void clicked()
        {
            sendAll (spec["clicked"]);

            if (auto* ids = spec["randomize"].getArray())
                for (auto& id : *ids)
                    if (auto* p = processor.apvts.getParameter (id.toString()))
                    {
                        p->beginChangeGesture();
                        p->setValueNotifyingHost (random.nextFloat());
                        p->endChangeGesture();
                    }

            if (auto* values = spec["set"].getDynamicObject())
                for (auto& prop : values->getProperties())
                    if (auto* p = processor.apvts.getParameter (prop.name.toString()))
                    {
                        p->beginChangeGesture();
                        p->setValueNotifyingHost (p->convertTo0to1 ((float) prop.value));
                        p->endChangeGesture();
                    }
        }

        MMMAudioProcessor& processor;
        juce::var spec;
        bool wasDown = false;
        juce::Random random;
    };

    // A button that opened a QFileDialog and sent the path as a string.
    // `node` is its entry in the spec (label, key, mode: open/save/dir).
    struct FileRow : juce::Component
    {
        FileRow (MMMAudioProcessor& p, const juce::var& node)
            : processor (p), key (node["key"].toString()), mode (node["mode"].toString()),
              button (node["label"].toString())
        {
            button.onClick = [this] { choose(); };
            fileLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
            showFile (processor.getFile (key));
            addAndMakeVisible (button);
            addAndMakeVisible (fileLabel);
        }

        void showFile (const juce::String& path)
        {
            fileLabel.setText (juce::File (path).getFileName(), juce::dontSendNotification);
            fileLabel.setTooltip (path);
        }

        void choose()
        {
            int flags = juce::FileBrowserComponent::canSelectFiles;
            if (mode == "save")     flags = juce::FileBrowserComponent::saveMode | juce::FileBrowserComponent::canSelectFiles
                                          | juce::FileBrowserComponent::warnAboutOverwriting;
            else if (mode == "dir") flags = juce::FileBrowserComponent::canSelectDirectories;
            flags |= (mode == "save" ? 0 : juce::FileBrowserComponent::openMode);

            chooser = std::make_unique<juce::FileChooser> (button.getButtonText(), juce::File(), "*");
            chooser->launchAsync (flags, [this] (const juce::FileChooser& fc)
            {
                auto file = fc.getResult();
                if (file == juce::File())
                    return;
                processor.setFile (key, file.getFullPathName());
                showFile (file.getFullPathName());
            });
        }

        void resized() override
        {
            auto r = getLocalBounds();
            button.setBounds (r.removeFromLeft (juce::jmax (120, getWidth() / 2)));
            fileLabel.setBounds (r.withTrimmedLeft (6));
        }

        MMMAudioProcessor& processor;
        juce::String key, mode;
        juce::TextButton button;
        juce::Label fileLabel;
        std::unique_ptr<juce::FileChooser> chooser;
    };

    // Slider2D: x and y in 0..1 with y = 0 at the bottom, and an optional
    // "pressed" parameter held on while the mouse is down. Pass "" for any
    // parameter the pad doesn't have.
    struct XYPad : juce::Component
    {
        XYPad (APVTS& state, const juce::String& xId, const juce::String& yId, const juce::String& pressedId)
            : pressed (pressedId.isEmpty() ? nullptr : state.getParameter (pressedId))
        {
            if (auto* x = state.getParameter (xId))
                xAttach = std::make_unique<juce::ParameterAttachment> (*x, [this] (float v) { xv = v; repaint(); });
            if (auto* y = state.getParameter (yId))
                yAttach = std::make_unique<juce::ParameterAttachment> (*y, [this] (float v) { yv = v; repaint(); });
            if (xAttach) xAttach->sendInitialUpdate();
            if (yAttach) yAttach->sendInitialUpdate();
        }

        juce::Rectangle<float> pad() const { return getLocalBounds().toFloat().reduced (radius); }

        void paint (juce::Graphics& g) override
        {
            auto b = getLocalBounds().toFloat();
            g.setColour (juce::Colours::lightgrey);
            g.fillRect (b);
            g.setColour (juce::Colours::grey);
            for (int i = 1; i < 4; ++i)
            {
                g.drawVerticalLine ((int) (b.getWidth() * (float) i / 4.0f), 0.0f, b.getHeight());
                g.drawHorizontalLine ((int) (b.getHeight() * (float) i / 4.0f), 0.0f, b.getWidth());
            }
            g.setColour (juce::Colours::black);
            g.drawRect (b, 2.0f);

            auto p = pad();
            auto cx = p.getX() + xv * p.getWidth();
            auto cy = p.getBottom() - yv * p.getHeight();
            g.setColour (juce::Colours::blue);
            g.fillEllipse (cx - radius, cy - radius, radius * 2, radius * 2);
            g.setColour (juce::Colours::darkblue);
            g.drawEllipse (cx - radius, cy - radius, radius * 2, radius * 2, 2.0f);
        }

        void moveTo (juce::Point<float> pos)
        {
            auto p = pad();
            auto x = juce::jlimit (0.0f, 1.0f, (pos.x - p.getX()) / p.getWidth());
            auto y = juce::jlimit (0.0f, 1.0f, (p.getBottom() - pos.y) / p.getHeight());
            if (xAttach) xAttach->setValueAsPartOfGesture (x);
            if (yAttach) yAttach->setValueAsPartOfGesture (y);
        }

        void mouseDown (const juce::MouseEvent& e) override
        {
            if (pressed) { pressed->beginChangeGesture(); pressed->setValueNotifyingHost (1.0f); pressed->endChangeGesture(); }
            if (xAttach) xAttach->beginGesture();
            if (yAttach) yAttach->beginGesture();
            moveTo (e.position);
        }

        void mouseDrag (const juce::MouseEvent& e) override { moveTo (e.position); }

        void mouseUp (const juce::MouseEvent&) override
        {
            if (xAttach) xAttach->endGesture();
            if (yAttach) yAttach->endGesture();
            if (pressed) { pressed->beginChangeGesture(); pressed->setValueNotifyingHost (0.0f); pressed->endChangeGesture(); }
        }

        static constexpr float radius = 10.0f;
        juce::RangedAudioParameter* pressed;
        std::unique_ptr<juce::ParameterAttachment> xAttach, yAttach;
        float xv = 0.5f, yv = 0.5f;
    };
}
