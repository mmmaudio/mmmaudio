
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestVAMoogLadder[N: Int = 2](Movable, Copyable):
    var world: World
    var noise: WhiteNoise[Self.N]
    var filt0: VAMoogLadder[Self.N, TimesOversampling.none]  # 4-pole Moog ladder filter, no oversampling
    var filt4: VAMoogLadder[Self.N, TimesOversampling.x4]
    var filt16: VAMoogLadder[Self.N, TimesOversampling.x16]
    var m: Messenger
    var which: Float64


    def __init__(out self, world: World):
        self.world = world
        self.noise = WhiteNoise[Self.N]()
        self.filt0 = VAMoogLadder[Self.N, TimesOversampling.none](world)
        self.filt4 = VAMoogLadder[Self.N, TimesOversampling.x4](world)
        self.filt16 = VAMoogLadder[Self.N, TimesOversampling.x16](world)
        self.m = Messenger(world)
        self.which = 0.0

    def next(mut self) -> MFloat[Self.N]:
        sample = self.noise.next()  # Get the next white noise sample
        freq = linexp(self.world[].mouse_x(), 0.0, 1.0, 20.0, 24000.0)
        q = linexp(self.world[].mouse_y(), 0.0, 1.0, 0.01, 1.04)

        self.m.update("which", self.which) 
        
        sample0 = self.filt0.next(sample, freq, q)  # Get the next sample from the filter
        sample2 = self.filt4.next(sample, freq, q)  # Get the next sample from the filter
        sample4 = self.filt16.next(sample, freq, q)  # Get the next sample from the filter

        sample = select(self.which, sample0, sample2, sample4)

        return sample * 0.2


        