from mmm_audio import *

# Synth Voice - Below is a polyphonic synth. The first struct, TrigSynthVoice, is a single voice of the synth. Each voice is made up of a modulator oscillator, a carrier oscillator, and an envelope generator. 

# TrigSynthVoice follows the pattern of a triggerd PolyObject - it has a set_trigger function that Poly calls to trigger the voice.

struct TrigSynthVoice(PolyObject):
    var world: World  # Pointer to the MMMWorld instance
    var env: Env
    var mod: Osc[]
    var car: Osc[1, Interp.linear]
    var sub: Osc[]
    var bend_mul: Float64
    var note: List[Float64]
    var trigger: Bool

    def check_active(mut self) -> Bool:
        return self.env.is_active


    # Poly will use this function to trigger the voice.
    def set_trigger(mut self, trigger: Bool):
        self.trigger = trigger

    def __init__(out self, world: World):
        self.world = world
        self.mod = Osc(self.world)
        self.car = Osc[1, Interp.linear](self.world)
        self.sub = Osc(self.world)
        self.env = Env(self.world)
        self.env.params = EnvParams([0.0, 1.0, 0.75, 0.75, 0.0], [0.01, 0.1, 0.2, 0.5], [1.0])
        self.bend_mul = 1.0
        self.note = List[Float64]()
        self.trigger = False

    @always_inline
    def next(mut self) -> Float64:
        # if there is no trigger and the envelope is not active, that means the voice should be silent - output 0.0
        if not self.env.is_active and not self.trigger:
            return 0.0
        else:
            var bend_freq = self.note[0] * self.bend_mul
            var mod_value = self.mod.next(bend_freq * 1.5)  
            var env = self.env.next(self.trigger)  
            var mod_mult = env * 0.5 * linlin(bend_freq, 1000, 4000, 1, 0) #decrease the mod amount as freq increases
            var car_value = self.car.next(bend_freq, mod_value * mod_mult)  

            car_value += self.sub.next(bend_freq * 0.5) 
            car_value = car_value * 0.1 * env * self.note[1]  

            return car_value

    # if you want to use this voice without Poly
    def next(mut self, trigger: Bool) -> Float64:
        self.set_trigger(trigger)
        var out = self.next()
        return out


struct MidiSequencer(Movable, Copyable):
    var world: World
    var messenger: Messenger
    var num_voices: Int
    var svf: SVF[]
    var filt_lag: Lag[]
    var filt_freq: Float64
    var bend_mul: Float64
    var notes: List[List[Float64]]
    var note_ons: List[List[Int]]
    var ccs: List[List[Int]]
    var bends: List[List[Int]]

    var voices: List[TrigSynthVoice]
    var poly: Poly

    def __init__(out self, world: World, num_voices: Int = 64):
        self.world = world
        self.num_voices = num_voices

        self.messenger = Messenger(self.world)

        self.voices = [TrigSynthVoice(self.world) for _ in range(num_voices)]  # Initialize the list of voices

        self.svf = SVF(self.world)
        self.filt_lag = Lag(self.world, 0.1)
        self.filt_freq = 1000.0
        self.bend_mul = 1.0
        self.notes = List[List[Float64]]()
        self.note_ons = List[List[Int]]()
        self.ccs = List[List[Int]]()
        self.bends = List[List[Int]]()
        self.poly = Poly(world, num_voices)

    # each trigger finds and triggers a different free voice
    def trigger_note(mut self, freq: Float64, amp: Float64):
        var voice = self.poly.next_trig(self.voices, True)
        if voice != -1:
            self.voices[voice].note = [freq, amp]

    @always_inline
    def next(mut self) -> MFloat[2]:
        var out = 0.0

        # call next_trig every sample so the voices triggered last sample are reset
        _ = self.poly.next_trig(self.voices, False)

        # the sequencer sends each note as a [freq, amplitude] list with send_floats("notes", ...)
        if self.messenger.notify_update_all("notes", self.notes):
            for ref note in self.notes:
                self.trigger_note(note[0], note[1])

        # MIDI note ons are [note, velocity, channel]. The voices have their own release, so note_off is ignored.
        if self.messenger.notify_update_all("note_on", self.note_ons):
            for ref note in self.note_ons:
                self.trigger_note(midicps(Float64(note[0])), Float64(note[1]) / 127.0)

        # add the values of all the voices
        for i in range(len(self.voices)):
            out += self.voices[i].next()

        # the sequencer sets the filter with "filt_freq" and a MIDI keyboard sets it with cc 34
        self.messenger.update("filt_freq", self.filt_freq)
        if self.messenger.notify_update_all("cc", self.ccs):
            for ref cc in self.ccs:
                if cc[0] == 34:
                    self.filt_freq = linexp(Float64(cc[1]), 0.0, 127.0, 100.0, 4000.0)

        # pitch bend is [value, channel], where value is 0 to 16383 and 8192 is no bend. Bends about a semitone either way.
        if self.messenger.notify_update_all("pitch_bend", self.bends):
            self.bend_mul = linlin(Float64(self.bends[len(self.bends) - 1][0]), 0.0, 16383.0, 0.9375, 1.0625)
            for i in range(len(self.voices)):
                self.voices[i].bend_mul = self.bend_mul

        out = self.svf.lpf(out, self.filt_lag.next(self.filt_freq), 2.0) * 0.6

        return out
