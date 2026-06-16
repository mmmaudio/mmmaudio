
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestPM(Movable, Copyable):
    var world: World
    var mod: Osc[]
    var carrier: Osc[1, Interp.lagrange4]
    var c2: Osc[1, Interp.sinc]
    var lag: Lag[1]

    def __init__(out self, world: World):
        self.world = world
        self.mod = Osc(self.world)
        self.carrier = Osc[1, Interp.lagrange4](self.world)
        self.c2 = Osc[1, Interp.sinc](self.world)
        self.lag = Lag[1](self.world, 0.2)

    def next(mut self) -> MFloat[2]:
        mod_mul = linexp(self.world[].mouse_y(), 0.0, 1.0, 0.0001, 32.0)
        mod_signal = self.mod.next(50)
        mod_mul = self.lag.next(mod_mul)
        sample = self.carrier.next(100, mod_signal * mod_mul)
        sample2 = self.c2.next(100, mod_signal * mod_mul)
        # return (sample-sample2)
        return MFloat[2](sample * 0.1, sample2 * 0.1)