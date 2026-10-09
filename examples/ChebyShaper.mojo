from mmm_audio import *


struct ChebyShaper(Movable, Copyable):
    """An oscillator pushed through four Chebyshev waveshaping curves.

    The mouse's horizontal position crossfades between the four transfer
    functions held in `waveshaper_functions`, which run from one harmonic on the left to
    five odd harmonics on the right, so sweeping right adds harmonics.
    """

    comptime table_size = 16384
    """Frames per transfer function."""

    comptime num_tables = 4
    """How many curves the mouse crossfades between."""

    var world: World
    var m: Messenger

    var osc: Osc[1]
    var waveshaper_functions: Buffer
    var shaper: WaveShaper[1, Interp.cubic, TimesOversampling.x2]
    var freq_lag: Lag[1]
    var dist_lag: Lag[1]

    var freq: Float64
    var dist_frac: Float64
    var mouse: Bool

    def __init__(out self, world: World):
        """Build the oscillator, the four tables, and the shaper.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.world = world
        self.m = Messenger(self.world)

        self.osc = Osc[1](self.world)
        self.shaper = WaveShaper[1, Interp.cubic, TimesOversampling.x2](self.world)

        # Table 0 gets harmonic 1, table 1 gets 1 and 3, table 2 gets 1, 3 and 5, and so on to 1-5.
        # cheby_fill takes one amplitude list per channel, so all four curves
        # are built in a single call.
        var amplitudes = List[List[Float64]]()
        for table in range(Self.num_tables):
            var amps = List[Float64]()
            for i in range(table * 2 + 1):
                if i % 2 == 1:
                    amps.append(0.0)
                else:
                    amps.append(1.0 / Float64(i + 1))
            amplitudes.append(amps^)

        self.waveshaper_functions = cheby_fill(amplitudes, Self.table_size)

        self.freq_lag = Lag[1](self.world, 0.05)
        self.dist_lag = Lag[1](self.world, 0.05)

        self.freq = 220.0
        self.dist_frac = 0.0
        self.mouse = True

    def next(mut self) -> MFloat[2]:
        """Shape one sample and send it to both channels.

        Returns:
            The shaped output, the same in both channels.
        """
        self.m.update("freq", self.freq)
        self.m.update("dist_frac", self.dist_frac)
        self.m.update("mouse", self.mouse)

        # Left edge of the screen is the first table, right edge the last.
        var position = self.world[].mouse_x() if self.mouse else self.dist_frac
        var dist_frac = self.dist_lag.next(MFloat[1](position))

        var sig = self.osc.sine(self.freq_lag.next(MFloat[1](self.freq)))

        var shaped = self.shaper.next(sig, self.waveshaper_functions, dist_frac)

        return shaped * dbamp(-6.0)
