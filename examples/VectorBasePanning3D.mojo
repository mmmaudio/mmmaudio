from mmm_audio import *
from std.time import perf_counter
# THE SYNTH


struct VectorBasePanning3D(Movable, Copyable):
    var world: World  
    var dust: Dust[1] 
    var messenger: Messenger
    var az: Float64
    var ht: Float64
    var filt: Reson[1]
    var wsl: Int
    var pos: List[Float64]
    var mouse: Bool
    var vbap: VBAP3D[5, 8]
    def __init__(out self, world: World):
        self.world = world
        self.dust = Dust[1](world)
        self.filt = Reson[1](world)
        self.messenger = Messenger(self.world)
        self.az = 0.0
        self.ht = 0.01
        self.wsl = 0
        self.pos = [0.0, -1.0]
        self.mouse = False
        comptime degrees_to_radians = pi/180
        # var speaker_array : Array[MFloat[2], 11] = [
        #     MFloat[2](0.0, 0),#Center
        #     MFloat[2](25 * degrees_to_radians, 0),# L
        #     MFloat[2](-25 * degrees_to_radians, 0),# R
        #     MFloat[2](90 * degrees_to_radians, 0), # LS
        #     MFloat[2](-90 * degrees_to_radians, 0), # RS
        #     MFloat[2](135  * degrees_to_radians, 0), # LB
        #     MFloat[2](-135 * degrees_to_radians, 0), # RB
        #     MFloat[2](40 * degrees_to_radians, 35 * degrees_to_radians), #LTF
        #     MFloat[2](-40 * degrees_to_radians, 35 * degrees_to_radians), #RTF
        #     MFloat[2](120 * degrees_to_radians, 35 * degrees_to_radians), #LTR
        #     MFloat[2](-120 * degrees_to_radians, 35 * degrees_to_radians) #RTF
        #     ]
        var speaker_array : Array[MFloat[2], 5] = [
            MFloat[2](-0.5 * pi, 0),
            MFloat[2](0.0, 0.0),
            MFloat[2](0.5 * pi, 0.0),
            MFloat[2](0.0, -0.5 * pi),
            MFloat[2](0.0, 0.5 * pi)
        ]
        self.vbap = VBAP3D[5, 8](speaker_array)

        
    def next(mut self) -> MFloat[8]:
        
        comptime two_pi = 2 * pi

        self.messenger.update("az", self.az)
        self.messenger.update("ht", self.ht)
        self.messenger.update("pos", self.pos)
        self.messenger.update("mouse", self.mouse)
       
        
     
        # comptime offset = deg_to_rad(90)
        if self.mouse:
            var x = linlin(self.world[].mouse_x(), 0.0, 1.0, -1.0 * pi, 1.0 * pi)
            var y = linlin(self.world[].mouse_y(), 0.0, 1.0, -1.0 * pi, 1.0 * pi)
            self.az = x
            self.ht = y
        
        var sig = self.dust.next(10, 40) * 0.5
        sig = self.filt.bpf(sig, 1200, 10.0, 1.0)

        
        
        

        var out = self.vbap.next(sig, self.az, self.ht)
        
        
        
        return out * 0.5


