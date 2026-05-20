from mmm_audio import *

struct DelaySynth(Movable, Copyable):
    var world: World
    comptime maxdelay = 1.0
    var main_lag: Lag[1]
    var buf: Buffer
    var playBuf: Play
    var delays: FB_Delay[num_chans=2, interp=4]  # FB_Delay with 2 channels and interpolation type 3 ()
    var delay_time_lag: Lag[2]
    var m: Messenger
    var gate_lag: Lag[1]
    var svf: SVF[2]
    var play: Bool
    var delaytime_m: Float64
    var feedback: Float64
    var delay_input: Bool
    var ffreq: Float64
    var q: Float64
    var mix: Float64
    var main: Bool

    def __init__(out self, world: World):
        self.world = world  
        self.main_lag = Lag[1](self.world, 0.03)
        self.buf = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.delays = FB_Delay[num_chans=2, interp=4](self.world, self.maxdelay) 
        self.delay_time_lag = Lag[2](self.world, 0.2)  # Initialize Lag with a default time constant
        self.m = Messenger(self.world)
        self.gate_lag = Lag[1](self.world, 0.03)
        self.svf = SVF[2](self.world)
        self.play = True
        self.delaytime_m = 0.5
        self.feedback = -6.0
        self.delay_input = True
        self.ffreq = 8000.0
        self.q = 1
        self.mix = 0.5
        self.main = True


    def next(mut self) -> MFloat[2]:

        self.m.update("play", self.play) 
        self.m.update("feedback", self.feedback) 
        self.m.update("delay-input", self.delay_input)
        self.m.update("ffreq", self.ffreq) 
        self.m.update("delay_time", self.delaytime_m)
        self.m.update("q", self.q) 
        self.m.update("mix", self.mix) 
        self.m.update("main", self.main) 

        var sample = self.playBuf.next[num_chans=2](self.buf, 1.0 if self.play else 0.0)  # Read samples from the buffer
        deltime = self.delay_time_lag.next(MFloat[2](self.delaytime_m, self.delaytime_m * 0.9))


        fb = MFloat[2](dbamp(self.feedback), dbamp(self.feedback) * 0.9)

        delays = self.delays.next(sample * self.gate_lag.next(1.0 if self.delay_input else 0.0), deltime, fb)
        delays = self.svf.lpf(delays, self.ffreq, self.q)
        output = (self.mix * delays) + ((1.0 - self.mix) * sample)
        output *= dbamp(-12.0)
        output *= self.main_lag.next(1.0 if self.main else 0.0)
        return output

struct FeedbackDelaysGUI(Movable, Copyable):
    var world: World
    var delay_synth: DelaySynth  # Instance of the Oscillator

    def __init__(out self, world: World):
        self.world = world
        self.delay_synth = DelaySynth(self.world)  # Initialize the DelaySynth with the world instance

    def next(mut self: FeedbackDelaysGUI) -> MFloat[2]:
        return self.delay_synth.next()  # Return the combined output sample