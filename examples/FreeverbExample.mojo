from mmm_audio import *

comptime num_chans = 2

struct FreeverbSynth(Copyable, Movable):
    var world: World 
    var buffer: SIMDBuffer[num_chans]

    var play_buf: Play

    var freeverb: Freeverb[num_chans]
    var m: Messenger

    var room_size: Float64
    var lpf_comb: Float64
    var added_space: Float64
    var mix: Float64

    def __init__(out self, world: World):
        self.world = world 

        # load the audio buffer 
        self.buffer = SIMDBuffer.load("resources/Shiverer.wav")

        # without printing this, the compiler wants to free the buffer for some reason
        print("Loaded buffer with", self.buffer.num_chans, "channels and", self.buffer.num_frames, "frames.")

        self.play_buf = Play(self.world)
        self.freeverb = Freeverb[num_chans](self.world)

        self.room_size = 0.9
        self.lpf_comb = 1000.0
        self.added_space = 0.5
        self.mix = 0.2

        self.m = Messenger(self.world)

    @always_inline
    def next(mut self) -> MFloat[2]:

        self.m.update("room_size", self.room_size)
        self.m.update("lpf_comb", self.lpf_comb)
        self.m.update("added_space", self.added_space)
        self.m.update("mix", self.mix) 

        out = self.play_buf.next[num_chans=num_chans](self.buffer, 1.0, True)
        out = self.freeverb.next(out, self.room_size, self.lpf_comb, self.added_space) * 0.1 * self.mix + out * (1.0 - self.mix)
        return out


struct FreeverbExample(Movable, Copyable):
    var world: World

    var freeverb_synth: FreeverbSynth  # Instance of the FreeverbSynth

    def __init__(out self, world: World):
        self.world = world
        self.freeverb_synth = FreeverbSynth(self.world)

    def next(mut self) -> MFloat[2]:
        #return MFloat[2](0.0)
        return self.freeverb_synth.next()  # Return the combined output sample
