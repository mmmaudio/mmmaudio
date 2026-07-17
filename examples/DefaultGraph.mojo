from mmm_audio import *

struct Default_Synth(Movable, Copyable):
    var world: World  
    var osc: Osc[1,Interp.sinc,TimesOversampling.x2]
    var filt: SVF[1]
    var messenger: Messenger
    var freq: Float64
    var pan: Float64

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[1,Interp.sinc,TimesOversampling.x2](self.world)
        self.filt = SVF[1](self.world)
        self.messenger = Messenger(self.world)
        self.freq = 440.0
        self.pan = -1.0

    def next(mut self) -> MFloat[2]:
        self.messenger.update("freq", self.freq) 
        self.messenger.update("pan", self.pan) 

        osc = self.osc.saw(self.freq)
        osc = self.filt.next[FilterType.lowpass](osc, 2000.0, 1.0)
        osc2 = pan2(osc, self.pan)

        return osc2 * 0.1


# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct DefaultGraph(Movable, Copyable):
    var world: World
    var synth: Default_Synth

    def __init__(out self, world: World):
        self.world = world
        self.synth = Default_Synth(self.world)

    def next(mut self) -> MFloat[2]:

        return self.synth.next()  # Get the next sample from the synth