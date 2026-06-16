
from mmm_audio import *

comptime ov_samp = TimesOversampling.x16
struct TestUpsample(Movable, Copyable):
    var world: World
    var osc: Osc[]
    var upsampler: Upsampler[1, ov_samp]
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc(world)
        self.upsampler = Upsampler[1, ov_samp](world)
        self.messenger = Messenger(world)

    def next(mut self) -> MFloat[2]:

        sample = self.osc.next[OscType.triangle](self.world[].mouse_y() * 200.0 + 20.0)
        sample2 = 0.0
        for i in range(ov_samp.times):
            sample2 = self.upsampler.next(sample, i)

        return MFloat[2](sample, sample2) * 0.2
