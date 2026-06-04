from mmm_audio import *

# THE SYNTH

comptime how_many = 16

struct MoogPops(Movable, Copyable):
    var world: World  
    var dusts: Dust[how_many]
    var filts: VAMoogLadder[how_many, TimesOversampling.x16] # 4-pole Moog ladder filter, 16x oversampling
    var m: Messenger
    var t_exp_rand: TExpRand[how_many]
    var t_rand: TRand[how_many]
    var t_rand2: TRand[how_many]


    def __init__(out self, world: World):
        self.world = world
        self.dusts = Dust[how_many](world)
        self.filts = VAMoogLadder[how_many, TimesOversampling.x16](world)
        self.m = Messenger(world)
        self.t_exp_rand = TExpRand[how_many]()
        self.t_rand = TRand[how_many]()
        self.t_rand2 = TRand[how_many]()

    def next(mut self) -> MFloat[2]:
        
        dusts = self.dusts.next_bool(0.25, 4.0)
        freqs = self.t_exp_rand.next(8000.0, 18000.0, dusts)
        qs = self.t_rand.next(0.5, 1.04, dusts)
        sig = self.filts.next(dusts.cast[DType.float64]() * self.t_rand2.next(0.2, 1.0, dusts), freqs, qs) 

        return splay(sig, self.world)
