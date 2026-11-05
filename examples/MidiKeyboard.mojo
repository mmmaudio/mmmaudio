from mmm_audio import *

struct OscVoice(PolyObject):
    var osc: Osc[1,Interp.sinc]
    var tri: LFOsc[]
    var world: World
    var env: ASREnv
    var gate: Bool
    var freq: Float64
    var vol: Float64
    var wubb_rate: Float64
    var messenger: Messenger
    var triggered: Bool
    var just_offset: List[Float64]
    var bend_mul: Float64

    def check_active(mut self) -> Bool:
        return self.env.is_active
    
    # Poly will use this function to release the voice when it receives a note off message for the note that this voice is playing. 
    def set_gate(mut self, gate: Bool):
        self.gate = gate

    def __init__(out self, world: World, name_space: String = ""):
        self.osc = Osc[1,Interp.sinc](world)
        self.tri = LFOsc(world)
        self.env = ASREnv(world)
        self.gate = False
        self.freq = 440.0
        self.vol = 1.0
        self.wubb_rate = 0.5
        self.messenger = Messenger(world, name_space)
        self.world = world
        self.triggered = False
        self.just_offset = [0.0, 0.1173, 0.0391, 0.1564, -0.1369, -0.0196, -0.0978, 0.0196, 0.1369, -0.1564, 0.1760, -0.1173]
        self.bend_mul = 1.0

    def next(mut self, ref buffer: SIMDBuffer) -> MFloat[1]:
        var osc_frac = self.tri.next[OscType.triangle](self.wubb_rate, 0.75, trig=self.gate) * 0.5 + 0.5
        return self.osc.next_vwt(buffer, self.freq*self.bend_mul, osc_frac = osc_frac) * self.env.next[WindowType.hann, Interp.linear](0.01,0.2,0.7,self.gate,2) * self.vol
        
struct MidiKeyboard(Movable, Copyable):
    comptime num_voices = 16
    comptime wavetables_per_channel = 8
    comptime num_messages = 10

    var world: World

    var poly: Poly
    var voices: List[OscVoice]

    var buffer: SIMDBuffer[Self.wavetables_per_channel]
    var file_name: String
    var messenger: Messenger
    var filter_cutoff: Lag[]
    var filter_resonance: Float64
    var moog_filter: VAMoogLadder[1,TimesOversampling.x2]
    var ccs: List[List[Int]]
    var bend_mul: Float64


    def __init__(out self, world: World):
        self.world = world
        self.file_name = "resources/small_wavetable8.wav"
        
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)
        
        self.poly = Poly(self.world, Self.num_voices)
        self.voices = [OscVoice(self.world) for _ in range(self.num_voices)]

        self.messenger = Messenger(self.world)
        self.filter_cutoff = Lag(self.world, 0.1)
        self.filter_cutoff.input = 20000.0
        self.filter_resonance = 0.5
        self.moog_filter = VAMoogLadder[1,TimesOversampling.x2](self.world)
        self.ccs = List[List[Int]]()
        self.bend_mul = 1.0

    def loadBuffer(mut self):
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)

    def next(mut self) -> MFloat[2]:
        if self.messenger.notify_update("load_file", self.file_name):
            self.loadBuffer()

        # midi_note_on and midi_note_off are [channel, note, velocity] lists. notify_update_all gives every
        # message sent since the last block, in the order they were sent.
        # next_gate opens a free voice's gate for a note on...
        
        def on_callback(notes: List[List[Int]]) capturing -> None:
            for ref note in notes:
                var voice = self.poly.next_gate(self.voices, note[1], True)
                if voice >= 0:
                    var midi = Float64(note[1]) + self.voices[voice].just_offset[note[1] % 12]
                    self.voices[voice].freq = midicps(midi)
                    self.voices[voice].vol = Float64(note[2]) / 127.0
        self.messenger.address_callback_all[on_callback]("midi_note_on")

        # ...and closes the gate of the voice playing that note for a note off. Note offs are handled after
        # note ons so a note that starts and stops in the same block doesn't get stuck on.
        def off_callback(notes: List[List[Int]]) capturing -> None:
            for ref note in notes:
                _ = self.poly.next_gate(self.voices, note[1], False)
        self.messenger.address_callback_all[off_callback]("midi_note_off")
                

        # add the output of all the voices
        var out = 0.0
        for ref voice in self.voices:
            out += voice.next(self.buffer)

        # cc is [channel, controller, value]: cc 1 sets the wubb rate of all the voices, 33 the filter cutoff and 34 the resonance
        def cc_callback(ccs: List[List[Int]]) capturing -> None:
            for ref cc in ccs:
                var val = Float64(cc[2])
                if cc[1] == 1:
                    var wubb_rate = linexp(val, 0.0, 127.0, 0.1, 10.0)
                    for ref voice in self.voices:
                        voice.wubb_rate = wubb_rate
                elif cc[1] == 33:
                    self.filter_cutoff.input = linexp(val, 0.0, 127.0, 20.0, 20000.0)
                elif cc[1] == 34:
                    self.filter_resonance = linexp(val, 0.0, 127.0, 0.1, 1.0)
        self.messenger.address_callback_all[cc_callback]("midi_cc")

        # pitch bend is [channel, value], where value is 0 to 16383 and 8192 is no bend. Bends about a semitone either way.
        # only the latest bend in a block matters, so this takes just the last one
        def bend_callback(bend: List[Int]) capturing -> None:
            self.bend_mul = linlin(Float64(bend[1]), 0.0, 16383.0, 0.9375, 1.0625)
            for i in range(len(self.voices)):
                self.voices[i].bend_mul = self.bend_mul
        self.messenger.address_callback[bend_callback]("midi_pitch_bend")

        out = self.moog_filter.next(out, self.filter_cutoff.next(), self.filter_resonance)

        return out * 0.5
