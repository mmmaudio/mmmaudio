from mmm_audio import *

comptime ov_samp = TimesOversampling.x2

# Ring modulates inputs 0 and 1 into the left output, and inputs 2 and 3 into the
# right output, at 2x the sample rate so the sum and difference frequencies above
# Nyquist are filtered out instead of aliasing.
struct QuadRingMod(Movable, Copyable):
    var world: World
    # the carriers (inputs 0 and 2) and modulators (inputs 1 and 3), upsampled together
    var upsampler: Upsampler[4, ov_samp]
    # Downsamplers are made with the main world, not an oversampled one
    var downsampler: Downsampler[2, ov_samp]

    def __init__(out self, world: World):
        self.world = world
        self.upsampler = Upsampler[4, ov_samp](world)
        self.downsampler = Downsampler[2, ov_samp](world)

    # get an input from the audio device, or 0.0 if the channel doesn't exist
    @always_inline
    def input(self, chan: Int) -> Float64:
        # silence for an input the audio device doesn't have
        if chan < self.world[].num_in_chans():
            return self.world[].sound_in(chan)
        return 0.0

    @always_inline
    def next(mut self) -> MFloat[2]:
        # [left carrier, right carrier, left modulator, right modulator]
        var ins = MFloat[4](self.input(0), self.input(2), self.input(1), self.input(3))

        for i in range(ov_samp.times):
            var up = self.upsampler.next(ins, i)
            var ring_mod = MFloat[2](up[0], up[1]) * MFloat[2](up[2], up[3])
            self.downsampler.add_sample(ring_mod)

        return self.downsampler.get_sample()

