from mmm_audio import *

# THE SYNTH

struct StereoBeatingSines2(Movable, Copyable):
    var world: World # pointer to the MMMWorld
    var osc_s: Osc[4, interp=Interp.linear] # the four oscillators, in one SIMD struct
    var osc_freqs: MFloat[4] # frequencies for the four oscillators, two we hear and two LFOs

    def __init__(out self, world: World, center_freq: Float64):
        self.world = world

        self.osc_s = Osc[4,interp=Interp.linear](self.world)
        self.osc_freqs = MFloat[4](
            center_freq + rrand(1.0, 5.0),
            center_freq - rrand(1.0, 5.0),
            rrand(0.03, 0.1),
            rrand(0.05, 0.2)
        )

    @always_inline
    def next(mut self) -> MFloat[2]:
        # calling .next on both oscillators gets both of their next samples
        var temp = self.osc_s.next(self.osc_freqs)

        # modulate the volume with a slow LFO
        
        var temp1 = (temp[0] + temp[1]) * (temp[2] * 0.5 + 0.5)

        return pan2(temp1, temp[3])  # Pan the temp signal

struct ManyOscillators(Copyable, Movable):
    var world: World
    var synths: List[StereoBeatingSines2]  # Instances of the StereoBeatingSines synth
    var messenger: Messenger
    var num_pairs: Int

    def __init__(out self, world: World):
        self.world = world

        # initialize the list of synths
        self.synths = List[StereoBeatingSines2]()

        self.messenger = Messenger(self.world)
        self.num_pairs = 10

        # add 10 pairs to the list
        for _ in range(self.num_pairs):
            self.synths.append(StereoBeatingSines2(self.world, exprand(100.0, 1000.0)))

    @always_inline
    def next(mut self) -> MFloat[2]:

        if self.messenger.notify_update("num_pairs", self.num_pairs):
            if len(self.synths) != Int(self.num_pairs):
                if self.num_pairs > len(self.synths):
                    # add more
                    for _ in range(self.num_pairs - len(self.synths)):
                        self.synths.append(StereoBeatingSines2(self.world, exprand(100.0, 1000.0)))
                else:
                    # remove some
                    for _ in range(len(self.synths) - self.num_pairs):
                        _ = self.synths.pop()

        # sum all the stereo outs from the N synths
        var sum = MFloat[2](0.0, 0.0)
        for i in range(len(self.synths)):
            sum += self.synths[i].next()

        return sum * (0.5 / Float64(self.num_pairs))  # scale the output down