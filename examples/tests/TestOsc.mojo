
from mmm_audio import *

comptime N = 1
comptime num: Int = 3500
comptime mul: Float64 = 0.2 / Float64(num)

struct TestOsc[](Movable, Copyable):
    var world: World
    var osc: List[Osc[]]
    var freqs: List[Float64]

    def __init__(out self, world: World):
        self.world = world
        self.osc = [Osc[](self.world) for _ in range(num)]
        self.freqs = [rrand(100.0, 2000.0) for _ in range(num)]

    def next(mut self) -> Float64:
        sample = 0.0

        for i in range(num):
            sample += self.osc[i].next(self.freqs[i]) 
        return sample * mul
