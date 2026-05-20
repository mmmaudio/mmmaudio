from mmm_audio import *

struct TestBiquad(Movable, Copyable):
    var world: World
    var noise: WhiteNoise[1]
    var filts: List[Biquad[1]]
    var messenger: Messenger
    var cutoff: Float64
    var q: Float64

    def __init__(out self, world: World):
        self.world = world
        self.noise = WhiteNoise[1]()
        self.messenger = Messenger(self.world)
        self.filts = List[Biquad[1]](capacity=2)
        self.cutoff = 1000.0
        self.q = 1.0
        for _ in range(2):
            self.filts.append(Biquad[1](self.world))

    def next(mut self) -> MFloat[2]:
        self.messenger.update("cutoff", self.cutoff) 
        self.messenger.update("q", self.q) 
        var sample = self.noise.next()
        var outs = MFloat[2](0.0, 0.0)
        outs[0] = self.filts[0].lpf(sample, MFloat[1](self.cutoff), MFloat[1](self.q))[0]
        outs[1] = self.filts[1].hpf(sample, MFloat[1](self.cutoff), MFloat[1](self.q))[0]
        return outs * 0.2