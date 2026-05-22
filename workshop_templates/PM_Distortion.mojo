
# get it working
# add messages for the frequency
# add the wavefolder back in
# talk through the interpolation and oversampling options

from mmm_audio import *
struct PM_Distortion(Movable, Copyable):
    var world: World
    var mod: Osc[]
    var carrier: Osc[1, Interp.lagrange4, 1]
    var xy: MFloat[2]
    var lag: Lag[2]
    var folder: BuchlaWavefolder[1, 1]
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.mod = Osc(self.world)
        self.carrier = Osc[1, Interp.lagrange4, 1](self.world)
        
        self.xy = MFloat[2](0.0, 0.0)
        self.lag = Lag[2](self.world, 0.2)

        self.folder = BuchlaWavefolder[1, 1](self.world)
        self.m = Messenger(self.world)

    def next(mut self) -> MFloat[2]:
        # get some messages
        self.m.update("x", self.xy[0])
        self.m.update("y", self.xy[1])

        xy = self.lag.next(self.xy)

        mod_mul = linexp(xy[1], 0.0, 1.0, 0.0001, 16.0)

        mod_signal = self.mod.next(50)
        
        sample = self.carrier.next(100, mod_signal * mod_mul)

        # the wavefolder adds some real aggression
        # folder_amp = xy[0] * 30.0 + 1.0
        # sample = self.folder.next(sample, folder_amp)

        return MFloat[2](sample * 0.1)