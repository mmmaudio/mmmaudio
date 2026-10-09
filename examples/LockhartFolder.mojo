from mmm_audio import *

struct LockhartFolder(Movable, Copyable):
    """A sine wave folded through the 4 Lockhart wavefolder transfer curves in series.

    The curve is the virtual analog model from Esqueda, Pontynen, Valimaki and
    Bilbao 2017, made with 4 cascaded waveshapers.

    How hard the sine is driven is what decides how much folding you get. A
    quiet sine only reaches the straight part of the curve near the origin and
    comes out clean; a loud one is carried past the fold and comes back down
    the other side, which is where the harmonics appear. 
    """

    comptime table_size = 8192
    """Frames in the transfer function."""

    var world: World
    var m: Messenger

    var osc: Osc[1]
    var table: Buffer
    var shaper: WaveShaper[1, Interp.cubic, TimesOversampling.x4]
    var freq_lag: Lag[1]
    var drive: Lag[1]

    var freq: Float64

    def __init__(out self, world: World):
        """Build the oscillator, the fold curve, and the shaper.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.world = world
        self.m = Messenger(self.world)

        self.osc = Osc[1](self.world)
        self.shaper = WaveShaper[1, Interp.cubic, TimesOversampling.x4](self.world)

        self.table = lockhart_fill4(Self.table_size)

        self.freq_lag = Lag[1](self.world, 0.05)
        self.drive = Lag[1](self.world, 0.05)

        self.freq = 220.0

    def next(mut self) -> MFloat[2]:
        """Fold one sample and send it to both channels.

        Returns:
            The folded output, the same in both channels.
        """
        self.m.update("freq", self.freq)

        var drive = self.drive.next(self.world[].mouse_x())

        var sig = self.osc.sine(self.freq_lag.next(MFloat[1](self.freq)))

        # The drive is the fold control: how far up the curve the sine reaches.
        var driven = sig * drive
        var folded = self.shaper.next(driven, self.table)

        return folded * dbamp(-12.0)
