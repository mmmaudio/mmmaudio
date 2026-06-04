from mmm_audio import *

comptime num_chans = 2

struct PlayRecExample(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    var num_chans: Int

    var play_buf: Play
    var play_rate: Float64
    var filepath: String
    var recorder: Recorder[2]
    var record_bool: Bool
    
    var moog: VAMoogLadder[num_chans, TimesOversampling.x2] # 2 channels, ov_samp == 1 (2x oversampling)
    var lpf_freq: Float64
    var lpf_freq_lag: Lag[]
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world 
        print("world memory location:", world)

        # load the audio buffer 
        self.filepath = "resources/Shiverer.wav"
        self.buffer = SIMDBuffer[2].load(self.filepath)
        self.num_chans = self.buffer.num_chans  

        self.recorder = Recorder[2](self.world, Int(10*world[].sample_rate), world[].sample_rate)  # Initialize the recorder for 2 channels

        # without printing this, the compiler wants to free the buffer for some reason
        print("Loaded buffer with", self.buffer.num_chans, "channels and", self.buffer.num_frames, "frames.")

        self.play_rate = 1.0
        self.record_bool = False

        self.play_buf = Play(self.world)

        self.moog = VAMoogLadder[num_chans, TimesOversampling.x2](self.world)
        self.lpf_freq = 20000.0
        self.lpf_freq_lag = Lag(self.world, 0.1)

        self.messenger = Messenger(self.world)

    def next(mut self) -> MFloat[num_chans]:
        self.messenger.update("lpf_freq", self.lpf_freq)
        self.messenger.update("play_rate", self.play_rate)
        load_buffer = self.messenger.notify_update("load_buffer", self.filepath)
        if load_buffer:
            print("Loading new buffer from:", self.filepath)
            temp_buffer = SIMDBuffer.load(self.filepath)
            if temp_buffer.num_frames > 0 and temp_buffer.num_chans > 0:
                self.buffer = temp_buffer^
                self.play_buf.reset_phase()
        start_rec = self.messenger.notify_trig("start_recording")
        if start_rec:
            print("Starting recording to internal buffer.")
            self.recorder.write_head = 0
            self.record_bool = True
        stop_rec = self.messenger.notify_trig("stop_recording")
        if stop_rec:
            print("Stopping recording.")
            self.record_bool = False
        

        save_buffer = self.messenger.notify_update("save_buffer", self.filepath)
        if save_buffer:
            print("Saving current buffer to:", self.filepath)
            self.recorder.buf.write_to_file(self.filepath, self.recorder.write_head)
            print("Saved", self.recorder.write_head, "samples to file.")
        
        out = self.play_buf.next[num_chans=num_chans](self.buffer, self.play_rate, True)
        if self.record_bool:
            self.recorder.write_next[loop=False](out)

        freq = self.lpf_freq_lag.next(self.lpf_freq)
        out = self.moog.next(out, freq, 1.0)
        return out

