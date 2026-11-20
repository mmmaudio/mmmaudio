from mmm_audio.constants import *
from mmm_audio.MMMWorld_Module import Interp
from mmm_audio.Windows_Module import kaiser_window, bessel_i0
from mmm_audio.functions import *
from std.sys import simd_width_of
from std.math import floor, log2, sin, sqrt


struct SincInterpolator[ripples: Int = 4, power: Int = 14](Movable, Copyable):
    """Sinc Interpolation of `List[Float64]`s.

    Struct for high-quality audio resampling using sinc interpolation. This struct precomputes a sinc table and provides methods for performing sinc interpolation
    on audio data with adjustable ripples and table size. It is used in Osc for resampling oscillator signals.

    As a user, you won't need to interact with this struct directly. Instead use the [ListInterpolator](Buffer.md#struct-spaninterpolator) struct.

    Parameters:
        ripples: Number of ripples in the sinc function, affecting interpolation quality.
        power: Power of two determining the size of the sinc table (table_size = 2^power).
    """
    var table: List[Float64]  # Sinc table for interpolation
    var table_size: Int  # Size of the sinc table
    var mask: Int  # Mask for wrapping indices
    var sinc_points: List[Int]  # Points for sinc interpolation
    var max_sinc_offset: Int 

    var sinc_power_f64: Float64
    var max_layer: Int

    def __init__(out self):
        self.table_size = 1 << self.power  # Size of the sinc table, e.g., 16384 for power 14 (using bit shift instead of exponentiation)
        self.mask = self.table_size - 1  # Mask for wrapping indices
        self.table = SincInterpolator.build_sinc_table(self.table_size)
        self.max_sinc_offset = self.table_size // (self.ripples * 2)  # Calculate maximum sinc offset based on spacing

        self.sinc_points = List[Int]()
        for i in range(self.table_size * 2):
            self.sinc_points.append(Int(i * self.table_size/(self.ripples * 2)))  # Initialize sinc points based on the sinc table size

        debug_assert[assert_mode="safe"](
            len(self.table) == self.mask + 1,
            "sinc table length ", len(self.table), " does not match mask ", self.mask,
        )

        self.sinc_power_f64 = Float64(self.power)  # Assuming sinc_power is 14
        self.max_layer = self.power - 3

    @doc_hidden
    @always_inline
    def interp_points(self, sp: Int, sinc_offset: Int, sinc_mult: Int, frac: Float64) -> Float64:
        """Helper function to perform quadratic interpolation on sinc table points.

        Returns the kernel weight for tap `sp`. The tap sits `offset = sp - ripples + 1` spacings
        from the spaced point at or below the read position, and the read position is
        `(sinc_offset + frac) / spacing` spacings above that point, so the kernel is evaluated at
        `t = offset - (sinc_offset + frac) / spacing`. The table holds t = -ripples..ripples
        with `max_sinc_offset` entries per unit, centered on index table_size / 2, so t maps to
        index `(sp + 1) * max_sinc_offset - (sinc_offset + frac) * sinc_mult`.
        """

        var f_index = Float64(self.sinc_points.unsafe_get(sp + 1)) - (Float64(sinc_offset) + frac) * Float64(sinc_mult)
        var index_floor = Int(f_index)
        var table_frac = f_index - Float64(index_floor)

        var idxA = index_floor & self.mask
        var idxB = (index_floor + 1) & self.mask
        var idxC = (index_floor + 2) & self.mask

        return quadratic_interp(
            self.table.unsafe_get(idxA),
            self.table.unsafe_get(idxB),
            self.table.unsafe_get(idxC),
            table_frac
        )

    @doc_hidden
    @always_inline  
    def spaced_sinc[num_chans: SIMDLength, bWrap: Bool = False, mask: Int = 0](self, data: Span[MFloat[num_chans], _], index: Int, frac: Float64, spacing: Int) -> MFloat[num_chans]:
        """Read using spaced sinc interpolation. This is a helper function for read_sinc."""
        var sinc_mult = self.max_sinc_offset // spacing
        var loop_count = Self.ripples * 2
        
        # Try to process in SIMD chunks if the loop is large enough
        comptime simd_width = simd_width_of[DType.float64]()
        var out: MFloat[num_chans] = MFloat[num_chans](0.0)
        var data_len: Int = len(data)
        check_wrap_mask[mask](data_len)
        
        # Process SIMD chunks
        var offset: Int
        for sp in range(loop_count):
            offset = Int(sp - Self.ripples + 1)
            
            comptime if bWrap:
                var loc_point_unwrapped = index + offset * spacing
                
                var loc_point: Int
                comptime if mask != 0:
                    loc_point = loc_point_unwrapped & mask
                else:
                    loc_point = loc_point_unwrapped % data_len
                    if loc_point < 0:
                        loc_point += data_len

                var spaced_point = loc_point & ~(spacing - 1)  # spacing is always 1 << layer
                var sinc_offset = loc_point - spaced_point
                
                var sinc_value = self.interp_points(sp, sinc_offset, sinc_mult, frac)
                out += sinc_value * data.unsafe_get(spaced_point)
            else:
                var loc_point = index + offset * spacing
                
                if loc_point >= 0 and loc_point < data_len:
                    var spaced_point = loc_point & ~(spacing - 1)
                    var sinc_offset = loc_point - spaced_point
                    
                    var sinc_value = self.interp_points(sp, sinc_offset, sinc_mult, frac)
                    out += sinc_value * data.unsafe_get(spaced_point)

        return out

    @always_inline
    def sinc_interp[num_chans: SIMDLength, bWrap: Bool = True, mask: Int = 0](self, data: Span[MFloat[num_chans], _], current_index: Float64, prev_index: Float64) -> MFloat[num_chans]:
        """Perform sinc interpolation on the given data at the specified current index.
        
        Parameters:
            num_chans: The number of channels in the audio data.
            bWrap: Whether to wrap around at the end of the buffer when an index exceeds the buffer length.
            mask: Mask for wrapping indices if bWrap is True.
        
        Args:
            data: The audio data (Buffer channel) to interpolate.
            current_index: The current fractional index for interpolation.
            prev_index: The previous index. Needed to calculate the slope.

        Returns:
            The sinc-interpolated sample value.
        """
        var size_f64: Float64 = Float64(len(data))
        var index_diff = current_index - prev_index
        var half_window = size_f64 * 0.5
        
        var slope_samples: Float64
        comptime if bWrap:
            slope_samples = wrap(index_diff, -half_window, half_window)  # Handle circular buffer wrap
        else:
            slope_samples = index_diff  # No wrapping
        
        var samples_per_frame = abs(slope_samples)
        
        var octave = clip(log2(samples_per_frame), 0.0, self.sinc_power_f64 - 2.0)
        var octave_floor = floor(octave)
        
        var layer = Int(octave_floor + 1.0)
        var sinc_crossfade = octave - octave_floor
        
        var layer_clamped = min(layer, self.max_layer)
        var selector: MBool[1] = (layer >= self.max_layer)
        sinc_crossfade = selector.select(0.0, sinc_crossfade)
        layer = layer_clamped
        
        var spacing1: Int = Int(1) << layer
        var spacing2: Int = spacing1 << 1
        
        var f_index = current_index
        var index_floor = Int(f_index)
        var frac = f_index - Float64(index_floor)
        
        var sinc1 = self.spaced_sinc[num_chans, bWrap, mask](data, index_floor, frac, spacing1)
        
        var sel0: MBool[num_chans] = MBool[num_chans](fill=(sinc_crossfade == 0.0))
        var sel1: MBool[num_chans] = MBool[num_chans](fill=(layer < 12))
        var sinc2 = sel0.select(0.0, sel1.select(self.spaced_sinc[num_chans,bWrap,mask](data, index_floor, frac, spacing2),0.0))
        
        return sinc1 + sinc_crossfade * (sinc2 - sinc1)

    @doc_hidden
    @staticmethod
    def build_sinc_table(table_size: Int) -> List[Float64]:
        
        # Index i holds the kernel at t = (i - table_size / 2) / (table_size / (2 * ripples)),
        # so t runs from -ripples (index 0) up to just below +ripples, t = 0 lands exactly on
        # index table_size / 2, and every integer t lands exactly on an index. The kernel is
        # symmetric, so index table_size (t = +ripples) wraps to index 0 (t = -ripples) correctly.
        var width = Float64(Self.ripples)
        var per_unit = Float64(table_size) / (2.0 * width)
        var center = table_size // 2

        # The beta parameter controls the trade-off between main lobe width and side lobe height
        var beta = 5.0  # Typical values range from 5 to 8 for audio processing
        var i0_beta = bessel_i0(beta)

        var table = List[Float64]()
        for i in range(table_size):
            var t = Float64(i - center) / per_unit
            var x = pi * t
            var s = 1.0 if i == center else sin(x) / x
            # Kaiser window evaluated at the same t, so it is centered on the same index as the sinc
            var r = t / width
            var window = bessel_i0(beta * sqrt(max(0.0, 1.0 - r * r))) / i0_beta
            table.append(s * window)

        return table.copy()