// The types MMMSCSpec.h describes a graph with. See MMMUGen.cpp.
#pragma once

#include <cstdint>

namespace MMMSC {

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

// What a Value control sends when its input changes.
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
    Value,   // sends its value (a slider)
    State,   // sends states[round(value)] (a check box or combo box)
    Trigger  // sends states[0] when the input goes from <= 0 to > 0 (a button)
};

// One control-rate input.
struct Control {
    const char* name;
    ControlKind kind;
    const Send* sends;
    int numSends;
    const MsgList* states;
    int numStates;
};

// A float list that Value controls fill one element each (an XY pad's [x, y]).
struct ListInit {
    const char* key;
    int size;
    const double* values;
};

} // namespace MMMSC
