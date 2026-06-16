from mmm_audio import *

# THE SYNTH

comptime num_speakers = 2
comptime num_simd_chans = 2

struct Grains(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    
    var tgrains: TGrains[win_type = WindowType.hann] # try changing to WindowType.user_defined 
    var impulse: Phasor[1]  
    var start_frame: Float64
    var m: Messenger
    var max_trig_rate: Float64
    var points_temp: List[Float64]
     
    def __init__(out self, world: World):
        self.world = world  

        # buffer uses numpy to load a buffer into an N channel array
        self.buffer = SIMDBuffer[2].load("resources/Shiverer.wav")

        self.tgrains = TGrains[win_type = WindowType.hann](self.world, 10)  # Set the number of simultaneous grains
        self.impulse = Phasor[1](self.world)
        self.m = Messenger(world)
        self.max_trig_rate = 20.0
        self.points_temp = List[Float64]()

        self.start_frame = 0.0 

    @always_inline
    def next(mut self) -> MFloat[num_simd_chans]:
        self.m.update("max_trig_rate", self.max_trig_rate)
        new_points = self.m.notify_update("env_points", self.points_temp)
        if new_points:
            self.tgrains.set_env_points(self.points_temp)

        num_grains = 0
        if self.m.notify_update("set_num_grains", num_grains):
            self.tgrains.set_num_grains(num_grains)

        imp_freq = linlin(self.world[].mouse_y(), 0.0, 1.0, 1.0, self.max_trig_rate)
        var impulse = self.impulse.next_bool(imp_freq, 0, True)

        start_frame = Int(linlin(self.world[].mouse_x(), 0.0, 1.0, 0.0, Float64(self.buffer.num_frames) - 1.0))

        comptime if num_speakers == 2:
            grain_num = self.tgrains.trig(impulse)
            if grain_num >= 0:
                self.tgrains.grains[grain_num].set_vals(1, start_frame, 0.4, random_float64(-1.0, 1.0), 1.0, 0)
            out = self.tgrains.next_2[2](self.buffer)

            return MFloat[num_simd_chans](out[0], out[1])
        else:
            grain_num = self.tgrains.trig(impulse)
            if grain_num >= 0:
                self.tgrains.grains[grain_num].set_vals(1, start_frame, 0.4, random_float64(-1.0, 1.0), 1.0, 0)
            out2 = self.tgrains.next_multi_channel[num_speakers=num_speakers, num_simd_chans=num_simd_chans](self.buffer, 0, 1.0)

            return out2