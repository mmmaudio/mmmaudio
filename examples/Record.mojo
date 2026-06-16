from mmm_audio import *

struct Record(Movable, Copyable):
    var world: World
    var buf_dur: Float64
    var buffer: Recorder[]
    var is_recording: Bool
    var is_playing: Float64
    var lag: LagUD[]
    var trig: Bool
    var play_buf: Play
    var input_chan: Int
    var messenger: Messenger
    var note_time: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buf_dur = 10.0  # seconds
        self.buffer = Recorder(self.world, Int(self.world[].sample_rate*self.buf_dur), self.world[].sample_rate)
        self.is_recording = False
        self.is_playing = 0.0
        self.lag = LagUD(self.world, 0.001, 0.05)
        self.trig = False
        self.play_buf = Play(self.world)
        self.input_chan = 0
        self.messenger = Messenger(self.world)
        self.note_time = 0.0

    def start_recording(mut self):
        self.buffer.write_head = 0
        self.is_recording = True
        self.is_playing = 0.0
        self.trig = False
        print("Recording started")
    
    def stop_recording(mut self):
        self.is_recording = False
        self.is_playing = 1.0
        self.trig = True
        self.note_time = Float64(self.buffer.write_head-1) / self.world[].sample_rate
        print("Recorded duration:", self.note_time, "seconds")
        print("Recording stopped. Now playing.")

    def next(mut self) -> MFloat[1]:
        if self.messenger.notify_update("set_input_chan", self.input_chan):
            if self.input_chan < 0 and self.input_chan >= self.world[].num_in_chans():
                print("Input channel out of range, resetting to 0")
                self.input_chan = 0

        notified = self.messenger.notify_update("is_recording", self.is_recording)
        if notified and self.is_recording:
            self.start_recording()
        elif notified and not self.is_recording:
            self.stop_recording()

        # this code does the actual recording, placing the next sample into the buffer
        # my audio interface has audio in on channel 9, so I use self.world[].sound_in(8)
        if self.is_recording:
            # the sound_in List in the world holds the audio in data for the current sample, so grab it from there.
            self.buffer.write_next[False](self.world[].sound_in(self.input_chan)) #write the current sample to the buffer, without looping 
            if self.buffer.write_head >= Int(self.buffer.buf.num_frames-1):
                self.stop_recording()
                print("Recording stopped: buffer full")
                

        out = self.play_buf.next(self.buffer.buf, 1.0, True, self.trig, start_frame = 0, num_frames = self.buffer.write_head-1)

        env = min_env[WindowType.hann](self.world, self.play_buf.get_relative_phase(), 0.01)

        out = out * self.lag.next(self.is_playing) * env

        return out
