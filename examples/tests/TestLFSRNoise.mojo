from mmm_audio import *

struct TestLFSRNoise(Movable, Copyable):
    var world: World
    var lfsr: LFSRNoise[2]
    var messenger: Messenger
    var freq: MFloat[2]
    var gain: MFloat[2]
    var width1: Int
    var width2: Int

    def __init__(out self, world: World):
        self.world = world
        self.lfsr = LFSRNoise[2](world)
        self.messenger = Messenger(self.world)
        self.freq = MFloat[2](1000.0, 1010.0)
        self.gain = MFloat[2](0.2, 0.3)
        self.width1 = 15
        self.width2 = 7

    def next(mut self) -> SIMD[DType.float64, 2]:
        self.messenger.update("freq1", self.freq[0]) 
        self.messenger.update("freq2", self.freq[1]) 
        self.messenger.update("gain1", self.gain[0]) 
        self.messenger.update("gain2", self.gain[1]) 
        self.messenger.update("width1", self.width1) 
        self.messenger.update("width2", self.width2) 

        var sample = self.lfsr.next(self.freq, MInt[2](MInt[1](self.width1), MInt[1](self.width2)), False)
        return sample * self.gain