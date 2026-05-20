from mmm_audio import *

struct MPlotExampleGrain[num_chans: Int = 1](Movable, Copyable):
    var world: World
    var start_frame: Int
    var num_frames: Int
    var player: Play
    var env: Env
    var envTrigger: Bool
    
    def __init__(out self, world: World):
        self.world = world
        self.start_frame = 0
        self.num_frames = 0
        self.env = Env(self.world)
        self.env.params.values = [0.0, 1.0, 1.0, 0.0]
        self.env.params.times = [0.03, 1.0, 0.03]
        self.env.params.curves = [0.0, 0.0, 0.0]
        self.envTrigger = False

        self.player = Play(self.world)
 
    def start(mut self, buf: SIMDBuffer[Self.num_chans], start_frame: Int, num_frames: Int):
        self.start_frame = start_frame
        self.num_frames = num_frames
        duration = Float64(num_frames) / buf.sample_rate
        self.env.params.times[1] = duration - 0.06
        self.envTrigger = True

    def next(mut self, buf: SIMDBuffer[Self.num_chans]) -> MFloat[Self.num_chans]:

        env = self.env.next(self.envTrigger)

        if not self.env.is_active:
            return 0.0

        out = self.player.next[num_chans=Self.num_chans,interp=Interp.none](
            buf=buf, 
            rate=1.0, 
            loop=False, 
            trig=self.envTrigger, 
            start_frame=self.start_frame, 
            num_frames=self.num_frames
            )

        # self.world[].print("grain player out=", out,"env=", env, "start=", self.start_frame, "num=", self.num_frames)

        out *= env
        self.envTrigger = False
        return out
    
    def is_available(self) -> Bool:
        return not self.env.is_active

struct MPlotExample(Movable, Copyable):
    var world: World
    var buf: SIMDBuffer[1]
    var grains: List[MPlotExampleGrain[1]]
    var m: Messenger
    var play_data: List[Int]
    var path: String

    def __init__(out self, world: World):
        self.world = world
        self.grains = List[MPlotExampleGrain[1]](length=30, fill=MPlotExampleGrain[1](world))
        self.m = Messenger(self.world)
        self.play_data = List[Int](length=2, fill=0)
        self.path = String("/Users/ted/Desktop/all_flucoma.wav")
        self.buf = SIMDBuffer[1].load(self.path)

    def next(mut self) -> MFloat[2]:

        if self.m.notify_update("load_sound", self.path):
            self.buf = self.buf.load(self.path)

        trig = self.m.notify_update("play_data", self.play_data)

        if trig:
            print("Playing slice: start=",self.play_data[0], ", num=", self.play_data[1])
            for i in range(len(self.grains)):
                if self.grains[i].is_available():
                    print("Starting grain ", i)
                    self.grains[i].start(self.buf, self.play_data[0], self.play_data[1])
                    break
            
        out = MFloat[2](0.0)
        for ref g in self.grains:
            out += g.next(self.buf)

        return out
