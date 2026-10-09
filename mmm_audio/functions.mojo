from mmm_audio.constants import *
from std.math import pow, log10, log, log2, abs, isnan, log1p, floor, iota
from std.python import PythonObject
from std.os import abort
from std.pathlib import Path
from std.random import random_float64, random_ui64

def mprint[*Ts: Writable](world: World, *values: *Ts, n_blocks: UInt16 = 10, sep: StringSlice[ImmStaticOrigin] = " ", end: StringSlice[ImmStaticOrigin] = "\n") -> None:
    """Prints the provided arguments to the console.

    Parameters:
        Ts: All printable values must implement the Writable trait. This parameter is inferred by the values passed to the function.

    Args:
        world: The World instance used for printing.
        values: A variable number of arguments to print.
        n_blocks: The number of blocks to print. Default is 10.
        sep: The separator between printed values. Default is a space.
        end: The string to print at the end. Default is a newline.
    """
    world[].print(*values, n_blocks=n_blocks, sep=sep, end=end)

@always_inline
def dbamp(db: MFloat[_]) -> type_of(db):
    """Converts decibel values to amplitude.

    amplitude = 10^(dB/20).

    Args:
        db: The decibel values to convert.

    Returns:
        The corresponding amplitude values.
    """
    return 10.0 ** (db / 20.0)

@always_inline
def ampdb(amp: MFloat[_]) -> type_of(amp):
    """Converts amplitude values to decibels.

    dB = 20 * log10(amplitude).

    Args:
        amp: The amplitude values to convert.

    Returns:
        The corresponding decibel values.
    """
    return 20.0 * log10(amp)

@always_inline
def power_to_db(value: Float64, zero_db_ref: Float64 = 1.0, amin: Float64 = 1e-10) -> Float64:
    """Convert a power value to decibels.

    This mirrors librosa's power_to_db behavior for a single scalar: 10 * log10(max(amin, value) / zero_db_ref).

    Args:
        value: Power value to convert.
        zero_db_ref: Reference power for 0 dB.
        amin: Minimum value to avoid log of zero.

    Returns:
        The value in decibels.
    """
    return 10.0 * log10(max(value, amin) / zero_db_ref)

@always_inline
def select[num_chans: SIMDLength](index: Float64, vals: Span[MFloat[num_chans], _]) -> MFloat[num_chans]:
    """Selects a value from a Span of SIMD vectors based on a floating-point index using linear interpolation.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        index: The floating-point index to select.
        vals: The Span of SIMD vectors containing the values.

    Returns:
        The interpolated value.
    """
    var index_int = Int(index) % len(vals)
    var index_mix: Float64 = index - Float64(index_int)
    var v0 = vals[index_int]
    var v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)

@always_inline
def select(index: Float64, vals: MFloat[_]) -> Float64:
    """Selects a value from a SIMD vector based on a floating-point index and using linear interpolation.

    Args:
        index: The floating-point index to select.
        vals: The SIMD vector containing the values.
    
    Returns:
        The interpolated value.
    """
    var index_int = Int(index) % len(vals)
    var index_mix: Float64 = index - Float64(index_int)
    var v0 = vals[index_int]
    var v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)

@always_inline
def select(index: Float64, *vals: MFloat[_]) -> type_of(vals[0]):
    """Selects a SIMD vector from a List of SIMD vectors based on a floating-point index using linear interpolation.

    Args:
        index: The floating-point index to select.
        vals: Either a VariadicList or a List of SIMD vectors containing the values.
    
    Returns:
        The interpolated value.
    """
    var index_int = Int(index) % len(vals)
    var index_mix: Float64 = index - Float64(index_int)
    var v0 = vals[index_int]
    var v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)


def check_reversed[dtype: DType](
    in_min: SIMD[dtype, _],
    in_max: type_of(in_min)
) -> Tuple[type_of(in_min), type_of(in_min), MBool[in_min.length]]:
    var ins_reversed: MBool[in_min.length] = in_min.gt(in_max)
    var in_min2 = ins_reversed.select(in_max, in_min)
    var in_max2 = ins_reversed.select(in_min, in_max)
    return (in_min2, in_max2, ins_reversed)

@always_inline
def linlin[
    dtype: DType, //
](input: SIMD[dtype, _], in_min: type_of(input) = 0, in_max: type_of(input) = 1, out_min: type_of(input) = 0, out_max: type_of(input) = 1) -> type_of(input):
    """Maps samples from one range to another range linearly.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.

    Samples outside the input range are clamped to the corresponding output boundaries.

    Args:
        input: The samples to map.
        in_min: The minimum of the input range.
        in_max: The maximum of the input range.
        out_min: The minimum of the output range.
        out_max: The maximum of the output range.

    Returns:
        The linearly mapped samples.
    """
    var in_min2, in_max2, _ = check_reversed(in_min, in_max)

    var normalized = (input - in_min2) / (in_max2 - in_min2)

    var out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)
 
    var result = out_min2 + normalized * (out_max2 - out_min2)
    return clip(result, out_min2, out_max2)

@always_inline
def expexp(
    input: MFloat[_], 
    in_min: type_of(input), 
    in_max: type_of(input), 
    out_min: type_of(input), 
    out_max: type_of(input)) -> type_of(input):
    """
    Exponential-to-exponential transform.
    
    Args:
        input: Input value to transform (exponential scale).
        in_min: Minimum of input range (exponential).
        in_max: Maximum of input range (exponential).
        out_min: Minimum of output range (exponential).
        out_max: Maximum of output range (exponential).
    
    Returns:
        Exponentially scaled output value.
    """
    
    var mask = (input.le(0.0)) | (in_min.le(0.0)) | (in_max.le(0.0)) | (out_min.le(0.0)) | (out_max.le(0.0)) | (input.lt(0.0))

    if any(mask):
        print("An expexp value is out of bounds. Retrurning out_min.")
        return out_min
    
    var in_min2, in_max2, _ = check_reversed(in_min, in_max)
    var input2 = clip(input, in_min2, in_max2)

    # Logarithmic normalization to 0-1 (exp → lin)
    var in_ratio = in_max2 / in_min2
    var normalized = log(input2 / in_min2) / log(in_ratio)
    
    var out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)

    # Exponential mapping to output (lin → exp)
    var out_ratio = out_max2 / out_min2
    var result = out_min2 * pow(out_ratio, normalized)
    
    return clip(result, out_min2, out_max2)

@always_inline
def linexp(input: MFloat[_], in_min: type_of(input), in_max: type_of(input), out_min: type_of(input), out_max: type_of(input)) -> type_of(input):
    """Maps samples from one linear range to another exponential range.

    Args:
        input: The samples to map.
        in_min: The minimum of the input range.
        in_max: The maximum of the input range.
        out_min: The minimum of the output range.
        out_max: The maximum of the output range.

    Returns:
        The exponentially mapped samples.
    """
    
    var mask = (out_min.le(0.0)) | (out_max.le(0.0))
    if any(mask):
        print("linexp error: out_min and out_max must be greater than 0. Returning input.")
        return input


    var in_min2, in_max2, _ = check_reversed(in_min, in_max)
    
    var input2 = clip(input, in_min2, in_max2)
    var normalized = (input2 - in_min2) / (in_max2 - in_min2)

    var out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    var ratio = out_max2 / out_min2
    var result = out_min2 * pow(ratio, normalized)
    
    result = outs_reversed.select(out_min2 * out_max2 / result, result)
    
    return clip(result, out_min2, out_max2)

def explin(input: MFloat[_], in_min: type_of(input), in_max: type_of(input), out_min: type_of(input), out_max: type_of(input)) -> type_of(input):
    """
    Exponential-to-linear transform (inverse of linexp).
    
    Args:
        input: Input value to transform (exponential scale).
        in_min: Minimum of input range (exponential).
        in_max: Maximum of input range (exponential).
        out_min: Minimum of output range (linear).
        out_max: Maximum of output range (linear).
    
    Returns:
        Linearly scaled output value.
    """

    var mask = (input.le(0.0)) | (in_min.le(0.0)) | (in_max.le(0.0))

    if any(mask):
        print("An explin value is out of bounds. Retrurning input.")
        return input
    
    var in_min2, in_max2, _ = check_reversed(in_min, in_max)
    var input2 = clip(input, in_min2, in_max2)
    var ratio = in_max2 / in_min2
    var normalized = log(input2 / in_min2) / log(ratio)
    
    var out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)

    # Map to output range
    var result = out_min2 + normalized * (out_max2 - out_min2)
    
    return clip(result, out_min2, out_max2)

@always_inline
def lincurve(input: MFloat[_], in_min: type_of(input), in_max: type_of(input), out_min: type_of(input), out_max: type_of(input), curve: type_of(input)) -> type_of(input):
    """Maps a linear input to a curved output range based on a curve parameter.

    Args:
        input: Input value to transform (linear).
        in_min: Minimum of input range (linear).
        in_max: Maximum of input range (linear).
        out_min: Minimum of output range (curved).
        out_max: Maximum of output range (curved).
        curve: Curve parameter (pow(normalized, curve))
               curve = 1: linear
               curve > 1: exponential (slow start, steep end)
               curve > 0 and < 1: logarithmic (steep start, slow end).
    
    Returns:
        Curved output value.
    """

    var normalized = clip((input - in_min) / (in_max - in_min), 0.0, 1.0)

    var _, _, ins_reversed = check_reversed(in_min, in_max)
    normalized = ins_reversed.select(1-normalized, normalized)
    
    var curve2 = clip(curve, 1e-5, 8192.0)

    var out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    var curved = outs_reversed.select(1.0-pow(normalized, 1.0/curve2), pow(normalized, curve2))
    return clip(out_min2 + curved * (out_max2 - out_min2), out_min2, out_max2)

def linmap(x: MFloat[_], *points: Tuple[type_of(x), type_of(x)]) -> type_of(x):
    """Linearly maps an input value `x` based on a series of input-output points.

    The function takes a variable number of (input, output) pairs and linearly maps the input `x` to the corresponding output value based on which segment of the input range `x` falls into. If `x` is outside the range of the provided points, it will be clamped to the nearest segment.

    Args:
        x: The input value to be mapped.
        points: A variable number of (input, output) pairs that define the mapping. For example, `linmap(x, (0, 0), (0.5, 1), (1, 0))` defines a mapping where 0 maps to 0, 0.5 maps to 1, and 1 maps to 0.

    Returns:
        The mapped output value corresponding to the input `x`.
    """
    var length = len(points)
    if length < 2:
        return x
    
    # Handle cases where x is outside the range of provided points
    if x <= points[0][0]:
        return points[0][1]
    if x >= points[length-1][0]:
        return points[length-1][1]
    # Find the segment that x falls into
    for i in range(length - 1):
        var x0, y0 = points[i]
        var x1, y1 = points[i + 1]
        if x0 <= x <= x1:
            # Perform linear interpolation
            return y0 + (y1 - y0) * ((x - x0) / (x1 - x0))
    return points[length - 1][1]

def py_to_float64(py_float: PythonObject) raises -> Float64:
    return Float64(py=py_float)

# def max[dtype: DType, //](x: SIMD[dtype], y: SIMD[dtype, x.length], /) -> SIMD[dtype, x.length]
@always_inline
def clip[
    dtype: DType, //
](x: SIMD[dtype, _], lo: type_of(x), hi: type_of(x)) -> type_of(x):
    """Clips each element in the SIMD vector to the specified range.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        x: The SIMD vector to clip. Each element will be clipped individually.
        lo: The minimum possible value.
        hi: The maximum possible value.

    Returns:
        The clipped SIMD vector.
    """ 
    return min(max(x, lo), hi)

##########This is the downside of switching to Int. 

@always_inline
def clip(x: Int, lo: Int, hi: Int) -> Int:
    return min(max(x, lo), hi)

@always_inline
def wrap(x: Int, lo: Int, hi: Int) -> Int:
    var range_size = hi - lo
    if range_size <= 0:
        return x
    var wrapped = (x - lo) % range_size + lo
    return wrapped

@always_inline
def wrap[
    dtype: DType, //
](input: SIMD[dtype, _], min_val: type_of(input), max_val: type_of(input)) -> type_of(input):
    """Wraps a sample around a specified range.

    The wrapped sample within the range [min_val, max_val). 
    This function uses modulus arithmetic so the output can never equal max_val.
    Returns the sample if min_val >= max_val.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        input: The sample to wrap.
        min_val: The minimum of the range.
        max_val: The maximum of the range.

    Returns:
        The wrapped value.
    """
    # Check if any min_val >= max_val (vectorized comparison)
    var invalid_range: MBool[input.length] = min_val.ge(max_val)
    
    var range_size = max_val - min_val
    var wrapped_sample = (input - min_val) % range_size + min_val
    
    # Handle negative modulo results (vectorized)
    var needs_adjustment: MBool[input.length] = wrapped_sample.lt(min_val)

    wrapped_sample = needs_adjustment.select(wrapped_sample + range_size, wrapped_sample)

    # Return original input where range is invalid, wrapped result otherwise
    return invalid_range.select(input, wrapped_sample)

def fold[dtype: DType](x: SIMD[dtype, _], lo: type_of(x), hi: type_of(x)) -> type_of(x):
    var lo2, hi2, _ = check_reversed(lo, hi)
    var range_size = hi2 - lo2
    var wrapped = (x - lo2) % (2 * range_size)

    var mask = wrapped.lt(range_size)
    var folded = mask.select(wrapped, (2 * range_size - wrapped))
    return folded + lo2

@always_inline
def check_wrap_mask[mask: Int](length: Int):
    """Verify that a compile-time wrap mask matches the runtime length of the table it wraps. Does nothing when `mask` is 0, which selects modulo wrapping instead.

    Parameters:
        mask: The bitmask that will be applied to indices.

    Args:
        length: The number of elements actually available to index.
    """
    # Plain debug_assert, so this is compiled out unless the build passes
    # -D ASSERT=all. The readers run inside the audio thread's per-sample loop and
    # the mask/length relationship is fixed for the life of a table, so checking it
    # at sample rate only pays off when the optimizer hoists it. ASSERT=all is also
    # the build in which unsafe_get regains its own bounds checks, so running the
    # tests that way validates every mask in the codebase at once.
    comptime if mask != 0:
        debug_assert(
            length == mask + 1,
            "wrap mask ", mask, " requires a table length of ", mask + 1,
            " but the table has ", length, " elements",
        )

@always_inline
def quadratic_interp[
    dtype: DType, //
](y0: SIMD[dtype, _], y1: type_of(y0), y2: type_of(y0), x: type_of(y0)) -> type_of(x):
    """Performs quadratic interpolation between three points.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
    
    Args:
        y0: The sample at position 0.
        y1: The sample at position 1.
        y2: The sample at position 2.
        x: The interpolation position (fractional part between 0 and 1).

    Returns:
        The interpolated sample at position x.
    """
    # Calculate the coefficients of the quadratic polynomial
    var xm1 = x - 1.0
    var xm2 = x - 2.0

    # Compute Lagrange coefficients for all elements
    var coeff0 = (xm1 * xm2) * 0.5
    var coeff1 = (x * xm2) * (-1.0)  
    var coeff2 = (x * xm1) * 0.5

    # Apply coefficients to y samples and sum
    var out = coeff0 * y0 + coeff1 * y1 + coeff2 * y2

    return out

@always_inline
def cubic_interp[
    dtype: DType, //
](p0: SIMD[dtype, _], p1: type_of(p0), p2: type_of(p0), p3: type_of(p0), t: type_of(p0)) -> type_of(p0):
    """
    Performs cubic interpolation.

    Cubic Intepolation equation from *The Audio Programming Book* 
    by Richard Boulanger and Victor Lazzarini. pg. 400

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
    
    Args:
        p0: Point to the left of p1.
        p1: Point to the left of the float t.
        p2: Point to the right of the float t.
        p3: Point to the right of p2.
        t: Interpolation parameter (fractional part between p1 and p2).
    
    Returns:
        Interpolated sample.
    """
    return p1 + (((p3 - p0 - 3*p2 + 3*p1)*t + 3*(p2 + p0 - 2*p1))*t - (p3 + 2*p0 - 6*p2 + 3*p1))*t / 6.0

@always_inline
def lagrange4[
    dtype: DType, //
](sample0: SIMD[dtype, _], sample1: type_of(sample0), sample2: type_of(sample0), sample3: type_of(sample0), sample4: type_of(sample0), frac: type_of(sample0)) -> type_of(sample0):
    """
    Perform Lagrange interpolation for 4th order case (from JOS Faust Model). This is extrapolated from the JOS Faust filter model.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        sample0: The first sample.
        sample1: The second sample.
        sample2: The third sample.
        sample3: The fourth sample.
        sample4: The fifth sample.
        frac: The fractional part between sample0 and sample1.

    Returns:
        The interpolated sample.
    """

    comptime o = 1.4999999999999999  # to avoid edge case issues
    var fd = o + frac

    # simd optimized!
    var out: SIMD[dtype, sample0.length] = SIMD[dtype, sample0.length](0.0)

    var fdm1: SIMD[dtype, sample0.length] = SIMD[dtype, sample0.length](0.0)
    var fdm2: SIMD[dtype, sample0.length] = SIMD[dtype, sample0.length](0.0)
    var fdm3: SIMD[dtype, sample0.length] = SIMD[dtype, sample0.length](0.0)
    var fdm4: SIMD[dtype, sample0.length] = SIMD[dtype, sample0.length](0.0)

    comptime offsets = SIMD[dtype, 4](1.0, 2.0, 3.0, 4.0)

    comptime for i in range(sample0.length):
        var fd_vec = SIMD[dtype, 4](fd[i], fd[i], fd[i], fd[i])

        var fd_minus_offsets = fd_vec - offsets  # [fd-1, fd-2, fd-3, fd-4]

        fdm1[i] = fd_minus_offsets[0]
        fdm2[i] = fd_minus_offsets[1]
        fdm3[i] = fd_minus_offsets[2]
        fdm4[i] = fd_minus_offsets[3]

    # all this math is parallelized - for N > 4, this should be further optimized
    var coeff0 = fdm1 * fdm2 * fdm3 * fdm4 / 24.0
    var coeff1 = (0.0 - fd) * fdm2 * fdm3 * fdm4 / 6.0
    var coeff2 = fd * fdm1 * fdm3 * fdm4 / 4.0
    var coeff3 = (0.0 - fd * fdm1 * fdm2 * fdm4) / 6.0
    var coeff4 = fd * fdm1 * fdm2 * fdm3 / 24.0

    comptime for i in range(sample0.length):
        var coeffs: SIMD[dtype, 4] = SIMD[dtype, 4](coeff0[i], coeff1[i], coeff2[i], coeff3[i])

        var samples_simd = SIMD[dtype, 4](
            sample0[i],
            sample1[i],
            sample2[i],
            sample3[i]
        )

        var products = samples_simd * coeffs

        out[i] = products.reduce_add() + sample4[i] * coeff4[i]

    return out

@always_inline
def linear_interp[
    dtype: DType, //
](p0: SIMD[dtype, _], p1: type_of(p0), t: type_of(p0)) -> type_of(p0):
    """
    Performs linear interpolation between two points.
    
    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        p0: The starting point.
        p1: The ending point.
        t: The interpolation parameter (fractional part between p0 and p1).
    
    Returns:
        The interpolated sample.
    """
    
    return p0 + ((p1 - p0) * t)

@always_inline
def midicps(midi_note_number: MFloat[_], reference_midi_note: Float64 = 69, reference_frequency: Float64 = 440.0) -> type_of(midi_note_number):
    """Convert MIDI note numbers to frequencies in Hz.

    (cps = "cycles per second")

    Conversion happens based on equating the `reference_midi_note` to the `reference_frequency`.
    For standard tuning, leave the defaults of MIDI note 69 (A4) and 440.0 Hz.

    Args:
        midi_note_number: The MIDI note number(s) to convert.
        reference_midi_note: The reference MIDI note number.
        reference_frequency: The frequency of the reference MIDI note.
    
    Returns:
        Frequency in Hz.
    """
    var exponent = (midi_note_number - reference_midi_note) / 12.0
    var frequency = Float64(reference_frequency) * pow(MFloat[midi_note_number.length](2.0), exponent)
    return frequency


@always_inline
def cpsmidi(freq: MFloat[_], reference_midi_note: Float64 = 69.0, reference_frequency: Float64 = 440.0) -> type_of(freq):
    """Convert frequencies in Hz to MIDI note numbers.
    
    (cps = "cycles per second")

    Conversion happens based on equating the `reference_midi_note` to the `reference_frequency`.
    For standard tuning, leave the defaults of MIDI note 69 (A4) and 440.0 Hz.

    Args:
        freq: The frequency in Hz to convert.
        reference_midi_note: The reference MIDI note number.
        reference_frequency: The frequency of the reference MIDI note.

    Returns:
        The corresponding MIDI note number.
    """

    var n = 12.0 * log2(abs(freq) / reference_frequency) + reference_midi_note
    return n

@always_inline
def sanitize(x: MFloat[_]) -> type_of(x):
    """Sanitizes a SIMD float64 vector by zeroing out elements that are too large, too small, or NaN.

    Args:
        x: The SIMD float64 vector to sanitize.
    
    Returns:
        The sanitized SIMD float64 vector.
    """

    var absx = abs(x)
    var too_large: MBool[x.length] = absx.gt(MFloat[x.length](1e15))
    var too_small: MBool[x.length] = absx.lt(MFloat[x.length](1e-15))
    var is_nan: MBool[x.length] = isnan(x)
    var should_zero: MBool[x.length] = too_large | too_small | is_nan

    return should_zero.select(0.0, x)

comptime _GOLDEN64 = 0x9E3779B97F4A7C15
"""The 64-bit golden-ratio odd constant, used to space seeds and lanes apart."""

@doc_hidden
@always_inline
def _splitmix64[N: SIMDLength](var z: SIMD[DType.uint64, N]) -> SIMD[DType.uint64, N]:
    """The splitmix64 finalizer, evaluated on a whole vector at once."""
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    return z ^ (z >> 31)

@doc_hidden
@always_inline
def _simd_uniform[N: SIMDLength]() -> MFloat[N]:
    """Draw one 64-bit value and expand it across N lanes with a vectorized splitmix64.

    See SIMDRand for an even more efficient implementation.
    """
    var bits = SIMD[DType.uint64, N](random_ui64(0, 0xFFFFFFFFFFFFFFFF))

    bits += iota[DType.uint64, N]() * _GOLDEN64

    return MFloat[N](from_bits=(_splitmix64(bits) >> 12) | 0x3FF0000000000000) - 1.0

def rrand(min: Int, max: Int) -> Int:
    """Generates a random Int from a uniform distribution. Can receive a SIMD Float or an Int, returning the same type.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (inclusive).

    Returns:
        A random Int sample from the specified range.
    """
    var range = (max - min) + 1
    
    return min + Int(random_ui64(0, 0xFFFFFFFFFFFFFFFF) % UInt64(range))

def rrand(min: MFloat[_], max: type_of(min)) -> type_of(min):
    """Generates a random value from a uniform distribution. Can receive a SIMD Float or an Int, returning the same type.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (exclusive).

    Returns:
        A random Float64 sample from the specified range.
    """

    return min + (max - min) * _simd_uniform[min.length]()

@always_inline
def exprand(min: MFloat[_], max: type_of(min)) -> type_of(min):
    """Generates a random float64 sample from an exponential distribution.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (inclusive).

    Returns:
        A random Float64 sample from the specified range.
    """
    var u = MFloat[min.length](0.0)
    comptime for i in range(min.length):
        u[i] = random_float64()
    u = linexp(u, 0.0, 1.0, min, max)
    return u

def sign(x: MFloat[_]) -> type_of(x):
    """Returns the sign of x: -1 if negative, 1 if positive, and 0 if zero.

    Args:
        x: The input SIMD vector.

    Returns:
        A SIMD vector containing the sign of each element in x.
    """
    var pmask:MBool[x.length] = x.gt(0.0)
    var nmask:MBool[x.length] = x.lt(0.0)

    return pmask.select(MFloat[x.length](1.0), nmask.select(MFloat[x.length](-1.0), MFloat[x.length](0.0)))

def linspace(start: Float64, stop: Float64, num: Int, endpoint: Bool = True) -> List[Float64]:
    """Create evenly spaced values between start and stop.
    
    Args:
        start: The starting value.
        stop: The ending value.
        num: Number of samples to generate.
        endpoint: Whether to include the stop value in the output (default: True).
    
    Returns:
        A List of Float64 values evenly spaced between start and stop.
    """
    var result = List[Float64](length=num, fill=0.0)
    if num == 1:
        result[0] = start
        return result^
    
    var step = (stop - start) / Float64(num - 1) if endpoint else (stop - start) / Float64(num)

    for i in range(num):
        result[i] = start + Float64(i) * step
    return result^

def diff(arr: Span[Float64, ...]) -> List[Float64]:
    """Compute differences between consecutive elements.
    
    Args:
        arr: Input list of Float64 values.
    
    Returns:
        A new list with length len(arr) - 1 containing differences.
    """
    var result = List[Float64](length=len(arr) - 1, fill=0.0)
    for i in range(len(arr) - 1):
        result[i] = arr[i + 1] - arr[i]
    return result^

def subtract_outer(a: Span[Float64, ...], b: Span[Float64, ...]) -> List[List[Float64]]:
    """Compute outer subtraction: a[i] - b[j] for all i, j.
    
    Args:
        a: First input list (will be rows).
        b: Second input list (will be columns).
    
    Returns:
        A 2D list where result[i][j] = a[i] - b[j].
    """
    var result = List[List[Float64]](length=len(a), fill=List[Float64]())
    for i in range(len(a)):
        result[i] = List[Float64](length=len(b), fill=0.0)
        for j in range(len(b)):
            result[i][j] = a[i] - b[j]
    return result^

def coin(p: MFloat[_]) -> MBool[p.length]:
    """Return True with probability p, False otherwise.
    
    Args:
        p: Probability of returning True (between 0 and 1).
    
    Returns:
        True with probability p, False otherwise.
    """
    var q = clip(p, 0.0, 1.0) 
    var rands = rrand(MFloat[p.length](0.0), MFloat[p.length](1.0))
    var coins = rands.lt(q)
    return coins

def choose[dtype: DType](*vals: SIMD[dtype, _]) -> type_of(vals[0]):
    """Choose a random index from a variadic list of values.
    
    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function so the values passed can be any DType of SIMD vector.

    Args:
        vals: A variable number of items to choose from.
    
    Returns:
        An item chosen randomly from the provided values.
    """
    var num_vals = len(vals)
    if num_vals == 0:
        return 0.0
    var idx = rrand(0, num_vals - 1)
    return vals[idx]

def choose[dtype: DType, N: SIMDLength](items: Span[SIMD[dtype, N], _]) -> type_of(items[0]):
    """Choose a random index.
    
    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function so the values passed can be any DType of SIMD vector.
        N: The length of the SIMD vector. Inferred by the values passed to the function.

    Args:
        items: A List or Array of items to choose from.
    
    Returns:
        An item chosen randomly from the provided values.
    """
    var num_vals = len(items)
    debug_assert(num_vals > 0, "items must not be empty")
    var idx = rrand(0, num_vals - 1)
    return items[idx]

def wchoose[dtype: DType, N: SIMDLength](items: Span[SIMD[dtype, N], _], weights: Span[Float64, _]) -> type_of(items[0]):
    """Choose a random index from the list of weights.
    
    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function so the values passed can be any DType of SIMD vector.
        N: The length of the SIMD vector.

    Args:
        items: A variable number of items to choose from. Can be any DType of SIMD vector.
        weights: A list of weights for the items.
    
    Returns:
        An item chosen randomly from the provided values.
    """
    debug_assert(len(items) == len(weights), "items and weights must be the same length")
    debug_assert(len(items) > 0, "items must not be empty")
    
    var max = 0.0
    var selected_item: Optional[type_of(items[0])] = None

    for item, weight in zip(items, weights):
        if weight <= 0:
            continue

        var u = rrand(0.001, 1.0)
        
        # Calculate the Efraimidis-Spirakis sort key: k_i = u_i ** (1 / w_i)
        var key = u ** (1.0 / weight)
        if key > max:
            max = key
            selected_item = item

    return selected_item.value() if selected_item is not None else choose(items)

@doc_hidden
def _reverse_range[T: ImplicitlyCopyable & Deinitable](mut data: List[T], start: Int, end: Int):
    var s = start
    var e = end
    while s < e:
        data[s], data[e] = data[e], data[s]
        s += 1
        e -= 1

def rotate_left_inplace[T: ImplicitlyCopyable & Deinitable](mut data: List[T], N: Int):
    """Rotates a list to the left by N positions in-place.

    Parameters:
        T: Element type stored in the list.

    Args:
        data: The list to rotate.
        N: The number of positions to rotate the list by.
    """
    var n = N % len(data)
    
    _reverse_range(data, 0, n - 1)      # Reverse first part
    _reverse_range(data, n, len(data) - 1)  # Reverse second part
    _reverse_range(data, 0, len(data) - 1)  # Reverse entire array

def rotate_right_inplace[T: ImplicitlyCopyable & Deinitable](mut data: List[T], N: Int):
    """Rotates a list to the right by N positions in-place.

    Parameters:
        T: Element type stored in the list.

    Args:
        data: The list to rotate.
        N: The number of positions to rotate the list by.
    """
    if len(data) == 0:
        return

    var n = len(data) - (N % len(data))
    
    _reverse_range(data, 0, n - 1)      # Reverse first part
    _reverse_range(data, n, len(data) - 1)  # Reverse second part
    _reverse_range(data, 0, len(data) - 1)  # Reverse entire array

struct TopNPeaks(Movable,Copyable):
    var ordinal: List[Int]

    def __init__(out self):
        self.ordinal = List[Int]()

    def process(mut self, in_list: Span[Float64,...], N: Int, out_list: Span[mut=True,Int,...], thresh: Float64 = 100.0) -> Int:
        """Return the indices of the top N largest values in the array.
        
        Args:
            in_list: Input list of Float64 values.
            N: The number of top indices to return.
            out_list: A pre-allocated list to store the output indices. Should have length N.
            thresh: The minimum value to include in the list.
        
        Returns:
            An integer indicating the number of valid peaks found (up to N). The indices of the peaks are stored in out_list.
        """

        var in_list_len: Int = len(in_list)

        self.ordinal.resize(in_list_len, 0)

        for i in range(in_list_len):
            self.ordinal[i] = i

        for i in range(N):
            out_list[i] = 0

        def cmp_fn(a: Int, b: Int) {imm in_list} -> Bool:
            return in_list[a] > in_list[b]

        # TODO: is it possible to find the peaks and then sort only those?
        # it's not completely necessary to sort the whole list here.
        sort(self.ordinal, cmp_fn)

        var valid_peaks: Int = 0
        for idx in self.ordinal:
            if idx > 0 and idx < in_list_len - 1 and in_list[idx] > thresh and in_list[idx] > in_list[idx - 1] and in_list[idx] > in_list[idx + 1]:
                out_list[valid_peaks] = idx
                valid_peaks += 1
                if valid_peaks == N:
                    return valid_peaks
        return valid_peaks

def find_quadratic_peak(p1: Float64, p2: Float64, p3: Float64) -> Tuple[Float64, Float64]:
    """
    Find the vertex of a quadratic function passing through three points.
    Points are at x = 0, 1, 2 with y values p1, p2, p3.
    
    For y = ax^2 + bx + c:
    - At x=0: c = p1
    - At x=1: a + b + c = p2
    - At x=2: 4a + 2b + c = p3

    Args:
        p1: The first sample value.
        p2: The middle sample value.
        p3: The third sample value.

    Returns:
        The x-position and y-value of the quadratic peak.
    """
    var c = p1
    var a = (p3 - 2.0 * p2 + p1) / 2.0
    var b = (p2 - p1) - a
    
    if a == 0.0:
        return (1.0, p2)  # Linear case, return middle point
    
    var vertex_x = -b / (2.0 * a)
    var vertex_y = a * vertex_x * vertex_x + b * vertex_x + c
    
    return (vertex_x, vertex_y)

# Minimax polynomial coefficients for sin and cos on [-pi/4, pi/4], from the
# FDLIBM kernels. Both polynomials are accurate to within an ulp over that range.
comptime _S1 = -1.66666666666666324348e-01
comptime _S2 = 8.33333333332248946124e-03
comptime _S3 = -1.98412698298579493134e-04
comptime _S4 = 2.75573137070700676789e-06
comptime _S5 = -2.50507602534068634195e-08
comptime _S6 = 1.58969099521155010221e-10

comptime _C1 = 4.16666666666666019037e-02
comptime _C2 = -1.38888888888741095749e-03
comptime _C3 = 2.48015872894767294178e-05
comptime _C4 = -2.75573143513906633035e-07
comptime _C5 = 2.08757232129817482790e-09
comptime _C6 = -1.13596475577881948265e-11

# 2/pi, then pi/2 split into three parts so that `n * _PI_2_HI` stays exact for
# |n| < 2**20 and the low parts carry the bits that would otherwise be lost.
comptime _TWO_OVER_PI = 6.36619772367581382433e-01
comptime _PI_2_HI = 1.57079632673412561417e+00
comptime _PI_2_MID = 6.07710050630396597660e-11
comptime _PI_2_LO = 2.02226624879595063154e-21

@always_inline
def sincos(x: MFloat[_]) -> Tuple[type_of(x), type_of(x)]:
    """Computes the sine and cosine of x together, using minimax polynomials.

    Unlike `std.math.sin` and `std.math.cos`, which fall back to a scalar libm call
    per lane, this evaluates every lane of the vector at once and shares the argument
    reduction between the two results. That makes it several times faster than calling
    `sin` and `cos` separately on a SIMD vector, at close to the same accuracy (within
    a few ulps for arguments up to roughly 1e6 radians, degrading gradually past that).

    Args:
        x: The angle, or SIMD vector of angles, in radians.

    Returns:
        A Tuple of (sine of x, cosine of x).
    """
    # Cody-Waite reduction: x = n*(pi/2) + r, with r in [-pi/4, pi/4]
    var n = round(x * _TWO_OVER_PI)
    var r = ((x - n * _PI_2_HI) - n * _PI_2_MID) - n * _PI_2_LO

    var z = r * r

    var sin_poly = _S1 + z * (_S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6))))
    var cos_poly = _C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6))))

    var sin_r = r + (r * z) * sin_poly
    var cos_r = (1.0 - 0.5 * z) + (z * z) * cos_poly

    # Fold the quadrant back in. n varies per lane, so this has to be a blend, not a branch.
    var quadrant = n.cast[DType.int]()
    var swapped = (quadrant & 1).ne(0)
    var sin_x = swapped.select(cos_r, sin_r)
    var cos_x = swapped.select(sin_r, cos_r)

    sin_x = (quadrant & 2).ne(0).select(-sin_x, sin_x)
    cos_x = ((quadrant + 1) & 2).ne(0).select(-cos_x, cos_x)

    return (sin_x, cos_x)


# Minimax polynomial for atan on [-tan(pi/8), tan(pi/8)], from the FDLIBM kernel.
comptime _AT0 = 3.33333333333329318027e-01
comptime _AT1 = -1.99999999998764832476e-01
comptime _AT2 = 1.42857142725034663711e-01
comptime _AT3 = -1.11111104054623557880e-01
comptime _AT4 = 9.09088713343650656196e-02
comptime _AT5 = -7.69187620504482999495e-02
comptime _AT6 = 6.66107313738753120669e-02
comptime _AT7 = -5.83357013379057348645e-02
comptime _AT8 = 4.97687799461593236017e-02
comptime _AT9 = -3.65315727442169155270e-02
comptime _AT10 = 1.62858201153657823623e-02

comptime _TAN_PI_8 = 0.4142135623730951

# Each angle is split into the nearest double and the bit of it that does not fit,
# so that the quadrant corrections below stay accurate to the last place.
comptime _QUARTER_PI = 0.7853981633974483
comptime _QUARTER_PI_TAIL = 3.061616997868383e-17
comptime _HALF_PI = 1.5707963267948966
comptime _HALF_PI_TAIL = 6.123233995736766e-17
comptime _ONE_PI = 3.141592653589793
comptime _ONE_PI_TAIL = 1.2246467991473532e-16


@always_inline
def fast_atan2[dtype: DType, //](y: SIMD[dtype, _], x: type_of(y)) -> type_of(y):
    """Computes atan2(y, x) with a minimax polynomial, evaluating every SIMD lane at once.

    `std.math.atan2` falls back to a scalar libm call per lane, so on a SIMD vector this
    is several times faster, at close to the same accuracy (within a few ulps). Unlike
    libm it does not distinguish the sign of a zero argument, so `fast_atan2(-0.0, -1.0)`
    returns pi rather than -pi. Zero over zero returns zero, as libm does.

    It works for any float dtype, and is built only from arithmetic and selects, so unlike
    `std.math.atan2` it also compiles for Metal, where `RealFFTGPU` relies on it.

    Parameters:
        dtype: The float dtype of the arguments, inferred from them.

    Args:
        y: The ordinate, or SIMD vector of ordinates.
        x: The abscissa, or SIMD vector of abscissas.

    Returns:
        The angle in radians between the positive x axis and the point (x, y), in [-pi, pi].
    """
    var a = abs(y)
    var b = abs(x)

    # Work with whichever ratio lands in [0, 1], then undo the swap afterwards
    var swapped = a.gt(b)
    var num = swapped.select(b, a)
    var den = swapped.select(a, b)

    # den is max(|y|, |x|), so it is only zero when both inputs are; keep the divide finite
    var t = num / den.eq(0.0).select(type_of(y)(1.0), den)

    # atan(t) = pi/4 + atan((t - 1)/(t + 1)) folds (tan(pi/8), 1] down onto the poly's range
    var folded = t.gt(_TAN_PI_8)
    var z = folded.select((t - 1.0) / (t + 1.0), t)

    # Odd polynomial in z, split into two chains so the two halves evaluate in parallel
    var zz = z * z
    var w = zz * zz
    var lo = zz * (_AT0 + w * (_AT2 + w * (_AT4 + w * (_AT6 + w * (_AT8 + w * _AT10)))))
    var hi = w * (_AT1 + w * (_AT3 + w * (_AT5 + w * (_AT7 + w * _AT9))))
    var core = z - z * (lo + hi)

    var r = folded.select(_QUARTER_PI + (core + _QUARTER_PI_TAIL), core)
    r = swapped.select((_HALF_PI - r) + _HALF_PI_TAIL, r)
    r = x.lt(0.0).select((_ONE_PI - r) + _ONE_PI_TAIL, r)
    return y.lt(0.0).select(-r, r)

@always_inline
def fast_tanh[w: Int](x: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """Hyperbolic tangent of float32 values, from a rational approximation.

    A degree 9/8 minimax rational approximation, accurate to within 1.5e-7 for |x| < 8.01773357391357422.

    Args:
        x: The input SIMD vector of float32 values.

    Returns:
        The hyperbolic tangent of each element in x.
    """
    var c = x.clamp(-8.01773357391357422, 8.01773357391357422)
    var x2 = c * c
    var p = ((1.394553628e-8 * x2 + 2.102733560e-5) * x2 + 3.520756727e-3) * x2 + 1.340216100e-1
    var q = (((8.015776984e-7 * x2 + 3.326951409e-4) * x2 + 2.597254514e-2) * x2 + 4.673548340e-1) * x2 + 1.0
    return (x2 * c * p + c) / q

@always_inline
def nam_fast_tanh[w: Int](x: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """NeuralAmpModelerCore's rational `fast_tanh`: cheaper, but only good to about 9e-4.

    Kept for NAM models whose activation is "Fasttanh", which were trained with exactly
    this function. Prefer `fast_tanh` everywhere else.

    Args:
        x: The input SIMD vector of float32 values.

    Returns:
        An approximation of the hyperbolic tangent of each element in x.
    """
    var ax = abs(x)
    var x2 = x * x
    return (
        x * (2.45550750702956 + 2.45550750702956 * ax + (0.893229853513558 + 0.821226666969744 * ax) * x2)
        / (2.44506634652299 + (2.44506634652299 + x2) * abs(x + 0.814642734961073 * x * ax))
    )

def all_lanes_equal[dtype: DType, width: SIMDLength](v: SIMD[dtype, width]) -> Bool:
    return (v.eq(v[0])).reduce_and()

@doc_hidden
def horner[num_chans: SIMDLength, coeffs: Span[Float64, ...]](z: MFloat[num_chans]) -> MFloat[num_chans]:
    """Evaluate polynomial using Horner's method."""
    var result: MFloat[num_chans] = 0.0
    for i in range(len(coeffs) - 1, -1, -1):
        result = result * z + coeffs[i]
    return result

@doc_hidden
def Li2[num_chans: SIMDLength](x: MFloat[num_chans]) -> MFloat[num_chans]:
    """Compute the dilogarithm (Spence's function) Li2(x) for SIMD vectors."""

    # Coefficients for double precision
    comptime P = [1.07061055633093042767673531395124630e+0, -5.25056559620492749887983310693176896e+0, 1.03934845791141763662532570563508185e+1, -1.06275187429164237285280053453630651e+1, 5.95754800847361224707276004888482457e+0, -1.78704147549824083632603474038547305e+0, 2.56952343145676978700222949739349644e-1, -1.33237248124034497789318026957526440e-2, 7.91217309833196694976662068263629735e-5]

    comptime Q = [1.00000000000000000000000000000000000e+0, -5.20360694854541370154051736496901638e+0, 1.10984640257222420881180161591516337e+1, -1.24997590867514516374467903875677930e+1, 7.97919868560471967115958363930214958e+0, -2.87732383715218390800075864637472768e+0, 5.49210416881086355164851972523370137e-1, -4.73366369162599860878254400521224717e-2, 1.23136575793833628711851523557950417e-3]

    comptime pi_sq = pi * pi

    # Initialize output variables
    var y: MFloat[num_chans] = 0.0
    var r: MFloat[num_chans] = 0.0
    var s: MFloat[num_chans] = 1.0

    var mask1: MBool[num_chans] = x.lt(-1.0)
    if mask1.reduce_or():
        var l1 = log(1.0 - x)
        var y1 = 1.0 / (1.0 - x)
        var r1 = -pi_sq / 6.0 + l1 * (0.5 * l1 - log(-x))
        y = mask1.select(y1, y)
        r = mask1.select(r1, r)
        s = mask1.select(MFloat[num_chans](1.0), s)

    # Case 2: x == -1
    var mask2: MBool[num_chans] = x.eq(-1.0)
    if mask2.reduce_or():
        r = mask2.select(MFloat[num_chans](-pi_sq / 12.0), r)
        y = mask2.select(MFloat[num_chans](0.0), y)
        s = mask2.select(MFloat[num_chans](0.0), s)  # Will return r directly

    # Case 3: -1 < x < 0
    var mask3: MBool[num_chans] = (x.gt(-1.0)) & (x.lt(0.0))
    if mask3.reduce_or():
        var l3 = log1p(-x)
        var y3 = x / (x - 1.0)
        var r3 = -0.5 * l3 * l3
        y = mask3.select(y3, y)
        r = mask3.select(r3, r)
        s = mask3.select(MFloat[num_chans](-1.0), s)

    # Case 4: x == 0
    var mask4: MBool[num_chans] = x.eq(0.0)
    if mask4.reduce_or():
        r = mask4.select(MFloat[num_chans](0.0), r)
        y = mask4.select(MFloat[num_chans](0.0), y)
        s = mask4.select(MFloat[num_chans](0.0), s)

    # Case 5: 0 < x < 0.5
    var mask5: MBool[num_chans] = (x.gt(0.0)) & (x.lt(0.5))
    if mask5.reduce_or():
        y = mask5.select(x, y)
        r = mask5.select(MFloat[num_chans](0.0), r)
        s = mask5.select(MFloat[num_chans](1.0), s)

    # Case 6: 0.5 <= x < 1
    var mask6: MBool[num_chans] = (x.ge(0.5)) & (x.lt(1.0))
    if mask6.reduce_or():
        var y6 = 1.0 - x
        var r6 = pi_sq / 6.0 - log(x) * log(1.0 - x)
        y = mask6.select(y6, y)
        r = mask6.select(r6, r)
        s = mask6.select(MFloat[num_chans](-1.0), s)

    # Case 7: x == 1
    var mask7: MBool[num_chans] = x.eq(1.0)
    if mask7.reduce_or():
        r = mask7.select(MFloat[num_chans](pi_sq / 6.0), r)
        y = mask7.select(MFloat[num_chans](0.0), y)
        s = mask7.select(MFloat[num_chans](0.0), s)

    # Case 8: 1 < x < 2
    var mask8: MBool[num_chans] = (x.gt(1.0)) & (x.lt(2.0))
    if mask8.reduce_or():
        var l8 = log(x)
        var y8 = 1.0 - 1.0 / x
        var r8 = pi_sq / 6.0 - l8 * (log(1.0 - 1.0 / x) + 0.5 * l8)
        y = mask8.select(y8, y)
        r = mask8.select(r8, r)
        s = mask8.select(MFloat[num_chans](1.0), s)

    # Case 9: x >= 2
    var mask9: MBool[num_chans] = x.ge(2.0)
    if mask9.reduce_or():
        var l9 = log(x)
        var y9 = 1.0 / x
        var r9 = pi_sq / 3.0 - 0.5 * l9 * l9
        y = mask9.select(y9, y)
        r = mask9.select(r9, r)
        s = mask9.select(MFloat[num_chans](-1.0), s)

    # Compute polynomial approximation
    var z = y - 0.25

    var p = horner[num_chans, P](z)
    var q = horner[num_chans, Q](z)

    return r + s * y * p / q

# TODO: add recursion
def select_files(dir: String, extensions: List[String] = [".wav",".aif"]) -> List[String]:
    """Select files with specified extensions from a directory and return their paths as a list of strings.

    Args:
        dir: The directory (as a `String`) to search for files.
        extensions: A list of file extensions to include (as a `List[String]`). They must include the dot (e.g., ".wav").

    Returns:
        A `List[String]` of file paths that match the specified extensions.
    """
    var path_dir = Path(dir)
    var paths: List[String] = List[String]()
    try:
        for f in path_dir.listdir():
            var fp: Path = path_dir.joinpath(String(f))
            if f.suffix() in extensions:
                paths.append(String(fp))
        sort(paths)
        return paths^
    except e:
        abort("select_files: " + String(e))

@always_inline  
def array_to_mfloat[simd_out_size: Int, array: Array[Float64, _], fill_with: Float64 = 0.0]() -> MFloat[simd_out_size]:
    """
    Creates an MFloat vector of size `simd_out_size` from a given array. If the given array is not a power of two the additional vector values will be initialized to 0.
    
    Parameters:
        simd_out_size: The size of the MFloat vector to be returned. Must be a power of two.
        array: The source array. Its length must be less than or equal to simd_out_size.
        fill_with: The value to fill in the remaining elements if array length is less than simd_out_size (default is 0.0).

    Returns:
        An MFloat populated from the input array and padded as needed.
    """
    
    var new_vec = MFloat[simd_out_size](fill_with)
    var materialized_array = materialize[array]()

    for i in range(materialized_array.length):
        new_vec[i] = materialized_array[i]
    return new_vec

def truncate(x: Float64, decimal_places: Int) -> Float64:
    """Truncates a float to a specified number of decimal places.

    Args:
        x: The float value to truncate.
        decimal_places: The number of decimal places to keep.

    Returns:
        The truncated float value.
    """
    var factor = 10.0 ** decimal_places
    return floor(x * factor) / factor

@always_inline
def deg_to_rad(degrees: Float64) -> Float64:
    """
    Converts from degrees to radians.

    Args:
        degrees: An angle in degrees.
    
    Returns:
        The given angle in radians.
    """
    return degrees * (pi/180.)


@always_inline
def rad_to_deg(radians: Float64) -> Float64:
    """
    Converts from radians to degrees.

    Args:
        radians: An angle in radians.
    
    Returns:
        The given angle in degrees.
    """
    return radians * (180/pi)