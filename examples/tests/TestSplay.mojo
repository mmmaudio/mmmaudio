
from mmm_audio import *

comptime num_output_channels = 16
comptime simd_out_size = 32
comptime num_osc = 500
# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestSplay(Movable, Copyable):
    var world: World
    var osc: List[Osc[2]]
    var freqs: List[Float64]
    var mult: Float64
    # var samples: List[MFloat[2]]
    var samples: InlineArray[MFloat[2], num_osc]

    def __init__(out self, world: World):
        self.world = world
        self.osc = [Osc[2](self.world) for _ in range(num_osc)]
        self.freqs = [rrand(100.0, 2000.0) for _ in range(num_osc)]
        self.mult = 0.2 / Float64(num_osc)
        # self.samples = [MFloat[2](0.0) for _ in range(num_osc)]
        self.samples = InlineArray[MFloat[2], num_osc](fill=0.0)

    def next(mut self) -> MFloat[simd_out_size]:
        for i in range(num_osc):
             self.samples[i] = self.osc[i].next(self.freqs[i])

        sample2 = splay_n[num_speakers = num_output_channels, simd_out_size = simd_out_size, pan_points = 100](self.samples, self.world)
        # sample2 = splay(self.samples, self.world)
        return sample2 * self.mult
