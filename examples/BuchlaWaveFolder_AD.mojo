from mmm_audio import *

struct BuchlaWaveFolder_AD(Movable, Copyable):
    var world: World  
    var osc: Osc[2]
    var lag: Lag[1]
    var b259: BuchlaWavefolder[2, TimesOversampling.x2]
    var m: Messenger
    var order: Int


    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[2](world)
        self.lag = Lag(world, 0.1)
        self.b259 = BuchlaWavefolder[2, TimesOversampling.x2](world)
        self.m = Messenger(world)
        self.order = 1

    def next(mut self) -> MFloat[2]:
        def callback(val: Int) capturing -> None:
            self.order = val if val >= 2 else 1
        self.m.address_callback[callback]("order")

        var amp = self.lag.next(self.world[].mouse_x() * 30.0) + 1

        var freq = self.world[].mouse_y() * 200 + 30

        var sample = self.osc.next[OscType.sine](freq)

        if self.order == 1:
            sample = self.b259.next[1](sample, amp) # first order antiderivative
        else:
            sample = self.b259.next[2](sample, amp) # second order antiderivative

        return sample * 0.5