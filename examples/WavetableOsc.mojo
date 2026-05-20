from mmm_audio import *

struct OscVoice(Movable, Copyable):
    var osc: Osc[1,Interp.quad,1]
    var tri: LFOsc[]
    var world: World
    var env: ASREnv
    var gate: Bool
    var freq: Float64
    var wubb_rate: Float64
    var messenger: Messenger

    def __init__(out self, world: World, name_space: String = ""):
        self.osc = Osc[1,Interp.quad,1](world)
        self.tri = LFOsc(world)
        self.env = ASREnv(world)
        self.gate = False
        self.freq = 440.0
        self.wubb_rate = 0.5
        self.messenger = Messenger(world, name_space)
        self.world = world

    def next(mut self, ref buffer: Buffer) -> MFloat[1]:
        self.messenger.update("gate", self.gate) 
        self.messenger.update("freq", self.freq) 
        self.messenger.update("wubb_rate", self.wubb_rate)
        osc_frac = self.tri.next[OscType.triangle](self.wubb_rate, 0.75, trig=self.gate) * 0.5 + 0.5
        return self.osc.next_vwt(buffer, self.freq, osc_frac = osc_frac) * self.env.next(0.01,0.2,0.1,self.gate,2)

struct WavetableOsc(Movable, Copyable):
    var world: World  
    var osc_voices: List[OscVoice]
    var wavetables_per_channel: Int
    var buffer: Buffer
    var file_name: String
    var messenger: Messenger
    var filter_cutoff: Float64
    var filter_resonance: Float64
    var moog_filter: VAMoogLadder[1,1]

    def __init__(out self, world: World):
        self.world = world
        self.file_name = "resources/Growl 15.wav"
        self.wavetables_per_channel = 256
        self.buffer = Buffer.load(self.file_name, num_wavetables=self.wavetables_per_channel)
        self.osc_voices = List[OscVoice]()
        for i in range(8):
            self.osc_voices.append(OscVoice(self.world, "voice_"+String(i)))
        
        self.messenger = Messenger(self.world)
        self.filter_cutoff = 20000.0
        self.filter_resonance = 0.5
        self.moog_filter = VAMoogLadder[1,1](self.world)

    def loadBuffer(mut self):
        self.buffer = Buffer.load(self.file_name, num_wavetables=self.wavetables_per_channel)

    def next(mut self) -> MFloat[2]:
        self.messenger.update("wavetables_per_channel", self.wavetables_per_channel)
        if self.messenger.notify_update("load_file", self.file_name):
            self.loadBuffer()

        var sample = 0.0
        for ref voice in self.osc_voices:
            sample += voice.next(self.buffer)

        self.messenger.update("filter_cutoff", self.filter_cutoff)
        self.messenger.update("filter_resonance", self.filter_resonance)
        sample = self.moog_filter.next(sample, self.filter_cutoff, self.filter_resonance)

        return sample * 0.5
