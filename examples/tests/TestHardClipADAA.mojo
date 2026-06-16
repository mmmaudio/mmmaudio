

from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestHardClipADAA[num_chans: Int = 2](Movable, Copyable):
    var world: World
    var osc: Osc[]
    var lag: Lag[]
    var clip: SoftClipAD[1,TimesOversampling.x16]
    var overdrive: TanhAD[Self.num_chans]

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc(world)
        self.clip = SoftClipAD[1,TimesOversampling.x16](world)
        self.overdrive = TanhAD[Self.num_chans](world)
        self.lag = Lag(world)

    def next(mut self) -> MFloat[Self.num_chans]:
        sample = self.osc.next(self.world[].mouse_y() * 40.0 + 20)  # Get the next white noise sample
        gain = self.lag.next(self.world[].mouse_x() * (20.0)) + 1.0

        sample2 = self.clip.next(sample*gain) 
        # sample = self.overdrive.next(sample*gain)
        return MFloat[self.num_chans](sample, sample2)*0.5


        