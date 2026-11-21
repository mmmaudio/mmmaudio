from mmm_audio import *

# A Pulsar played with the mouse.
# Left/right sets the width: at the left edge the waveform is squeezed into a tiny sliver
# of each cycle (a click train), at the right edge it is a plain, unsquashed waveform.
# Up/down sets the pitch from 40 Hz (bottom of the screen) to 1000 Hz (top).
# The "osc_frac" message crossfades sine -> triangle -> saw -> square.

# Setting "which" selects between the basic waveform and the VWT (wavetable) version of the pulsar, which uses a precomputed wavetable of a sinc function.


struct PulsarExample(Movable, Copyable):
    var world: World
    var pulsar: Pulsar[1, Interp.sinc, TimesOversampling.x4]
    var pulsar_vwt: Pulsar[1, Interp.sinc, TimesOversampling.x4]
    var table: SIMDBuffer[1]
    var freq_lag: Lag[1]
    var width_lag: Lag[1]
    var m: Messenger
    var osc_frac: Float64
    var gain: Float64
    var which: Int

    def __init__(out self, world: World):
        self.world = world
        self.pulsar = Pulsar[1, Interp.sinc, TimesOversampling.x4](world)
        self.pulsar_vwt = Pulsar[1, Interp.sinc, TimesOversampling.x4](world)
        self.table = SIMDBuffer(sinc_table(16384, 8), world[].sample_rate)
        self.freq_lag = Lag(world, 0.05)
        self.width_lag = Lag(world, 0.05)
        self.m = Messenger(world)
        self.osc_frac = 0.0
        self.gain = 0.3
        self.which = 0

    @always_inline
    def next(mut self) -> MFloat[2]:
        self.m.update("osc_frac", self.osc_frac)
        self.m.update("gain", self.gain)
        self.m.update("which", self.which)

        var mouse_x = clip(self.world[].mouse_x(), 0.0, 1.0)
        var mouse_y = clip(self.world[].mouse_y(), 0.0, 1.0)

        # mouse y is 0 at the top of the screen, so flip it to put the high pitches at the top
        var freq = self.freq_lag.next(linexp(1.0 - mouse_y, 0.0, 1.0, 40.0, 1000.0))
        var width = self.width_lag.next(linexp(mouse_x, 0.0, 1.0, 0.01, 1.0))

        var sample = self.pulsar.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](
            freq, 0.0, False, self.osc_frac, width
        )
        var sample_vwt = self.pulsar_vwt.next_vwt[mask=16383](self.table, freq, 0.0, False, 0.0, width)

        if self.which == 0:
            return MFloat[2](sample[0], sample[0]) * self.gain
        else:
            return MFloat[2](sample_vwt[0], sample_vwt[0]) * self.gain
