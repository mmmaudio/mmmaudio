from mmm_audio import *

struct ChowningFM(Movable, Copyable):
    var world: World # pointer to the MMMWorld
    var m: Messenger
    var c_osc: Osc[1,Interp.linear,TimesOversampling.x2]  # Carrier oscillator
    var m_osc: Osc[1,Interp.linear,TimesOversampling.x2]  # Modulator oscillator
    var index_env: Env
    var amp_env: Env
    var cfreq: Float64
    var mfreq: Float64
    var vol: Float64

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)
        self.c_osc = Osc[1,Interp.linear,TimesOversampling.x2](self.world)
        self.m_osc = Osc[1,Interp.linear,TimesOversampling.x2](self.world)
        self.index_env = Env(self.world)
        self.amp_env = Env(self.world)
        self.cfreq = 200.0
        self.mfreq = 100.0
        self.vol = -12.0

    @always_inline
    def update_envs(mut self):
        
        self.m.update("index_vals", self.index_env.params.values)
        self.m.update("index_times", self.index_env.params.times)
        self.m.update("index_curves", self.index_env.params.curves)
        self.m.update("amp_vals", self.amp_env.params.values)
        self.m.update("amp_times", self.amp_env.params.times)
        self.m.update("amp_curves", self.amp_env.params.curves)

    @always_inline
    def next(mut self) -> MFloat[2]:

        self.m.update("c_freq", self.cfreq)
        self.m.update("m_freq", self.mfreq)
        self.m.update("vol", self.vol) 
        trig = self.m.notify_trig("trigger")
        self.update_envs()

        index = self.index_env.next(trig)
        msig = self.m_osc.next(self.mfreq) * self.mfreq * index
        csig = self.c_osc.next(self.cfreq + msig)
        csig *= self.amp_env.next(trig)
        csig *= dbamp(self.vol)

        return csig