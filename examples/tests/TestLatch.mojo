
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestLatch(Movable, Copyable):
    var world: World
    var osc: Osc[2]
    var lfo: Osc[2]
    var latch: Latch[2] 
    var dusty: Dust[2]
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[2](self.world)
        self.lfo = Osc[2](self.world)
        self.latch = Latch[2]()
        self.dusty = Dust[2](self.world)
        self.messenger = Messenger(self.world)

    def next(mut self) -> MFloat[2]:
        freq = self.lfo.next(0.1) * 200 + 300
        edge = self.dusty.next_bool(0.5, 1.0)
        freq = self.latch.next(freq,edge)
        sample = self.osc.next(freq)  # Get the next sample from the synth
        return sample * 0.2  # Get the next sample from the synth