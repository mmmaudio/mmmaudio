from mmm_audio import *

# THE SYNTH

struct DbapSynth(Movable, Copyable):
    var world: World  
    var dust: Dust[1] 
    var messenger: Messenger
    var pos: MFloat[2]
    var filt: Reson[1]

    def __init__(out self, world: World):
        self.world = world
        self.dust = Dust[1](world)
        self.filt = Reson[1](world)
        self.messenger = Messenger(self.world)
        self.pos = MFloat[2](0.0, 0.0)

    def next(mut self) -> MFloat[4]:
        
        self.pos[0] = linlin(self.world[].mouse_x, 0.0, 1.0, -1.0, 1.0)
        self.pos[1] = linlin(self.world[].mouse_y, 0.0, 1.0, -1.0, 1.0)
        comptime speakers : InlineArray[MFloat[2], 4] = [
            MFloat[2](-1, 1),
            MFloat[2](1, 1),
            MFloat[2](-1, -1),
            MFloat[2](1, -1)
        ]

        comptime weights : InlineArray[Float64, 4] = [
            1,1,1,1
        ]

        sig = self.dust.next(10, 40) * 0.5

        sig = self.filt.bpf(sig, 1200, 10.0, 1.0)
        out = dbap2D[4, 4, speakers, weights](sig, self.pos)
        
        

        return out

# THE GRAPH

struct DistanceBasedPanning(Movable, Copyable):
    var world: World  
    var dust: DbapSynth
    var reson: Reson[2]
    var freq: MFloat[1]
    var lag: Lag[1]

    def __init__(out self, world: World):
        self.world = world
        self.dust = DbapSynth(world)
        self.reson = Reson[2](world)
        self.freq = MFloat[1](200.0)
        self.lag = Lag(world, 0.1)

    def next(mut self) -> MFloat[4]:

        

        out = self.dust.next()

        return out * 0.5