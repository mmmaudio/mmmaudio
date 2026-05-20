from mmm_audio import *

struct VariableOsc(Movable, Copyable):
    var world: World  
    # for efficiency we set the interpolation and oversampling in the constructor
    # so here we have sinc interpolation with 2x oversampling
    # var osc: Osc[1,2,1]
    # var lag: Lag[1]
    var osc: Osc[2,Interp.sinc,os_index=1]
    var lag: Lag[2]
    var m: Messenger
    var x: Float64
    var y: Float64
    var is_down: Bool
    var asr: ASREnv

    def __init__(out self, world: World):
        self.world = world
        # for efficiency we set the interpolation and oversampling in the constructor
        self.osc = Osc[2,Interp.sinc,os_index=1](self.world)
        self.lag = Lag[2](self.world, 0.1)
        self.m = Messenger(self.world)
        self.x = 0.0
        self.y = 0.0
        self.is_down = False
        self.asr = ASREnv(self.world)

    def next(mut self) -> MFloat[2]:
        self.m.update("x", self.x) 
        self.m.update("y", self.y) 
        self.m.update("mouse_down", self.is_down)

        env = self.asr.next(0.05, 1, 0.05, self.is_down)

        # freq = self.world[].mouse_y
        freq = MFloat[2](1-self.y, self.y)
        freq = self.lag.next(freq)
        freq = linexp(freq, 0.0, 1.0, 100, 10000)

        # osc_frac = self.world[].mouse_x
        osc_frac = MFloat[2](1-self.x, self.x)
        sample = self.osc.next_basic_waveforms(freq, osc_frac = osc_frac)

        return sample * 0.1 * env
