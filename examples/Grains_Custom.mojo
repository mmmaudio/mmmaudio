"""This example demonstrates how to create a custom grain type with a filter inside each grain.

GrainBPF embeds a GrainAll and sends its output through a bandpass filter.

Because the filter introduces an impulse response, the grain will still be active for a short time after the grain envelope has finished, so we need to test the signal for when both channels get to a zero crossing and reset the filter before the next grain starts.
"""

from mmm_audio import *

struct GrainBPF(GrainObject):
    """A custom grain with a BPF inside each grain.
    """
    var world: World 
    var grain: GrainAll # a custom grain needs to include a GrainAll, which holds all the grain parameters and does all the envelope and windowing work
    var start_chan: Int
    var svf: SVF[2]
    var filter_freq: Float64
    var q: Float64
    var last_sample: MFloat[2]

    def __init__(out self, world: World):
        """

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world  
        self.grain = GrainAll(world)
        self.start_chan = 0
        self.svf = SVF[2](world)
        self.filter_freq = 200.
        self.q = 1.0
        self.last_sample = MFloat[2](0.0)

    def check_active(mut self) -> Bool:
        # the grain is active if either the grain envelope is active or if the output of the filter is still above a very small threshold (to account for the filter's impulse response)
        if self.grain.check_active():
            return True
        elif abs(self.last_sample[0]) > 1e-06 or abs(self.last_sample[1]) > 1e-06:
            return True
        else:
            return False

    # the following functions are needed in all GrainObject objects. In general, you can copy and paste these and change the items below listed as being for this example

    def set_trigger(mut self, trigger: Bool):
        self.grain.set_trigger(trigger)
        if trigger:
            self.svf.reset() # this needs to be in this example, but may not need to be your implementation
    
    def set_env_trigger(mut self, trigger: Bool):
        self.grain.set_env_trigger(trigger)

    def get_env_trigger(self) -> Bool:
        return self.grain.get_env_trigger()

    def set_user_defined_env(mut self, env_points: Span[Tuple[Float64, Float64], ...]):
        self.grain.set_user_defined_env(env_points)

    def set_vals(mut self, 
    rate: Float64 = 1.0, 
    start_frame: Int = 0, 
    duration: Float64 = 0.0,
    pan: Float64 = 0.0,
    gain: Float64 = 1.0,
    start_chan: Int = 0,
    filter_freq: Float64 = 200.,
    q: Float64 = 1.0
    ):
        self.grain.set_vals(rate, start_frame, duration, pan, gain) # this is the general grain parameter setting function
        
        # these are custom for this example, but may be different in your implementation
        self.start_chan = start_chan
        self.filter_freq = filter_freq
        self.q = q

    def process_sample(mut self, sample: MFloat[2]) -> MFloat[2]:
            return self.svf.bpf(sample, self.filter_freq, self.q)

    @always_inline
    # this is a stereo grain, but you can make a pan_az grain by making a .next_az function instead
    def next_2[num_buf_chans: Int, num_playback_chans: Int = 1, win_type: WindowType = WindowType.hann, custom_curve: WindowType = WindowType.hann, bWrap: Bool = False](mut self, buffer: SIMDBuffer[num_buf_chans]) -> MFloat[2]:
        
        # get all the channels from the grain
        var sample = self.grain.next_all[win_type=win_type, custom_curve=custom_curve, bWrap=bWrap](buffer)

        comptime if num_playback_chans == 1:
            panned = pan2(sample[self.start_chan], self.grain.pan)
            panned = self.svf.bpf(panned, self.filter_freq, self.q)
            self.last_sample = panned
            return panned
        else:
            panned = pan_stereo(MFloat[2](sample[self.start_chan], sample[(self.start_chan + 1) % buffer.get_num_chans()]), self.grain.pan) 
            panned = self.svf.bpf(panned, self.filter_freq, self.q)
            self.last_sample = panned
            return panned

struct Grains_Custom(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    
    var tgrains: TGrains[GrainBPF, WindowType.user_defined, WindowType.hann]
    var impulse: Phasor[1]  
    var m: Messenger
    var max_trig_rate: Float64
    var points_temp: List[Float64]
     
    def __init__(out self, world: World):
        self.world = world  

        # buffer uses numpy to load a buffer into an N channel array
        self.buffer = SIMDBuffer[2].load("resources/Shiverer.wav")

        self.tgrains = TGrains[GrainBPF, WindowType.user_defined, WindowType.hann](self.world, 8)  
        self.impulse = Phasor[1](self.world)
        self.m = Messenger(world)
        self.max_trig_rate = 20.0
        self.points_temp = List[Float64]()

        arr = [
            (0.0, 0.0), 
            (0.01, 1.0), 
            (0.9, 1.0), 
            (1.0, 0.0)
        ]
        # set the initial envelope points for the grains.
        self.tgrains.set_env_points(arr)

    @always_inline
    def next(mut self) -> MFloat[2]:
        self.m.update("max_trig_rate", self.max_trig_rate)
        new_points = self.m.notify_update("env_points", self.points_temp)
        if new_points:
            self.tgrains.set_env_points(self.points_temp)

        imp_freq = linlin(self.world[].mouse_y, 0.0, 1.0, 1.0, self.max_trig_rate)
        var impulse = self.impulse.next_bool(imp_freq, 0, True)

        start_frame = Int(linlin(self.world[].mouse_x, 0.0, 1.0, 0.0, Float64(self.buffer.num_frames) - 1.0))

        # to make this work we need to: 1) trigger the grain, 2) set the grain parameters (including the custom ones), and 3) call next on tgrains to get the output sample. this way you guarantee that all values are set before the grain starts processing audio
        grain_num = self.tgrains.trig(impulse)
        if grain_num >= 0:
            self.tgrains.grains[grain_num].set_vals(1, start_frame, 0.1, random_float64(-1.0, 1.0), 1.0, 0, exprand(200., 8000.), rrand(5.0, 10.0))
        out = self.tgrains.next_2[2](self.buffer, 1.0)

        return MFloat[2](out[0], out[1])