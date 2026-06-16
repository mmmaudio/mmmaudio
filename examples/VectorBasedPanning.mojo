from mmm_audio import *

# THE SYNTH


struct VectorBasedPanning(Movable, Copyable):
    var world: World  
    var dust: Dust[1] 
    var messenger: Messenger
    var az: Float64
    var filt: Reson[1]
    var wsl: Int
    var pos: List[Float64]
    def __init__(out self, world: World):
        self.world = world
        self.dust = Dust[1](world)
        self.filt = Reson[1](world)
        self.messenger = Messenger(self.world)
        self.az = 0.0
        self.wsl = 0
        self.pos = [0.0, -1.0]

    def next(mut self) -> MFloat[8]:
        
        comptime max_simd = 8
        comptime two_pi = 2 * pi

        self.messenger.update("az", self.az)
        self.messenger.update("pos", self.pos)
        self.messenger.update("wsl", self.wsl)
        
        if self.wsl == 0:
            
            var x = linlin(self.world[].mouse_x, 0.0, 1.0, -1.0, 1.0)
            var y = linlin(self.world[].mouse_y, 0.0, 1.0, 1.0, -1.0)
            self.az = atan2(y, x)
        else:
            self.az = atan2(self.pos[1], self.pos[0])
            
        # 4 speaker setup
        comptime offset = deg_to_rad(90)
        
        comptime speakers : InlineArray[Float64, 4] = [
            deg_to_rad(-55),
            deg_to_rad(55),
            deg_to_rad(-110),
            deg_to_rad(110)
        ]
        
        

        sig = self.dust.next(10, 40) * 0.5
        sig = self.filt.bpf(sig, 1200, 10.0, 1.0)

        out = vbap2D[4, max_simd, speakers](sig, self.az + offset)
        

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



def deg_to_rad(degrees: Float64) -> Float64:
    """
    Converts from degrees to radians.
    """
    return degrees * (pi/180)



def rad_to_deg(radians: Float64) -> Float64:
    """
    Converts from radians to degrees.
    """
    return radians * (180/pi)