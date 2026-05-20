from mmm_audio import *

struct EQSynth(Movable, Copyable):
    """5-band parametric EQ processor using Biquad filters.
    
    Demonstrates: lowshelf, 3x bell, highshelf
    """
    var world: World
    var buffer: Buffer
    var num_chans: MInt[1]
    var play_buf: Play
    var lowshelf: Biquad[2]
    var bell1: Biquad[2]
    var bell2: Biquad[2]
    var bell3: Biquad[2]
    var highshelf: Biquad[2]
    var messenger: Messenger
    
    # EQ parameters
    var ls_freq: Float64
    var ls_gain: Float64
    var b1_freq: Float64
    var b1_gain: Float64
    var b1_q: Float64
    var b2_freq: Float64
    var b2_gain: Float64
    var b2_q: Float64
    var b3_freq: Float64
    var b3_gain: Float64
    var b3_q: Float64
    var hs_freq: Float64
    var hs_gain: Float64

    def __init__(out self, world: World):
        self.world = world
        
        # Load the audio buffer
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.num_chans = MInt[1](self.buffer.num_chans)
        
        # without printing this, the compiler wants to free the buffer for some reason
        print("Loaded buffer with", self.buffer.num_chans, "channels and", self.buffer.num_frames, "frames.")
        
        self.play_buf = Play(self.world)
        self.lowshelf = Biquad[2](self.world)
        self.bell1 = Biquad[2](self.world)
        self.bell2 = Biquad[2](self.world)
        self.bell3 = Biquad[2](self.world)
        self.highshelf = Biquad[2](self.world)
        self.messenger = Messenger(self.world)
        
        # Default EQ settings (flat response)
        self.ls_freq = 100.0
        self.ls_gain = 0.0
        self.b1_freq = 250.0
        self.b1_gain = 0.0
        self.b1_q = 1.0
        self.b2_freq = 1000.0
        self.b2_gain = 0.0
        self.b2_q = 1.0
        self.b3_freq = 4000.0
        self.b3_gain = 0.0
        self.b3_q = 1.0
        self.hs_freq = 8000.0
        self.hs_gain = 0.0

    def next(mut self) -> MFloat[2]:
        self.messenger.update("ls_freq", self.ls_freq)
        self.messenger.update("ls_gain", self.ls_gain)
        self.messenger.update("b1_freq", self.b1_freq)
        self.messenger.update("b1_gain", self.b1_gain)
        self.messenger.update("b1_q", self.b1_q)
        self.messenger.update("b2_freq", self.b2_freq)
        self.messenger.update("b2_gain", self.b2_gain)
        self.messenger.update("b2_q", self.b2_q)
        self.messenger.update("b3_freq", self.b3_freq)
        self.messenger.update("b3_gain", self.b3_gain)
        self.messenger.update("b3_q", self.b3_q)
        self.messenger.update("hs_freq", self.hs_freq)
        self.messenger.update("hs_gain", self.hs_gain)
        
        var out = self.play_buf.next[num_chans=2](self.buffer, 1.0, True)
        
        out = self.lowshelf.lowshelf(out, self.ls_freq, 0.707, self.ls_gain)
        out = self.bell1.bell(out, self.b1_freq, self.b1_q, self.b1_gain)
        out = self.bell2.bell(out, self.b2_freq, self.b2_q, self.b2_gain)
        out = self.bell3.bell(out, self.b3_freq, self.b3_q, self.b3_gain)
        out = self.highshelf.highshelf(out, self.hs_freq, 0.707, self.hs_gain)
        
        return out

struct BiquadEQ(Movable, Copyable):
    var world: World
    var eq_synth: EQSynth

    def __init__(out self, world: World):
        self.world = world
        self.eq_synth = EQSynth(self.world)

    def next(mut self) -> MFloat[2]:
        return self.eq_synth.next()