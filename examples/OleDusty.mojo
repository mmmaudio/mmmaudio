from mmm_audio import *

# THE SYNTH

struct Dusty(Movable, Copyable):
    var world: World  
    var dust: Dust[2] 

    def __init__(out self, world: World):
        self.world = world
        self.dust = Dust[2](world)

    def next(mut self, freq: MFloat[1]) -> MFloat[2]:

        out = self.dust.next(freq*0.125, freq*8) * 0.5

        # uncomment below for use the phase of the Dust oscillator instead of the impulse
        # out = self.dust.get_phase()

        return out

# THE GRAPH

struct OleDusty(Movable, Copyable):
    var world: World  
    var dusty: Dusty
    var reson: Reson[2]
    var freq: MFloat[1]
    var lag: Lag[1]

    def __init__(out self, world: World):
        self.world = world
        self.dusty = Dusty(world)
        self.reson = Reson[2](world)
        self.freq = MFloat[1](200.0)
        self.lag = Lag(world, 0.1)

    def next(mut self) -> MFloat[2]:

        freq = linexp(self.world[].mouse_y(), 0.0, 1.0, 100.0, 2000.0)

        out = self.dusty.next(linlin(self.world[].mouse_x(), 0.0, 1.0, 1.0, 10.0))

        # the reson filter uses SIMD to run 2 filters in parallel, each processing a channel of the dusty synth
        out = self.reson.bpf(out, self.lag.next(freq), 10.0, 1.0)  # apply a bandpass filter to the output of the Dusty synth

        return out * 0.5