from mmm_audio import *

# THE SYNTH

comptime num_output_chans = 2
comptime num_simd_chans = next_power_of_two(num_output_chans)

struct Grains(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    
    var tgrains: TGrains # set the number of simultaneous grains by setting the max_grains parameter here
    var tgrains2: TGrains 
    var impulse: Phasor[1]  
    var start_frame: Float64
    var m: Messenger
    var max_trig_rate: Float64
    var env_params: EnvParams
     
    def __init__(out self, world: World):
        self.world = world  

        # buffer uses numpy to load a buffer into an N channel array
        self.buffer = SIMDBuffer[2].load("resources/Shiverer.wav")

        self.tgrains = TGrains(10, 100, world)  
        self.tgrains2 = TGrains(10, 100, world)
        self.impulse = Phasor[1](self.world)
        self.m = Messenger(world)
        self.max_trig_rate = 20.0
        self.env_params = EnvParams()

        self.start_frame = 0.0 

    @always_inline
    def next(mut self) -> MFloat[num_simd_chans]:
        self.m.update("max_trig_rate", self.max_trig_rate)
        c1 = self.m.notify_update("times", self.env_params.times) 
        c2 = self.m.notify_update("values", self.env_params.values) 
        c3 = self.m.notify_update("curves", self.env_params.curves) 
        if c1 or c2 or c3:
            self.tgrains.set_env_params(self.env_params)

        imp_freq = linlin(self.world[].mouse_y, 0.0, 1.0, 1.0, self.max_trig_rate)  # Map mouse Y to a trigger frequency between 1 Hz and max_trig_rate
        var impulse = self.impulse.next_bool(imp_freq, 0, True)

        start_frame = Int(linlin(self.world[].mouse_x, 0.0, 1.0, 0.0, Float64(self.buffer.num_frames) - 1.0))
        # if there are 2 (or fewer) output channels, pan the stereo buffer out to 2 channels by panning the stereo playback with pan2
        # if there are more than 2 output channels, pan each of the 2 channels separately and randomly pan each grain channel to a different speaker
        comptime if num_output_chans == 2:
            out = self.tgrains.next[2, WindowType.user_defined](self.buffer, 1, impulse, start_frame, 0.4, random_float64(-1.0, 1.0), 1.0)

            return MFloat[num_simd_chans](out[0], out[1])
        else:
            pass
            # for > 2 output channels, uncomment these lines to use the next_pan_az method
            # pan each channel separately to num_output_chans speakers
            # out_az1 = self.tgrains.next_pan_az[num_simd_chans=num_simd_chans](self.buffer, 1, impulse, start_frame, 0.4, random_float64(-1.0, 1.0), 1.0, num_output_chans, 0)
            # out_az2 = self.tgrains2.next_pan_az[num_simd_chans=num_simd_chans](self.buffer, 1, impulse, start_frame, 0.4, random_float64(-1.0, 1.0), 1.0, num_output_chans, 1)
  
            # return out_az1 + out_az2