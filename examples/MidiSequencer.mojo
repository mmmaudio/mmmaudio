from mmm_audio import *

# Synth Voice - Below is a polyphonic synth. The first struct, TrigSynthVoice, is a single voice of the synth. Each voice is made up of a modulator oscillator, a carrier oscillator, and an envelope generator. 

# TrigSynthVoice follows the pattern of a triggerd PolyObject - it has a set_trigger function that Poly calls to trigger the voice.

struct TrigSynthVoice(PolyObject):
    var world: World  # Pointer to the MMMWorld instance
    var env: Env
    var mod: Osc[]
    var car: Osc[1, Interp.linear]
    var sub: Osc[]
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
        self.note = List[Float64]()
        self.trigger = False

    @always_inline
    def next(mut self) -> Float64:
        # if there is no trigger and the envelope is not active, that means the voice should be silent - output 0.0
        if not self.env.is_active and not self.trigger:
            return 0.0
        else:
            var bend_freq = self.note[0]
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
    var filt_freq: Lag[]

    var voices: List[TrigSynthVoice]
    var poly: Poly

    def __init__(out self, world: World, num_voices: Int = 64):
        self.world = world
        self.num_voices = num_voices

        self.messenger = Messenger(self.world)

        self.voices = [TrigSynthVoice(self.world) for _ in range(num_voices)]  # Initialize the list of voices

        self.svf = SVF(self.world)
        self.filt_freq = Lag(self.world, 0.1)
        self.filt_freq.input = 1000.0
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
        def notes_callback(notes: List[List[Float64]]) capturing -> None:
            for ref note in notes:
                self.trigger_note(note[0], note[1])
        self.messenger.address_callback_all[notes_callback]("notes")

        # MIDI note ons are [channel, note, velocity]. The voices have their own release, so midi_note_off is ignored.
        def note_on_callback(notes: List[List[Int]]) capturing -> None:
            for ref note in notes:
                self.trigger_note(midicps(Float64(note[1])), Float64(note[2]) / 127.0)
        self.messenger.address_callback_all[note_on_callback]("midi_note_on")

        # add the values of all the voices
        for i in range(len(self.voices)):
            out += self.voices[i].next()

        # the sequencer sets the filter with "filt_freq" and a MIDI keyboard sets it with cc 34
        def filt_freq_callback(freq: Float64) capturing -> None:
            self.filt_freq.input = freq
        self.messenger.address_callback[filt_freq_callback]("filt_freq")

        out = self.svf.lpf(out, self.filt_freq.next(), 2.0) * 0.6

        return out
