
from mmm_audio import *

comptime num: Int = 4000
comptime mul: Float64 = 1.0 / Float64(num)

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
            sample += self.osc[i].next(self.freqs[i]) * mul
        return sample

# struct TestOsc[](Movable, Copyable):
#     var world: World
#     var osc: OscBank[num]

#     def __init__(out self, world: World):
#         self.world = world
#         self.osc = OscBank[num](self.world)
#         for i in range(num):
#             self.osc.set_freq(i, rrand(100.0, 2000.0))

#     def next(mut self) -> Float64:
#         return self.osc.next(OscType.triangle)