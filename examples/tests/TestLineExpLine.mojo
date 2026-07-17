
from mmm_audio import *

comptime num: Int = 1

struct TestLineExpLine[](Movable, Copyable):
    var world: World
    var osc: Osc[num]
    var osc2: Osc[num]
    var osc3: Osc[num]
    var line_vals: List[Float64]
    var m: Messenger
    var line: Line[num]
    var expline: Line[num]
    var curveline: Line[num]
    var which: Int

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[num](self.world)
        self.osc2 = Osc[num](self.world)
        self.osc3 = Osc[num](self.world)
        self.line_vals = [440.0, 880.0, 1.0]
        self.m = Messenger(self.world)
        self.line = Line[num](self.world)
        self.which = 0
        self.expline = Line[num](self.world)
        self.curveline = Line[num](self.world)

    def next(mut self) -> MFloat[2]:
        trig = self.m.notify_update("line_vals", self.line_vals)
        if trig:
            print("line_vals updated to: ", self.line_vals)
        self.m.update("which", self.which) 
        
        line = self.line.next(self.line_vals[0], self.line_vals[1], self.line_vals[2], trig)
        expline = self.expline.exp(self.line_vals[0], self.line_vals[1], self.line_vals[2], trig)
        curveline = self.curveline.curve(self.line_vals[0], self.line_vals[1], self.line_vals[2], trig, curve=2.0)


        self.world[].print("line: ", line, " expline: ", expline, " curveline: ", curveline, n_blocks = 50)

        line, expline, curveline = self.osc.next(line), self.osc2.next(expline), self.osc3.next(curveline)

        return select(MFloat[1](self.which), MFloat[2](line), MFloat[2](expline), MFloat[2](curveline), splay(line, expline, curveline, world=self.world) ) * 0.1