
from mmm_audio import *

struct PGVoice(PolyObject):
    var world: World
    var env: ASREnv
    var synth: Osc[]
    var messenger: Messenger
    var curves: MFloat[2]
    var gate: Bool
    var freq: MFloat[]
    var pan: MFloat[]

    def check_active(self) -> Bool:
        return self.env.is_active
    
    def set_gate(mut self, gate: Bool):
        self.gate = gate
        if gate:
            self.freq = exprand(100., 1000.)
            self.pan = rrand(-1., 1.)

    def __init__(out self, world: World):
        self.world = world
        self.env = ASREnv(self.world)
        self.synth = Osc(self.world)
        self.messenger = Messenger(self.world)
        self.curves = MFloat[2](1.0, 1.0)
        self.gate = False
        self.freq = 0.0
        self.pan = 0.0


    def next(mut self) -> MFloat[2]:
        env = self.env.next(0.01, 1, 0.7, self.gate, self.curves)
        sample = self.synth.next(self.freq)
        return env * pan2(sample, self.pan) * 0.1


struct TestPolyGate(Movable, Copyable):
    comptime num_gates: Int = 4
    comptime num_voices: Int = 16

    var psg_voices: List[PGVoice]
    var world: World
    var gates: List[Dust[]]
    var poly: Poly
    var gated_sigs: List[Bool]
    var m: Messenger
    var dust_vals: List[Float64]

    def __init__(out self, world: World):
        self.psg_voices = [PGVoice(world) for _ in range(self.num_voices)]
        self.world = world
        self.gates = [Dust(self.world) for _ in range(self.num_gates)]
        self.poly = Poly(self.world, self.num_voices)
        self.gated_sigs = [False for _ in range(Self.num_gates)]
        self.m = Messenger(world)
        self.dust_vals = [1.0, 2.0]
    
    def next(mut self) -> MFloat[2]:
        self.m.update("dust_vals", self.dust_vals)
        for i in range(Self.num_gates):
            if self.gates[i].next_bool(self.dust_vals[0], self.dust_vals[1]): self.gated_sigs[i] = not self.gated_sigs[i]

        # interpret the gates
        _ = self.poly.next_gate(self.psg_voices, self.gated_sigs)
        # sum the voices
        out = MFloat[2](0.0, 0.0)
        for ref voice in self.psg_voices:
            out += voice.next()
        return out