from mmm_audio import *

comptime num_chans = 2

struct TestAmpComp(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    var amp: Amplitude[2]
    var compress: Compressor[2]
    var m: Messenger

    var thresh: MFloat[1]
    var ratio: MFloat[1]
    var attack: MFloat[1]
    var release: MFloat[1]
    var knee_width: MFloat[1]

    var play_buf: Play
    def __init__(out self, world: World):
        self.world = world 
        self.buffer = SIMDBuffer[2].load("resources/Shiverer.wav")

        self.play_buf = Play(self.world)
        self.amp = Amplitude[2](world, 0.01, 0.1)
        self.compress = Compressor[2](world)
        self.m = Messenger(world)

        self.thresh = -20.0
        self.ratio = 4.0
        self.attack = 0.01
        self.release = 0.1
        self.knee_width = 0.0

    def next(mut self) -> MFloat[num_chans+2]:

        self.m.update("thresh", self.thresh) 
        self.m.update("ratio", self.ratio) 
        self.m.update("attack", self.attack) 
        self.m.update("release", self.release) 
        self.m.update("knee_width", self.knee_width)

        sig = self.play_buf.next[num_chans=num_chans](self.buffer, 1.0, True)
        amp = self.amp.next(sig)
        out = self.compress.next(sig, self.thresh, self.ratio, self.attack, self.release, self.knee_width)

        return MFloat[num_chans+2](out[0], out[1], self.compress.sidechain, amp[0])