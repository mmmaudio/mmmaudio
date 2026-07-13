from mmm_audio import *

@always_inline
def dbamp[width: Int, //](db: MFloat[width]) -> MFloat[width]:
    """Converts decibel values to amplitude.

    amplitude = 10^(dB/20).

    Parameters:
        width: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        db: The decibel values to convert.

    Returns:
        The corresponding amplitude values.
    """
    return 10.0 ** (db / 20.0)

@always_inline
def ampdb[width: Int, //](amp: MFloat[width]) -> MFloat[width]:
    """Converts amplitude values to decibels.

    dB = 20 * log10(amplitude).

    Parameters:
        width: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

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
def select[num_chans: Int](index: Float64, vals: Span[MFloat[num_chans], ...]) -> MFloat[num_chans]:
    """Selects a value from a Span of SIMD vectors based on a floating-point index using linear interpolation.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        index: The floating-point index to select.
        vals: The Span of SIMD vectors containing the values.

    Returns:
        The interpolated value.
    """
    index_int = Int(index) % len(vals)
    index_mix: Float64 = index - Float64(index_int)
    v0 = vals[index_int]
    v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)

@always_inline
def select[num_chans: Int, //](index: Float64, vals: MFloat[num_chans]) -> Float64:
    """Selects a value from a SIMD vector based on a floating-point index and using linear interpolation.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        index: The floating-point index to select.
        vals: The SIMD vector containing the values.
    
    Returns:
        The interpolated value.
    """
    index_int = Int(index) % len(vals)
    index_mix: Float64 = index - Float64(index_int)
    v0 = vals[index_int]
    v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)

@always_inline
def select[num_chans: Int](index: Float64, *vals: MFloat[num_chans]) -> MFloat[num_chans]:
    """Selects a SIMD vector from a List of SIMD vectors based on a floating-point index using linear interpolation.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        index: The floating-point index to select.
        vals: Either a VariadicList or a List of SIMD vectors containing the values.
    
    Returns:
        The interpolated value.
    """
    index_int = Int(index) % len(vals)
    index_mix: Float64 = index - Float64(index_int)
    v0 = vals[index_int]
    v1 = vals[(index_int + 1) % len(vals)]
    return linear_interp(v0, v1, index_mix)


def check_reversed[dtype: DType, num_chans: Int](
    in_min: SIMD[dtype, num_chans],
    in_max: SIMD[dtype, num_chans]
) -> Tuple[SIMD[dtype, num_chans], SIMD[dtype, num_chans], MBool[num_chans]]:
    ins_reversed: MBool[num_chans] = in_min.gt(in_max)
    in_min2 = ins_reversed.select(in_max, in_min)
    in_max2 = ins_reversed.select(in_min, in_max)
    return (in_min2, in_max2, ins_reversed)

@always_inline
def linlin[
    dtype: DType, num_chans: Int, //
](input: SIMD[dtype, num_chans], in_min: SIMD[dtype, num_chans] = 0, in_max: SIMD[dtype, num_chans] = 1, out_min: SIMD[dtype, num_chans] = 0, out_max: SIMD[dtype, num_chans] = 1) -> SIMD[dtype, num_chans]:
    """Maps samples from one range to another range linearly.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

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
    in_min2, in_max2, _ = check_reversed(in_min, in_max)

    normalized = (input - in_min2) / (in_max2 - in_min2)

    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)
 
    result = out_min2 + normalized * (out_max2 - out_min2)
    return clip(result, out_min2, out_max2)

@always_inline
def expexp[num_chans: Int, //](
    input: MFloat[num_chans], 
    in_min: MFloat[num_chans], 
    in_max: MFloat[num_chans], 
    out_min: MFloat[num_chans], 
    out_max: MFloat[num_chans]) -> MFloat[num_chans]:
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
    
    mask = (input.le(0.0)) | (in_min.le(0.0)) | (in_max.le(0.0)) | (out_min.le(0.0)) | (out_max.le(0.0)) | (input.lt(0.0))

    if any(mask):
        print("An expexp value is out of bounds. Retrurning out_min.")
        return out_min
    
    in_min2, in_max2, _ = check_reversed(in_min, in_max)
    input2 = clip(input, in_min2, in_max2)

    # Logarithmic normalization to 0-1 (exp → lin)
    in_ratio = in_max2 / in_min2
    normalized = math.log(input2 / in_min2) / math.log(in_ratio)
    
    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)

    # Exponential mapping to output (lin → exp)
    out_ratio = out_max2 / out_min2
    result = out_min2 * pow(out_ratio, normalized)
    
    return clip(result, out_min2, out_max2)

@always_inline
def linexp[num_chans: Int, //
](input: MFloat[num_chans], in_min: MFloat[num_chans], in_max: MFloat[num_chans], out_min: MFloat[num_chans], out_max: MFloat[num_chans]) -> MFloat[num_chans]:
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
    
    mask = (out_min.le(0.0)) | (out_max.le(0.0))
    if any(mask):
        print("linexp error: out_min and out_max must be greater than 0. Returning input.")
        return input


    in_min2, in_max2, _ = check_reversed(in_min, in_max)
    
    input2 = clip(input, in_min2, in_max2)
    normalized = (input2 - in_min2) / (in_max2 - in_min2)

    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    ratio = out_max2 / out_min2
    result = out_min2 * pow(ratio, normalized)
    
    result = outs_reversed.select(out_min2 * out_max2 / result, result)
    
    return clip(result, out_min2, out_max2)

def explin[num_chans: Int, //](input: MFloat[num_chans], in_min: MFloat[num_chans], in_max: MFloat[num_chans], out_min: MFloat[num_chans], out_max: MFloat[num_chans]) -> MFloat[num_chans]:
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

    mask = (input.le(0.0)) | (in_min.le(0.0)) | (in_max.le(0.0))

    if any(mask):
        print("An explin value is out of bounds. Retrurning input.")
        return input
    
    in_min2, in_max2, _ = check_reversed(in_min, in_max)
    input2 = clip(input, in_min2, in_max2)
    ratio = in_max2 / in_min2
    normalized = math.log(input2 / in_min2) / math.log(ratio)
    
    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    normalized = outs_reversed.select(1 - normalized, normalized)

    # Map to output range
    result = out_min2 + normalized * (out_max2 - out_min2)
    
    return clip(result, out_min2, out_max2)

@always_inline
def lincurve[num_chans: Int, //
](input: MFloat[num_chans], in_min: MFloat[num_chans], in_max: MFloat[num_chans], out_min: MFloat[num_chans], out_max: MFloat[num_chans], curve: MFloat[num_chans]) -> MFloat[num_chans]:
    """Maps a linear input to a curved output range based on a curve parameter.

    Args:
        input: Input value to transform (linear).
        in_min: Minimum of input range (linear).
        in_max: Maximum of input range (linear).
        out_min: Minimum of output range (curved).
        out_max: Maximum of output range (curved).
        curve: Curve parameter (-10 to 10 typical range)
               curve = 0: linear
               curve > 0: exponential curve
               curve < 0: logarithmic curve.
    
    Returns:
        Curved output value.
    """

    
    # Handle near-zero curve (linear case)
    curve_near_zero: MBool[num_chans] = abs(curve).lt(0.001)
    
    in_min2, in_max2, _ = check_reversed(in_min, in_max)
    input2 = clip(input, in_min2, in_max2)
    normalized = (input2 - in_min2) / (in_max2 - in_min2)
    
    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)
    normalized = outs_reversed.select(1.0 - normalized, normalized)

    curve2 = outs_reversed.select(-curve, curve)

    denom = 1.0 - exp(curve2)
    numer = 1.0 - exp(normalized * curve2)
    
    curved = numer / denom
    
    linear_result = normalized
    curved_result = curved
    
    final_normalized = curve_near_zero.select(linear_result, curved_result)
    
    return clip(out_min2 + final_normalized * (out_max2 - out_min2), out_min2, out_max2)

def curvelin[num_chans: Int, //](
    input: MFloat[num_chans],
    in_min: MFloat[num_chans],
    in_max: MFloat[num_chans],
    out_min: MFloat[num_chans],
    out_max: MFloat[num_chans],
    curve: MFloat[num_chans] = 0
) -> MFloat[num_chans]:
    """
    Curve-to-linear transform (inverse of lincurve).
    
    Args:
        input: Input value to transform (from curved space).
        in_min: Minimum of input range (curved).
        in_max: Maximum of input range (curved).
        out_min: Minimum of output range (linear).
        out_max: Maximum of output range (linear).
        curve: Curve parameter (-10 to 10 typical range)
               curve = 0: linear
               curve > 0: undoes exponential curve
               curve < 0: undoes logarithmic curve.
    
    Returns:
        Linearized output value.
    
    """
    
    curve_zero: MBool[num_chans] = curve.eq(0.0)
    temp_curve: MFloat[num_chans] = curve_zero.select(0.0001, curve)

    in_min2, in_max2, _ = check_reversed(in_min, in_max)
    input2 = clip(input, in_min2, in_max2)

    normalized = (input2 - in_min2) / (in_max2 - in_min2)

    out_min2, out_max2, outs_reversed = check_reversed(out_min, out_max)

    grow = pow(MFloat[num_chans](2.71828182845904523536), temp_curve)
    linearized = log(normalized * (grow - 1) + 1) / temp_curve
    linearized = outs_reversed.select(1 - linearized, linearized) 

    answer = out_min2 + linearized * (out_max2 - out_min2)
    return clip(answer, out_min2, out_max2)

def linmap[num_chans: Int](x: MFloat[num_chans], *points: Tuple[MFloat[num_chans], MFloat[num_chans]]) -> MFloat[num_chans]:
    """Linearly maps an input value `x` based on a series of input-output points.

    The function takes a variable number of (input, output) pairs and linearly maps the input `x` to the corresponding output value based on which segment of the input range `x` falls into. If `x` is outside the range of the provided points, it will be clamped to the nearest segment.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        x: The input value to be mapped.
        points: A variable number of (input, output) pairs that define the mapping. For example, `linmap(x, (0, 0), (0.5, 1), (1, 0))` defines a mapping where 0 maps to 0, 0.5 maps to 1, and 1 maps to 0.

    Returns:
        The mapped output value corresponding to the input `x`.
    """
    length = len(points)
    if length < 2:
        return x
    
    # Handle cases where x is outside the range of provided points
    if x <= points[0][0]:
        return points[0][1]
    if x >= points[length-1][0]:
        return points[length-1][1]
    # Find the segment that x falls into
    for i in range(length - 1):
        x0, y0 = points[i]
        x1, y1 = points[i + 1]
        if x0 <= x <= x1:
            # Perform linear interpolation
            return y0 + (y1 - y0) * ((x - x0) / (x1 - x0))
    return points[length - 1][1]

def py_to_float64(py_float: PythonObject) raises -> Float64:
    return Float64(py=py_float)

@always_inline
def clip[
    dtype: DType, num_chans: Int, //
](x: SIMD[dtype, num_chans], lo: SIMD[dtype, num_chans], hi: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """Clips each element in the SIMD vector to the specified range.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

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
    range_size = hi - lo
    if range_size <= 0:
        return x
    wrapped = (x - lo) % range_size + lo
    return wrapped

@always_inline
def wrap[
    dtype: DType, num_chans: Int, //
](input: SIMD[dtype, num_chans], min_val: SIMD[dtype, num_chans], max_val: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """Wraps a sample around a specified range.

    The wrapped sample within the range [min_val, max_val). 
    This function uses modulus arithmetic so the output can never equal max_val.
    Returns the sample if min_val >= max_val.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        input: The sample to wrap.
        min_val: The minimum of the range.
        max_val: The maximum of the range.

    Returns:
        The wrapped value.
    """
    # Check if any min_val >= max_val (vectorized comparison)
    var invalid_range: MBool[num_chans] = min_val.ge(max_val)
    
    var range_size = max_val - min_val
    var wrapped_sample = (input - min_val) % range_size + min_val
    
    # Handle negative modulo results (vectorized)
    var needs_adjustment: MBool[num_chans] = wrapped_sample.lt(min_val)

    wrapped_sample = needs_adjustment.select(wrapped_sample + range_size, wrapped_sample)

    # Return original input where range is invalid, wrapped result otherwise
    return invalid_range.select(input, wrapped_sample)

def fold[dtype: DType, num_chans: Int](x: SIMD[dtype, num_chans], lo: SIMD[dtype, num_chans], hi: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    lo2, hi2, _ = check_reversed(lo, hi)
    range_size = hi2 - lo2
    wrapped = (x - lo2) % (2 * range_size)

    mask = wrapped.lt(range_size)
    folded = mask.select(wrapped, (2 * range_size - wrapped))
    return folded + lo2

@always_inline
def quadratic_interp[
    dtype: DType, num_chans: Int, //
](y0: SIMD[dtype, num_chans], y1: SIMD[dtype, num_chans], y2: SIMD[dtype, num_chans], x: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """Performs quadratic interpolation between three points.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.
    
    Args:
        y0: The sample at position 0.
        y1: The sample at position 1.
        y2: The sample at position 2.
        x: The interpolation position (fractional part between 0 and 1).

    Returns:
        The interpolated sample at position x.
    """
    # Calculate the coefficients of the quadratic polynomial
    xm1 = x - 1.0
    xm2 = x - 2.0

    # Compute Lagrange coefficients for all elements
    coeff0 = (xm1 * xm2) * 0.5
    coeff1 = (x * xm2) * (-1.0)  
    coeff2 = (x * xm1) * 0.5

    # Apply coefficients to y samples and sum
    out = coeff0 * y0 + coeff1 * y1 + coeff2 * y2

    return out

@always_inline
def cubic_interp[
    dtype: DType, num_chans: Int, //
](p0: SIMD[dtype, num_chans], p1: SIMD[dtype, num_chans], p2: SIMD[dtype, num_chans], p3: SIMD[dtype, num_chans], t: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """
    Performs cubic interpolation.

    Cubic Intepolation equation from *The Audio Programming Book* 
    by Richard Boulanger and Victor Lazzarini. pg. 400

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.
    
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
    dtype: DType, num_chans: Int, //
](sample0: SIMD[dtype, num_chans], sample1: SIMD[dtype, num_chans], sample2: SIMD[dtype, num_chans], sample3: SIMD[dtype, num_chans], sample4: SIMD[dtype, num_chans], frac: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """
    Perform Lagrange interpolation for 4th order case (from JOS Faust Model). This is extrapolated from the JOS Faust filter model.

    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

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
    var out: SIMD[dtype, num_chans] = SIMD[dtype, num_chans](0.0)

    var fdm1: SIMD[dtype, num_chans] = SIMD[dtype, num_chans](0.0)
    var fdm2: SIMD[dtype, num_chans] = SIMD[dtype, num_chans](0.0)
    var fdm3: SIMD[dtype, num_chans] = SIMD[dtype, num_chans](0.0)
    var fdm4: SIMD[dtype, num_chans] = SIMD[dtype, num_chans](0.0)

    comptime offsets = SIMD[dtype, 4](1.0, 2.0, 3.0, 4.0)

    comptime for i in range(num_chans):
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

    comptime for i in range(num_chans):
        coeffs: SIMD[dtype, 4] = SIMD[dtype, 4](coeff0[i], coeff1[i], coeff2[i], coeff3[i])

        samples_simd = SIMD[dtype, 4](
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
    dtype: DType, num_chans: Int, //
](p0: SIMD[dtype, num_chans], p1: SIMD[dtype, num_chans], t: SIMD[dtype, num_chans]) -> SIMD[dtype, num_chans]:
    """
    Performs linear interpolation between two points.
    
    Parameters:
        dtype: The data type of the SIMD vector. This parameter is inferred by the values passed to the function.
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        p0: The starting point.
        p1: The ending point.
        t: The interpolation parameter (fractional part between p0 and p1).
    
    Returns:
        The interpolated sample.
    """
    
    return p0 + ((p1 - p0) * t)

@always_inline
def midicps[
    num_chans: Int, //
](midi_note_number: MFloat[num_chans], reference_midi_note: Float64 = 69, reference_frequency: Float64 = 440.0) -> MFloat[num_chans]:
    """Convert MIDI note numbers to frequencies in Hz.

    (cps = "cycles per second")

    Conversion happens based on equating the `reference_midi_note` to the `reference_frequency`.
    For standard tuning, leave the defaults of MIDI note 69 (A4) and 440.0 Hz.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        midi_note_number: The MIDI note number(s) to convert.
        reference_midi_note: The reference MIDI note number.
        reference_frequency: The frequency of the reference MIDI note.
    
    Returns:
        Frequency in Hz.
    """
    
    frequency = Float64(reference_frequency) * 2.0 ** ((midi_note_number - reference_midi_note) / 12.0)
    return frequency


@always_inline
def cpsmidi[
    num_chans: Int, //
](freq: MFloat[num_chans], reference_midi_note: Float64 = 69.0, reference_frequency: Float64 = 440.0) -> MFloat[num_chans]:
    """Convert frequencies in Hz to MIDI note numbers.
    
    (cps = "cycles per second")

    Conversion happens based on equating the `reference_midi_note` to the `reference_frequency`.
    For standard tuning, leave the defaults of MIDI note 69 (A4) and 440.0 Hz.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        freq: The frequency in Hz to convert.
        reference_midi_note: The reference MIDI note number.
        reference_frequency: The frequency of the reference MIDI note.

    Returns:
        The corresponding MIDI note number.
    """

    n = 12.0 * log2(abs(freq) / reference_frequency) + reference_midi_note
    return n

@always_inline
def sanitize[
    num_chans: Int, //
](x: MFloat[num_chans]) -> MFloat[num_chans]:
    """Sanitizes a SIMD float64 vector by zeroing out elements that are too large, too small, or NaN.
    
    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        x: The SIMD float64 vector to sanitize.
    
    Returns:
        The sanitized SIMD float64 vector.
    """

    var absx = abs(x)
    too_large: MBool[num_chans] = absx.gt(MFloat[num_chans](1e15))
    too_small: MBool[num_chans] = absx.lt(MFloat[num_chans](1e-15))
    is_nan: MBool[num_chans] = isnan(x)
    should_zero: MBool[num_chans] = too_large | too_small | is_nan

    return should_zero.select(0.0, x)

def rrand(min: Int, max: Int) -> Int:
    """Generates a random Int from a uniform distribution. Can receive a SIMD Float or an Int, returning the same type.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (inclusive).

    Returns:
        A random Int sample from the specified range.
    """
    return Int(rrand(Float64(min), Float64(max)+0.99999999999999))

def rrand[num_chans: Int = 1](min: MFloat[num_chans], max: MFloat[num_chans]) -> MFloat[num_chans]:
    """Generates a random value from a uniform distribution. Can receive a SIMD Float or an Int, returning the same type.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (inclusive).

    Returns:
        A random Float64 sample from the specified range.
    """
    var u = MFloat[num_chans](0.0)
    comptime for i in range(num_chans):
        u[i] = random_float64(min[i], max[i])
    return u

@always_inline
def exprand[num_chans: Int](min: MFloat[num_chans], max: MFloat[num_chans]) -> MFloat[num_chans]:
    """Generates a random float64 sample from an exponential distribution.

    Parameters:
        num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        min: The minimum sample (inclusive).
        max: The maximum sample (inclusive).

    Returns:
        A random Float64 sample from the specified range.
    """
    var u = MFloat[num_chans](0.0)
    comptime for i in range(num_chans):
        u[i] = random_float64()
    u = linexp(u, 0.0, 1.0, min, max)
    return u

def sign[num_chans:Int,//](x: MFloat[num_chans]) -> MFloat[num_chans]:
    """Returns the sign of x: -1 if negative, 1 if positive, and 0 if zero.
    
    Parameters:
        num_chans: Number of channels in the SIMD vector. This parameter is inferred by the values passed to the function.

    Args:
        x: The input SIMD vector.

    Returns:
        A SIMD vector containing the sign of each element in x.
    """
    pmask:MBool[num_chans] = x.gt(0.0)
    nmask:MBool[num_chans] = x.lt(0.0)

    return pmask.select(MFloat[num_chans](1.0), nmask.select(MFloat[num_chans](-1.0), MFloat[num_chans](0.0)))

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
    result = List[Float64](length=num, fill=0.0)
    if num == 1:
        result[0] = start
        return result^
    
    if endpoint:
        step = (stop - start) / Float64(num - 1)
    else:
        step = (stop - start) / Float64(num)

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

def coin[num_chans:Int](p: MFloat[num_chans]) -> MBool[num_chans]:
    """Return True with probability p, False otherwise.

    Parameters:
        num_chans: Number of channels in the SIMD vector.
    
    Args:
        p: Probability of returning True (between 0 and 1).
    
    Returns:
        True with probability p, False otherwise.
    """
    q = clip(p, 0.0, 1.0) 
    rands = rrand(MFloat[num_chans](0.0), MFloat[num_chans](1.0))
    coins = rands.lt(q)
    return coins

def choose[num_chans:Int](*vals: MFloat[num_chans]) -> MFloat[num_chans]:
    """Choose a random index.

    Parameters:
        num_chans: Number of channels in the SIMD vector.
    
    Args:
        vals: A variable number of items to choose from.
    
    Returns:
        An item chosen randomly from the provided values.
    """
    num_vals = len(vals)
    if num_vals == 0:
        return MFloat[num_chans](0.0)
    idx = rrand(0, num_vals - 1)
    return vals[idx]

@doc_hidden
def _reverse_range[T: Movable & Copyable & ImplicitlyCopyable & ImplicitlyDeletable](mut data: List[T], start: Int, end: Int):
    s = start
    e = end
    while s < e:
        data[s], data[e] = data[e], data[s]
        s += 1
        e -= 1

def rotate_left_inplace[T: Movable & Copyable & ImplicitlyCopyable & ImplicitlyDeletable](mut data: List[T], N: Int):
    """Rotates a list to the left by N positions in-place.

    Parameters:
        T: Element type stored in the list.

    Args:
        data: The list to rotate.
        N: The number of positions to rotate the list by.
    """
    n = N % len(data)
    
    _reverse_range(data, 0, n - 1)      # Reverse first part
    _reverse_range(data, n, len(data) - 1)  # Reverse second part
    _reverse_range(data, 0, len(data) - 1)  # Reverse entire array

def rotate_right_inplace[T: Movable & Copyable & ImplicitlyCopyable & ImplicitlyDeletable](mut data: List[T], N: Int):
    """Rotates a list to the right by N positions in-place.

    Parameters:
        T: Element type stored in the list.

    Args:
        data: The list to rotate.
        N: The number of positions to rotate the list by.
    """
    if len(data) == 0:
        return

    n = len(data) - (N % len(data))
    
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

        in_list_len: Int = len(in_list)

        self.ordinal.resize(in_list_len, 0)

        for i in range(in_list_len):
            self.ordinal[i] = i

        for i in range(N):
            out_list[i] = 0

        def cmp_fn(a: Int, b: Int) capturing -> Bool:
            return in_list[a] > in_list[b]

        # TODO: is it possible to find the peaks and then sort only those?
        # it's not completely necessary to sort the whole list here.
        sort[cmp_fn](self.ordinal)

        valid_peaks: Int = 0
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

    c = p1
    
    a = (p3 - 2.0 * p2 + p1) / 2.0
    b = (p2 - p1) - a
    
    if a == 0.0:
        return (1.0, p2)  # Linear case, return middle point
    
    vertex_x = -b / (2.0 * a)
    vertex_y = a * vertex_x * vertex_x + b * vertex_x + c
    
    return (vertex_x, vertex_y)

def all_lanes_equal[dtype: DType, width: Int](v: SIMD[dtype, width]) -> Bool:
    return (v.eq(v[0])).reduce_and()

@doc_hidden
def horner[num_chans: Int, coeffs: Span[Float64, ...]](z: MFloat[num_chans]) -> MFloat[num_chans]:
    """Evaluate polynomial using Horner's method."""
    var result: MFloat[num_chans] = 0.0
    for i in range(len(coeffs) - 1, -1, -1):
        result = result * z + coeffs[i]
    return result

@doc_hidden
def Li2[num_chans: Int](x: MFloat[num_chans]) -> MFloat[num_chans]:
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
    path_dir = Path(dir)
    paths: List[String] = List[String]()
    try:
        for f in path_dir.listdir():
            fp: Path = path_dir.joinpath(String(f))
            if f.suffix() in extensions:
                paths.append(String(fp))
        sort(paths)
        return paths^
    except e:
        abort("select_files: " + String(e))

@always_inline  
def array_to_mfloat[simd_out_size: Int, array: InlineArray[Float64, _], fill_with: Float64 = 0.0]() -> MFloat[simd_out_size]:
    """
    Creates an MFloat vector of size `simd_out_size` from a given array. If the given array is not a power of two the additional vector values will be initialized to 0.
    
    Parameters:
        simd_out_size: The size of the MFloat vector to be returned. Must be a power of two.
        array: The source array. Its length must be less than or equal to simd_out_size.
        fill_with: The value to fill in the remaining elements if array length is less than simd_out_size (default is 0.0).

    Returns:
        An MFloat populated from the input array and padded as needed.
    """
    
    new_vec = MFloat[simd_out_size](fill_with)
    for i in range(len(array)):
        new_vec[i] = array[i]
    return new_vec