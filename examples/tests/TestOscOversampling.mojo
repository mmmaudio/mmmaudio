
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestOscOversampling(Movable, Copyable):
    var world: World
    var osc: Osc[]
    var osc1: Osc[1,Interp.linear,TimesOversampling.x2]
    var osc2: Osc[1,Interp.linear,TimesOversampling.x4]
    var osc3: Osc[1,Interp.linear,TimesOversampling.x8]
    var osc4: Osc[1,Interp.linear,TimesOversampling.x16]
    var which: Float64
    var messenger: Messenger
    var lag: Lag[]

    var downsampler: Downsampler[1,TimesOversampling.x16]
    var osc5: Osc[1,Interp.linear]

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc(world)
        self.osc1 = Osc[1,Interp.linear,TimesOversampling.x2](world)
        self.osc2 = Osc[1,Interp.linear,TimesOversampling.x4](world)
        self.osc3 = Osc[1,Interp.linear,TimesOversampling.x8](world)
        self.osc4 = Osc[1,Interp.linear,TimesOversampling.x16](world)
        self.which = 0.0
        self.messenger = Messenger(world)
        self.lag = Lag(world, 0.1)

        self.downsampler = Downsampler[1,TimesOversampling.x16](world)
        oversampled_world = create_subworld(world, TimesOversampling.x16)
        self.osc5 = Osc[1,Interp.linear](oversampled_world)

    def next(mut self) -> Float64:
        self.messenger.update("which", self.which) 
        freq = self.lag.next(linexp(self.world[].mouse_x(), 0.0, 1.0, 20.0, 20000.0))

        for _ in range(TimesOversampling.x16.times):
            self.downsampler.add_sample(self.osc5.next[OscType.saw](freq))
            
        sample = select(self.which, 
            self.osc.next[OscType.saw](freq)[0],
            self.osc1.next[OscType.saw](freq)[0],
            self.osc2.next[OscType.saw](freq)[0],
            self.osc3.next[OscType.saw](freq)[0],
            self.osc4.next[OscType.saw](freq)[0],
            self.downsampler.get_sample()
        )

        return sample * 0.2
