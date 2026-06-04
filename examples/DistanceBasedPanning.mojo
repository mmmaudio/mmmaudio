from mmm_audio import *

# THE SYNTH


struct DistanceBasedPanning(Movable, Copyable):
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
        self.pos = [0, 0]

    def next(mut self) -> MFloat[8]:
        comptime max_simd = 8

        # self.messenger.update("pos", self.pos)
        self.pos[0] = linlin(self.world[].mouse_x, 0.0, 1.0, -1.0, 1.0)
        self.pos[1] = linlin(self.world[].mouse_y, 0.0, 1.0, 1.0, -1.0)
        
        # 4 speaker setup

        self.pos[1] = linlin(self.world[].mouse_y, 0.0, 1.0, 1.0, -1.0)
        
        # 4 speaker setup

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

        out = dbap2D[4, max_simd, speakers, weights](sig, self.pos, 0.5)
        

        #7 speaker setup

        # comptime speakers : InlineArray[MFloat[2], 7] = [
        #     MFloat[2](-0.66, 1),
        #     MFloat[2](0.66, 1),
        #     MFloat[2](0, 1),
        #     MFloat[2](-1, 0),
        #     MFloat[2](1, 0),
        #     MFloat[2](-0.66, -1),
        #     MFloat[2](0.66, -1)
        # ]
        # comptime weights : InlineArray[Float64, 7] = [
        #     1,1,1,1,1,1,1
        # ]

        # sig = self.dust.next(10, 40) * 0.5
        # sig = self.filt.bpf(sig, 1200, 10.0, 1.0)

        # out = dbap2D[7, max_simd, speakers, weights](sig, self.pos, 0.5)
        

        return out * 0.5
