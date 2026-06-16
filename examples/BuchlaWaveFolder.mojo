from mmm_audio import *

struct BuchlaWaveFolder(Movable, Copyable):
    var world: World  
    var osc: Osc[2]
    var lag: Lag[1]
    var m: Messenger


    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[2](self.world)
        self.lag = Lag(self.world, 0.1)
        self.m = Messenger(self.world)

    def next(mut self) -> MFloat[2]:
        amp = self.lag.next(self.world[].mouse_x() * 39.0) + 1

        sample = self.osc.next[OscType.sine](40)
        sample = buchla_wavefolder(sample, amp)

        return sample
