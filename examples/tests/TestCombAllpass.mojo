
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestCombAllpass(Movable, Copyable):
    var world: World
    var synth: Impulse[1]
    var messenger: Messenger
    var which: Float64
    var comb: Comb[1, Interp.lagrange4]
    var allpass: Allpass[1, Interp.lagrange4]
    var comb2: Comb[1, Interp.lagrange4]
    var allpass2: Allpass[1, Interp.lagrange4]
    var LP_Comb: LP_Comb[1, Interp.lagrange4]
    var delay_time: Float64

    def __init__(out self, world: World):
        self.world = world
        self.synth = Impulse[1](self.world)
        self.messenger = Messenger(world)
        self.which = 0
        self.comb = Comb[1, Interp.lagrange4](self.world, max_delay_time=2.0)
        self.allpass = Allpass[1, Interp.lagrange4](self.world, max_delay_time=2.0)
        self.comb2 = Comb[1, Interp.lagrange4](self.world, max_delay_time=2.0)
        self.allpass2 = Allpass[1, Interp.lagrange4](self.world, max_delay_time=2.0)
        self.LP_Comb = LP_Comb[1, Interp.lagrange4](self.world, max_delay_time=2.0)
        self.delay_time = 0.1

    def next(mut self) -> MFloat[2]:
        self.messenger.update("which_fx", self.which)
        self.messenger.update("delay_time", self.delay_time)

        sample = self.synth.next(0.4)  # Get the next sample from the synth

        comb0 = self.comb.next(sample, self.delay_time, 0.9)
        allpass0 = self.allpass.next(sample, self.delay_time, 0.9)
        comb1 = self.comb2.next_decaytime(sample, self.delay_time, 1)
        allpass1 = self.allpass2.next_decaytime(sample, self.delay_time, 1)
        lp_comb = self.LP_Comb.next(sample, self.delay_time, 0.9, 10000.0)

        filt = select(self.which, comb0, allpass0, comb1, allpass1, lp_comb)

        return MFloat[2](sample, filt)