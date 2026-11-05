// The types MMMVCVSpec.h describes a graph with. See MMMModule.cpp.
#pragma once

#include <cstdint>

namespace MMMVCV {

// The message types MMMAudio.py sends.
enum class MsgType { Bool, Bools, Float, Floats, Int, Ints, Trig, Trigs, String, Strings };

// One message. Its values are in the array its type uses: `flags` (bools and
// trigs), `floats`, `ints` or `strings`. Single values are arrays of one.
struct Msg {
    MsgType type;
    const char* key;
    intptr_t count;
    const double* floats;
    const int64_t* ints;
    const uint8_t* flags;
    const char* const* strings;
};

struct MsgList {
    const Msg* msgs;
    int count;
};

// What a Value control sends when its knob moves.
enum class SendType {
    Float,
    Int,         // truncated
    IntRound,    // rounded
    Bool,        // true at 0.5 and above
    ListElement  // element `index` of `lists[list]`, sent as a float list
};

struct Send {
    SendType type;
    const char* key;
    int list;
    int index;
};

enum class ControlKind {
    Value,   // sends its value (a GUI slider)
    State,   // sends states[round(value)] (a check box or combo box)
    Trigger  // sends states[0] when pressed (a GUI button)
};

// How a Value knob shows its value: as the struct maps it with linlin, linexp or
// lincurve(value, map[0], map[1], map[2], map[3], map[4]). It still sends the value itself.
enum class DisplayMap { None, Lin, Exp, Curve };

enum class ControlWidget {
    Knob,      // a slider: the knob turns from min to max
    SnapKnob,  // a combo box: one step per item
    Latch,     // a check box or checkable button
    Momentary, // on while held, like an XY pad's "pressed"
    Button     // a push button
};

// A button that sets another control to a value (a preset).
struct SetValue {
    int control;
    float value; // the knob's value (normalized, for a knob with a curve)
};

// One knob or button.
struct Control {
    const char* name;
    const char* label; // shown on the panel
    ControlKind kind;
    ControlWidget widget;
    const Send* sends;
    int numSends;
    const MsgList* states;
    int numStates;
    // A Value control's GUI slider: value = min + n^exp * (max - min), for n in 0..1.
    // With exp == 1 the knob turns through the values themselves.
    float min, max, exp, defaultValue;
    bool integer;        // snaps to whole numbers
    const char* const* choices; // a SnapKnob's items
    const int* randomize;       // controls a Button randomizes
    int numRandomize;
    const SetValue* sets;       // controls a Button sets
    int numSets;
    float x, y;                 // centre on the panel, in mm
    DisplayMap display;
    float map[5];               // in_min, in_max, out_min, out_max, curve
};

// A float list that Value controls fill one element each (an XY pad's [x, y]).
struct ListInit {
    const char* key;
    int size;
    const double* values;
};

struct Port {
    const char* name;  // its tooltip
    const char* label; // shown on the panel
    float x, y; // centre on the panel, in mm
    float unplugged; // an input's value while nothing is plugged in
};

} // namespace MMMVCV
