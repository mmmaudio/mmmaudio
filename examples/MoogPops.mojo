from mmm_audio import *

# THE SYNTH

comptime how_many = 16
comptime times_oversampling = TimesOversampling.none

struct MoogPops(Movable, Copyable):
    var world: World  
    var dusts: Dust[how_many]
    var filts: VAMoogLadder[how_many]
    var m: Messenger
    var t_exp_rand: TExpRand[how_many]
    var t_rand: TRand[how_many]
    var t_rand2: TRand[how_many]
    var downsampler: Downsampler[how_many, times_oversampling]


    def __init__(out self, world: World):
        self.world = world
        oversampled_world = create_subworld(world, times_oversampling)
        self.dusts = Dust[how_many](oversampled_world)
        self.filts = VAMoogLadder[how_many](oversampled_world)

        self.m = Messenger(world)
        self.t_exp_rand = TExpRand[how_many]()
        self.t_rand = TRand[how_many]()
        self.t_rand2 = TRand[how_many]()
        self.downsampler = Downsampler[how_many, times_oversampling](world)

    def next(mut self) -> MFloat[2]:
        
        for _ in range(times_oversampling.times):
            dusts = self.dusts.next_bool(0.25, 4.0)
            freqs = self.t_exp_rand.next(8000.0, 18000.0, dusts)
            qs = self.t_rand.next(0.5, 1.04, dusts)
            sig = self.filts.next(dusts.cast[DType.float64]() * self.t_rand2.next(0.2, 1.0, dusts), freqs, qs) 
            self.downsampler.add_sample(sig)

        return splay(self.downsampler.get_sample(), self.world)
