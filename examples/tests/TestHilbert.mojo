
from mmm_audio import *

struct TestHilbert(Movable, Copyable):
    var world: World
    var hilbert: Hilbert[WindowType.sine]
    var sine: Osc[]
    var m: Messenger
    var freq: MFloat[]
    var radians: MFloat[]

    def __init__(out self, world: World):
        self.world = world
        self.hilbert = Hilbert[WindowType.sine](2048, 1024, self.world)
        self.sine = Osc(self.world)
        self.m = Messenger(self.world)
        self.freq = 440.0
        self.radians = pi/2.0

    def next(mut self) -> SIMD[DType.float64,2]:
        self.m.update("freq", self.freq) 
        self.m.update("radians", self.radians) 
        s = self.sine.next(self.freq)
        o = self.hilbert.next(s, self.radians)
        return SIMD[DType.float64,2](o[0],o[1]) * 0.1

