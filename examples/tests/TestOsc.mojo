
from mmm_audio import *

comptime num: Int = 1500 * 8
comptime mul: Float64 = 1.0 / Float64(num)

struct TestOsc[](Movable, Copyable):
    var world: World
    var osc: List[Osc[]]
    var osc2: List[Osc[2,interp=Interp.linear]]
    var osc4: List[Osc[4,interp=Interp.linear]]
    var osc8: List[Osc[8,interp=Interp.linear]]
    var freqs: List[Float64]
    var which: Int
    var m: Messenger


    def __init__(out self, world: World):
        self.world = world
        self.osc = [Osc[](self.world) for _ in range(num)]
        self.osc2 = [Osc[2,interp=Interp.linear](self.world) for _ in range(num//2)]
        self.osc4 = [Osc[4,interp=Interp.linear](self.world) for _ in range(num//4)]
        self.osc8 = [Osc[8,interp=Interp.linear](self.world) for _ in range(num//8)]
        print("TestOsc: num = ", String(len(self.osc8)) + " groups of 8 = ", len(self.osc8)*8)
        self.freqs = [rrand(100.0, 2000.0) for _ in range(num)]
        self.which = 3
        self.m = Messenger(self.world)

    def next(mut self) -> Float64:
        self.m.update("which", self.which)

        if self.which == 0:
            var sample = 0.0
            for i in range(len(self.osc)):
                sample += self.osc[i].next(self.freqs[i])
            return sample * mul
        elif self.which == 1:
            var sample2 = MFloat[2](0.0)
            for i in range(len(self.osc2)):
                var freqs2 = MFloat[2](self.freqs[i*2], self.freqs[i*2 + 1])
                sample2 += self.osc2[i].next(freqs2)

            return sample2.reduce_add() * mul
        elif self.which == 2:
            var sample4 = MFloat[4](0.0)
            for i in range(len(self.osc4)):
                var freqs4 = MFloat[4](self.freqs[i*4], self.freqs[i*4 + 1], self.freqs[i*4 + 2], self.freqs[i*4 + 3])
                sample4 += self.osc4[i].next(freqs4)

            return sample4.reduce_add() * mul
        elif self.which == 3:
            var sample8 = MFloat[8](0.0)
            for i in range(len(self.osc8)):
                var freqs8 = MFloat[8](
                    self.freqs[i*8], self.freqs[i*8 + 1], self.freqs[i*8 + 2], self.freqs[i*8 + 3],
                    self.freqs[i*8 + 4], self.freqs[i*8 + 5], self.freqs[i*8 + 6], self.freqs[i*8 + 7]
                )
                sample8 += self.osc8[i].next(freqs8)
            return sample8.reduce_add() * mul
        else:
            return 0.0
