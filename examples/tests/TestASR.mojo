
from mmm_audio import *

struct TestASR(Movable, Copyable):
    var world: World
    var env: ASREnv
    var synth: Osc[]
    var messenger: Messenger
    var curves: MFloat[2]
    var gate: Bool
    var notes: List[List[Int]]

    def __init__(out self, world: World):
        self.world = world
        self.env = ASREnv(self.world)
        self.synth = Osc(self.world)
        self.messenger = Messenger(self.world)
        self.curves = MFloat[2](1.0, 1.0)
        self.gate = False
        self.notes = List[List[Int]]()

    def next(mut self) -> MFloat[2]:
        self.messenger.update("curves", self.curves) 
        # any MIDI note on opens the gate and any note off closes it.
        # note_on and note_off are [note, velocity, channel] lists, sent by MMMAudio.send_midi or by a plugin's MIDI input.
        if self.messenger.notify_update_all("note_on", self.notes):
            self.gate = True
        if self.messenger.notify_update_all("note_off", self.notes):
            self.gate = False

        var env = self.env.next(self.world[].mouse_x(), 1, self.world[].mouse_y(), self.gate, self.curves)
        var sample = self.synth.next(200)
        return env * sample * 0.1



        