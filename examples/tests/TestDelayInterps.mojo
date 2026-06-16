
from mmm_audio import *

struct TestDelayInterps(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var delay_none: Delay[interp=Interp.none]
    var delay_linear: Delay[interp=Interp.linear]
    var delay_quadratic: Delay[interp=Interp.quad]
    var delay_cubic: Delay[interp=Interp.cubic]
    var delay_lagrange: Delay[interp=Interp.lagrange4]
    var lag: Lag[]
    var lfo: Osc[]
    var m: Messenger
    var mouse_lag: Lag[]
    var max_delay_time: Float64
    var lfo_freq: Float64
    var mix: Float64
    var which_delay: Float64
    var mouse_onoff: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.delay_none = Delay[interp=Interp.none](self.world,1.0)
        self.delay_linear = Delay[interp=Interp.linear](self.world,1.0)
        self.delay_quadratic = Delay[interp=Interp.quad](self.world,1.0)
        self.delay_cubic = Delay[interp=Interp.cubic](self.world,1.0)
        self.delay_lagrange = Delay[interp=Interp.lagrange4](self.world,1.0)
        self.lag = Lag(self.world, 0.2)
        self.lfo = Osc[interp=Interp.linear](self.world)
        self.m = Messenger(world)
        self.mouse_lag = Lag(self.world, 0.05)
        self.max_delay_time = 0.5
        self.lfo_freq = 0.5
        self.mix = 0.5
        self.which_delay = 0
        self.mouse_onoff = 0

    def next(mut self) -> MFloat[2]:

        self.m.update("lfo_freq", self.lfo_freq)
        self.m.update("mix", self.mix) 
        self.m.update("mouse_onoff", self.mouse_onoff)
        self.m.update("which_delay", self.which_delay)
        self.m.update("max_delay_time", self.max_delay_time)  
        self.max_delay_time = self.lag.next(self.max_delay_time) 
        delay_time = linlin(self.lfo.next(self.lfo_freq),-1,1,0.001,self.max_delay_time)

        delay_time = select(self.mouse_onoff,delay_time, self.mouse_lag.next(linlin(self.world[].mouse_x(), 0.0, 1.0, 0.0, 0.001)))

        input = self.playBuf.next(self.buffer, 1.0, True)  # Read samples from the buffer

        none = self.delay_none.next(input, delay_time)
        linear = self.delay_linear.next(input, delay_time)
        quadratic = self.delay_quadratic.next(input, delay_time)
        cubic = self.delay_cubic.next(input, delay_time)
        lagrange4 = self.delay_lagrange.next(input, delay_time)

        one_delay = select(self.which_delay,none,linear,quadratic,cubic,lagrange4)
        sig = input * (1.0 - self.mix) + one_delay * self.mix  # Mix the dry and wet signals based on the mix level

        return MFloat[2](sig, sig)