from mmm_audio import *

comptime num_chans = 2

struct BufSynth(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    var num_chans: Int

    var play_buf: Play
    var play_rate: Float64
    
    var moog: VAMoogLadder[num_chans, 1] # 2 channels, os_index == 1 (2x oversampling)
    var lpf_freq: Float64
    var lpf_freq_lag: Lag[]
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world 
        print("world memory location:", world)

        # load the audio buffer 
        self.buffer = SIMDBuffer[2].load("resources/Shiverer.wav")
        self.num_chans = self.buffer.num_chans  

        # without printing this, the compiler wants to free the buffer for some reason
        print("Loaded buffer with", self.buffer.num_chans, "channels and", self.buffer.num_frames, "frames.")

        self.play_rate = 1.0

        self.play_buf = Play(self.world)

        self.moog = VAMoogLadder[num_chans, 1](self.world)
        self.lpf_freq = 20000.0
        self.lpf_freq_lag = Lag(self.world, 0.1)

        self.messenger = Messenger(self.world)

    def next(mut self) -> MFloat[num_chans]:
        self.messenger.update("lpf_freq", self.lpf_freq)
        self.messenger.update("play_rate", self.play_rate)

        out = self.play_buf.next[num_chans=num_chans](self.buffer, self.play_rate, True)

        freq = self.lpf_freq_lag.next(self.lpf_freq)
        out = self.moog.next(out, freq, 1.0)
        return out

struct PlayExample(Movable, Copyable):
    var world: World

    var buf_synth: BufSynth  # Instance of the BufSynth

    def __init__(out self, world: World):
        self.world = world

        self.buf_synth = BufSynth(self.world)  

    def next(mut self) -> MFloat[num_chans]:
        return self.buf_synth.next()  # Return the combined output sample