
from mmm_audio import *

struct TestDelay(Movable, Copyable):
    var world: World
    var synth: Phasor[]
    var delay: Delay[interp = Interp.lagrange4]
    var del_time: Float64
    var freq: Float64
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.synth = Phasor(self.world)
        self.delay = Delay[interp = Interp.lagrange4](self.world, Int(4800))
        self.freq = 0.5
        self.del_time = 0.5
        self.messenger = Messenger(world)

    def next(mut self) -> MFloat[2]:
        self.messenger.update("freq", self.freq) 
        # self.messenger.update("del_time", self.del_time)
        self.del_time = self.world[].mouse_x() * 0.11

        trig = self.messenger.notify_trig("trig")
        sample = self.synth.next_impulse(self.freq, 0.0, MBool[1](fill=trig))  # Get the next sample from the synth
        delay = self.delay.next(sample, self.del_time)  # Process the sample through the delay line
        return MFloat[2](sample, delay) * 0.2  # Get the next sample from the synth
