from mmm_audio import *

struct OscVoice(PolyObject):
    var osc: Osc[1,Interp.quad,TimesOversampling.x2]
    var tri: LFOsc[]
    var world: World
    var env: ASREnv
    var gate: Bool
    var freq: Float64
    var vol: Float64
    var wubb_rate: Float64

    def check_active(mut self) -> Bool:
        return self.env.is_active

    # Poly uses this function to open the gate on a note on and close it on the note off for the note this voice is playing.
    def set_gate(mut self, gate: Bool):
        self.gate = gate

    def __init__(out self, world: World):
        self.osc = Osc[1,Interp.quad,TimesOversampling.x2](world)
        self.tri = LFOsc(world)
        self.env = ASREnv(world)
        self.gate = False
        self.freq = 440.0
        self.vol = 1.0
        self.wubb_rate = 0.5
        self.world = world

    def next(mut self, ref buffer: Buffer) -> MFloat[1]:
        var osc_frac = self.tri.next[OscType.triangle](self.wubb_rate, 0.75, trig=self.gate) * 0.5 + 0.5
        return self.osc.next_vwt(buffer, self.freq, osc_frac = osc_frac) * self.env.next(0.01,0.2,0.1,self.gate,2) * self.vol

struct WavetableOsc(Movable, Copyable):
    comptime num_voices = 8

    var world: World  
    var poly: Poly
    var voices: List[OscVoice]
    var wavetables_per_channel: Int
    var buffer: Buffer
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
        self.file_name = "resources/Growl 15.wav"
        self.wavetables_per_channel = 256
        self.buffer = Buffer.load(self.file_name, num_wavetables=self.wavetables_per_channel)
        self.poly = Poly(self.world, Self.num_voices)
        self.voices = [OscVoice(self.world) for _ in range(Self.num_voices)]
        
        self.messenger = Messenger(self.world)
        self.filter_cutoff = 20000.0
        self.filter_resonance = 0.5
        self.moog_filter = VAMoogLadder[1,TimesOversampling.x2](self.world)
        self.note_ons = List[List[Int]]()
        self.note_offs = List[List[Int]]()
        self.ccs = List[List[Int]]()

    def loadBuffer(mut self):
        self.buffer = Buffer.load(self.file_name, num_wavetables=self.wavetables_per_channel)

    def next(mut self) -> MFloat[2]:
        self.messenger.update("wavetables_per_channel", self.wavetables_per_channel)
        if self.messenger.notify_update("load_file", self.file_name):
            self.loadBuffer()

        # note_on and note_off are [note, velocity, channel] lists, sent by MMMAudio.send_midi or by a plugin's MIDI input.
        # next_gate opens a free voice's gate for a note on and closes the gate of the voice playing that note for a note off.
        # Note offs are handled after note ons so a note that starts and stops in the same block doesn't get stuck on.
        if self.messenger.notify_update_all("note_on", self.note_ons):
            for ref note in self.note_ons:
                var voice = self.poly.next_gate(self.voices, note[0], True)
                if voice >= 0:
                    self.voices[voice].freq = midicps(Float64(note[0]))
                    self.voices[voice].vol = Float64(note[1]) / 127.0

        if self.messenger.notify_update_all("note_off", self.note_offs):
            for ref note in self.note_offs:
                _ = self.poly.next_gate(self.voices, note[0], False)

        var sample = 0.0
        for ref voice in self.voices:
            sample += voice.next(self.buffer)

        # the filter can be set directly with float messages (the NRT score does this) or with ccs from a MIDI controller
        self.messenger.update("filter_cutoff", self.filter_cutoff)
        self.messenger.update("filter_resonance", self.filter_resonance)

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
        sample = self.moog_filter.next(sample, self.filter_cutoff, self.filter_resonance)

        return sample * 0.5
