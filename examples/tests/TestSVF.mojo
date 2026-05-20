
from mmm_audio import *

struct TestSVF(Movable, Copyable):
    var world: World
    var osc: LFOsc[]
    var filts: List[Biquad[]]
    var messenger: Messenger
    var freq: Float64
    var cutoff: Float64
    var res: Float64

    def __init__(out self, world: World):
        self.world = world
        self.osc = LFOsc(self.world)
        self.messenger = Messenger(self.world)
        self.filts = List[Biquad[]](capacity=2)
        self.freq = 440
        self.cutoff = 1000.0
        self.res = 1.0
        for i in range(2):
            self.filts[i] = Biquad(self.world)

    def next(mut self) -> MFloat[2]:
        self.messenger.update("freq", self.freq) 
        sample = self.osc.next[OscType.triangle](self.freq) 
        outs = MFloat[2](0.0,0.0)
        self.cutoff = linexp(self.world[].mouse_x, 0.0, 1.0, 20.0, 20000.0)
        self.messenger.update("res", self.res) 
        outs[0] = self.filts[0].lpf(sample, self.cutoff, self.res)
        outs[1] = self.filts[1].hpf(sample, self.cutoff, self.res)
        return outs * 0.2