
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestOscOversampling(Movable, Copyable):
    var world: World
    var osc: Osc[]
    var osc1: Osc[1,Interp.linear,1]
    var osc2: Osc[1,Interp.linear,2]
    var osc3: Osc[1,Interp.linear,3]
    var osc4: Osc[1,Interp.linear,4]
    var which: Float64
    var messenger: Messenger
    var lag: Lag[]

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc(world)
        self.osc1 = Osc[1,Interp.linear,1](world)
        self.osc2 = Osc[1,Interp.linear,2](world)
        self.osc3 = Osc[1,Interp.linear,3](world)
        self.osc4 = Osc[1,Interp.linear,4](world)
        self.which = 0.0
        self.messenger = Messenger(world)
        self.lag = Lag(world, 0.1)

    def next(mut self) -> Float64:
        self.messenger.update("which", self.which) 
        freq = self.lag.next(linexp(self.world[].mouse_x, 0.0, 1.0, 20.0, 20000.0))

        sample = select(self.which, 
            self.osc.next(freq, osc_type=OscType.saw)[0],
            self.osc1.next(freq, osc_type=OscType.saw)[0],
            self.osc2.next(freq, osc_type=OscType.saw)[0],
            self.osc3.next(freq, osc_type=OscType.saw)[0],
            self.osc4.next(freq, osc_type=OscType.saw)[0],
        )

        return sample * 0.2
