from mmm_audio import *

# THE SYNTH


struct VectorBasePanning(Movable, Copyable):
    var world: World  
    var dust: Dust[1] 
    var messenger: Messenger
    var az: Float64
    var filt: Reson[1]
    var wsl: Int
    var pos: List[Float64]
    var mouse: Bool
    var vbap_4: VBAP2D[4, 4]
    var vbap_7: VBAP2D[7, 8]
    def __init__(out self, world: World):
        self.world = world
        self.dust = Dust[1](world)
        self.filt = Reson[1](world)
        self.messenger = Messenger(self.world)
        self.az = 0.0
        self.wsl = 0
        self.pos = [0.0, -1.0]
        self.mouse = False
        self.vbap_4 = VBAP2D[4, 4]([
            deg_to_rad(-55),
            deg_to_rad(55),
            deg_to_rad(-110),
            deg_to_rad(110)
            ])

        #A Left-Front, Left-Right, Center, Left, Right, Rear-Left, Rear-Right array where Center is channel 3
        self.vbap_7 = VBAP2D[7, 8]([
            deg_to_rad(-30),
            deg_to_rad(30),
            0,
            deg_to_rad(-90),
            deg_to_rad(90),
            deg_to_rad(-150),
            deg_to_rad(150)
        ])

    def next(mut self) -> MFloat[8]:
        
        self.messenger.update("az", self.az)
        self.messenger.update("pos", self.pos)
        self.messenger.update("mouse", self.mouse)
       
        comptime offset = deg_to_rad(90)
        if self.mouse:
            var x = linlin(self.world[].mouse_x(), 0.0, 1.0, -1.0, 1.0)
            var y = linlin(self.world[].mouse_y(), 0.0, 1.0, 1.0, -1.0)
            self.az = atan2(y, x) + offset
        
        var sig = self.dust.next(10, 40) * 0.5
        sig = self.filt.bpf(sig, 1200, 10.0, 1.0)

        # 4 speaker setup
        var pan = self.vbap_4.next(sig, self.az)
        var out = MFloat[8](pan[0], pan[1], pan[2], pan[3], 0.0, 0.0, 0.0, 0.0)
        
        # 7 speaker setup, note that the simd_out_size must be a power of two and larger than the speaker array size.
        # var out = self.vbap_7.next[8](sig, self.az)

        # output for a 7.1 surround sound setup
        return MFloat[8](out[0], out[1], out[2], 0.0,out[3], out[4], out[5], out[6]) * 0.5
        # send all the outs directly
        # return out * 0.5
