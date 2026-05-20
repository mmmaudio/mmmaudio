from mmm_audio import *

struct ParallelGraphs(Movable, Copyable):
    var world: World  
    var osc: Osc[1,Interp.sinc,1]
    var filt: SVF[1]
    var messenger: Messenger
    var freq: Float64
    var pan: Float64

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[1,Interp.sinc,1](self.world)
        self.filt = SVF[1](self.world)
        self.messenger = Messenger(self.world)
        self.freq = 440.0
        self.pan = -1.0

    def next(mut self) -> MFloat[2]:
        self.messenger.update("freq", self.freq) 
        self.messenger.update("pan", self.pan) 

        osc = self.osc.next(self.freq, osc_type=OscType.saw) 
        osc = self.filt.next[filter_type=SVFModes.lowpass](osc, 2000.0, 1.0)
        osc2 = pan2(osc, self.pan)

        return osc2 * 0.3