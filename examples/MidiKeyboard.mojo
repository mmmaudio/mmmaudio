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

    def next(mut self, ref buffer: SIMDBuffer) -> MFloat[1]:
        var osc_frac = self.tri.next[OscType.triangle](self.wubb_rate, 0.75, trig=self.gate) * 0.5 + 0.5
        return self.osc.next_vwt(buffer, self.freq, osc_frac = osc_frac) * self.env.next[WindowType.hann, Interp.linear](0.01,0.2,0.7,self.gate,2) * self.vol
        
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
    var filter_cutoff: Float64
    var filter_resonance: Float64
    var moog_filter: VAMoogLadder[1,TimesOversampling.x2]
    var note_ons: List[List[Int]]
    var note_offs: List[List[Int]]
    var ccs: List[List[Int]]


    def __init__(out self, world: World):
        self.world = world
        self.file_name = "resources/small_wavetable8.wav"
        
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)
        
        self.poly = Poly(self.world, Self.num_voices)
        self.voices = [OscVoice(self.world) for _ in range(self.num_voices)]

        self.messenger = Messenger(self.world)
        self.filter_cutoff = 20000.0
        self.filter_resonance = 0.5
        self.moog_filter = VAMoogLadder[1,TimesOversampling.x2](self.world)
        self.note_ons = List[List[Int]]()
        self.note_offs = List[List[Int]]()
        self.ccs = List[List[Int]]()

    def loadBuffer(mut self):
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)

    def next(mut self) -> MFloat[2]:
        if self.messenger.notify_update("load_file", self.file_name):
            self.loadBuffer()

        # note_on and note_off are [note, velocity, channel] lists. notify_update_all gives every
        # message sent since the last block, in the order they were sent.
        # next_gate opens a free voice's gate for a note on...
        if self.messenger.notify_update_all("note_on", self.note_ons):
            for ref note in self.note_ons:
                var voice = self.poly.next_gate(self.voices, note[0], True)
                if voice >= 0:
                    var midi = Float64(note[0]) + self.voices[voice].just_offset[note[0] % 12]
                    self.voices[voice].freq = midicps(midi)
                    self.voices[voice].vol = Float64(note[1]) / 127.0

        # ...and closes the gate of the voice playing that note for a note off. Note offs are handled after
        # note ons so a note that starts and stops in the same block doesn't get stuck on.
        if self.messenger.notify_update_all("note_off", self.note_offs):
            for ref note in self.note_offs:
                _ = self.poly.next_gate(self.voices, note[0], False)

        # add the output of all the voices
        var out = 0.0
        for ref voice in self.voices:
            out += voice.next(self.buffer)

        # cc is [controller, value, channel]: cc 1 sets the wubb rate of all the voices, 33 the filter cutoff and 34 the resonance
        if self.messenger.notify_update_all("cc", self.ccs):
            for ref cc in self.ccs:
                var val = Float64(cc[1])
                if cc[0] == 1:
                    var wubb_rate = linexp(val, 0.0, 127.0, 0.1, 10.0)
                    for ref voice in self.voices:
                        voice.wubb_rate = wubb_rate
                elif cc[0] == 33:
                    self.filter_cutoff = linexp(val, 0.0, 127.0, 20.0, 20000.0)
                elif cc[0] == 34:
                    self.filter_resonance = linexp(val, 0.0, 127.0, 0.1, 1.0)
        out = self.moog_filter.next(out, self.filter_cutoff, self.filter_resonance)

        return out * 0.5
