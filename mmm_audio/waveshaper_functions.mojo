"""Table building functions.

Tables to hand the WaveShaper.
"""

from std.math import cos, acos, abs, exp, log
from mmm_audio.Buffer_Module import Buffer
from mmm_audio.functions import clip

def cheby_fill(
    amplitudes: List[Float64],
    size: Int,
    normalize: Bool = True,
    zero_offset: Bool = False,
) -> Buffer:
    var data = List[List[Float64]]()
    data.append(cheby_table(size, amplitudes, normalize, zero_offset))
    return Buffer(data^, 48000.0)

def cheby_fill(
    amplitudes: List[List[Float64]],
    size: Int,
    normalize: Bool = True,
    zero_offset: Bool = False,
) -> Buffer:
    """Fill a Buffer with sums of Chebyshev polynomials of the first kind.

    `amplitudes` holds one list per channel, so the buffer comes back with as
    many channels as there are lists in it, each `size` frames long.

    The buffer keeps its sample rate; everything else about it is replaced.

    Args:
        amplitudes: A list of per-channel amplitude lists. Each inner list
            contains the polynomial amplitudes for one channel. These amplitudes
            control the relative strength of the corresponding harmonics in the resulting waveshaper curve.
        size: Number of frames in the table.
        normalize: Whether to scale each channel to a peak of 1.
        zero_offset: Whether to apply DC corrections for even
            polynomials and normalize the table as a transfer function.

    Returns:
        A Buffer with one channel per amplitude list, each `size` frames long.
    """
    var data = List[List[Float64]]()
    for chan in range(len(amplitudes)):
        data.append(cheby_table(size, amplitudes[chan], normalize, zero_offset))

    return Buffer(data^, 48000.0)


def cheby_table(
    size: Int,
    amplitudes: List[Float64],
    normalize: Bool = True,
    zero_offset: Bool = False,
) -> List[Float64]:
    """Build one channel's worth of summed Chebyshev polynomials.

    Args:
        size: Number of frames in the table.
        amplitudes: One amplitude per polynomial, starting with T1.
        normalize: Whether to scale the result to a peak of 1.
        zero_offset: Whether to apply the DC corrections and normalize the
            table as a transfer function.

    Returns:
        The table, `size` frames long.
    """
    if size < 1:
        return List[Float64]()

    var table = [Float64(0.0) for _ in range(size)]

    # x walks from -1 to 1 across the table. A one frame table has nowhere to
    # walk, so it just gets Tn(-1).
    var step = 2.0 / Float64(size - 1) if size > 1 else 0.0

    for i in range(len(amplitudes)):
        var harmonic = Float64(i + 1)
        var amp = amplitudes[i]
        var x = -1.0
        for j in range(size):
            # min() guards the last frame, where the accumulated steps can put
            # x a hair past 1 and hand acos() a NaN.
            table[j] += cos(harmonic * acos(min(x, 1.0))) * amp
            x += step

        # The even polynomials sit off center, so this follows convention from SuperCollider, where even polynomials are DC corrected to center at 0
        if zero_offset:
            if i % 4 == 1:
                for j in range(size):
                    table[j] += amp
            elif i % 4 == 3:
                for j in range(size):
                    table[j] -= amp

    if normalize:
        if zero_offset:
            normalize_transfer(table)
        else:
            normalize_peak(table)

    return table^

def normalize_peak(mut table: List[Float64]):
    """Scale a table in place so its largest magnitude is 1.

    Args:
        table: The values to scale.
    """
    var peak = 0.0
    for j in range(len(table)):
        peak = max(peak, abs(table[j]))

    if peak != 0.0:
        var scale = 1.0 / peak
        for j in range(len(table)):
            table[j] *= scale


def normalize_transfer(mut table: List[Float64]):
    """Center a table on zero and scale it to a peak of 1, in place.

    Args:
        table: The values to center and scale.
    """
    var size = len(table)
    var half = size >> 1

    var dc = (table[max(0, half - 2)] + table[max(0, half - 1)]) * 0.5

    var peak = 0.0
    for j in range(size):
        peak = max(peak, abs(table[j] - dc))

    if peak != 0.0:
        var scale = 1.0 / peak
        for j in range(size):
            table[j] = (table[j] - dc) * scale


def lockhart_fill(
    size: Int,
    in_range: Float64 = 1.2,
    load_resistance: Float64 = 15.0e3,
    normalize: Bool = True,
) -> Buffer:
    """Fill a single channel Buffer with the Lockhart wavefolder's curve.

    This is the virtual analog model from Esqueda, Pontynen, Valimaki and
    Bilbao, "Virtual Analog Models of the Lockhart and Serge Wavefolders"
    (Applied Sciences 7(12), 2017), Equation 26:

        Vout = L * eta * Vt * W(Delta * exp(L * beta * Vin)) - alpha * Vin

    where L is the sign of Vin, W() is the principal branch of the Lambert W
    function, alpha = 2*RL/R, beta = (2*RL + R)/(eta*Vt*R) and
    Delta = RL*Is/(eta*Vt). The circuit values are the paper's: R = 15k,
    Is = 1e-17 A, eta = 1, Vt = 25.864 mV.

    Args:
        size: Number of frames in the table.
        in_range: Input voltage the ends of the table stand for. Ken Stone's
            circuit bounds its input to about 1.2 V, which is the default.
        load_resistance: RL in ohms, the paper's timbre control, 1k to 50k.
        normalize: Whether to scale the curve to a peak of 1.

    Returns:
        A one channel Buffer holding the transfer function.
    """
    var data = List[List[Float64]]()
    data.append(lockhart_table(size, in_range, load_resistance, normalize))
    return Buffer(data^, 48000.0)


def lockhart_table(
    size: Int,
    in_range: Float64 = 1.2,
    load_resistance: Float64 = 15.0e3,
    normalize: Bool = True,
) -> List[Float64]:
    """Build the curve `lockhart_fill` wraps in a Buffer.

    Args:
        size: Number of frames in the table.
        in_range: Input voltage the ends of the table stand for.
        load_resistance: RL in ohms.
        normalize: Whether to scale the curve to a peak of 1.

    Returns:
        The table, `size` frames long.
    """
    if size < 1:
        return List[Float64]()

    var table = [Float64(0.0) for _ in range(size)]
    var step = 2.0 / Float64(size - 1) if size > 1 else 0.0

    for j in range(size):
        table[j] = lockhart_sample((-1.0 + step * Float64(j)) * in_range, load_resistance)

    if normalize:
        normalize_peak(table)

    return table^


def lockhart_sample(v_in: Float64, load_resistance: Float64 = 15.0e3) -> Float64:
    """Evaluate the Lockhart wavefolder's transfer function at one voltage.

    Equation 26 of the paper, in volts in and volts out:

        Vout = L * eta * Vt * W(Delta * exp(L * beta * Vin)) - alpha * Vin

    Args:
        v_in: Input voltage.
        load_resistance: RL in ohms, the paper's timbre control, 1k to 50k.

    Returns:
        The folded output voltage.
    """
    var r = 15.0e3          # R, ohms
    var i_s = 1.0e-17       # reverse bias saturation current, amps
    var eta = 1.0           # diode ideality factor
    var v_t = 25.864e-3     # thermal voltage, volts

    var r_l = load_resistance
    var alpha = 2.0 * r_l / r
    var beta = (2.0 * r_l + r) / (eta * v_t * r)
    var log_delta = log(r_l * i_s / (eta * v_t))

    var lam = 1.0 if v_in > 0.0 else (-1.0 if v_in < 0.0 else 0.0)

    var w = lambert_w_exp(log_delta + lam * beta * v_in)

    return lam * eta * v_t * w - alpha * v_in


def lockhart_fill4(
    size: Int,
    in_range: Float64 = 1.2,
    load_resistance: Float64 = 15.0e3,
    normalize: Bool = True,
) -> Buffer:
    """Fill a single channel Buffer with four Lockhart wavefolders in series as suggested by the Esqueda et al. paper.

    Args:
        size: Number of frames in the table.
        in_range: Input voltage the ends of the table stand for.
        load_resistance: RL in ohms, the paper's timbre control, 1k to 50k.
        normalize: Whether to scale the finished curve to a peak of 1.

    Returns:
        A one channel Buffer holding the transfer function of the four stages.
    """
    comptime num_stages = 4

    var table = [Float64(0.0) for _ in range(size)]
    var step = 2.0 / Float64(size - 1) if size > 1 else 0.0

    for j in range(size):
        # Each stage hands the next one a voltage, so nothing is normalized
        # until all four have run.
        var v = (-1.0 + step * Float64(j)) * in_range
        for _ in range(num_stages):
            v = lockhart_sample(v, load_resistance)
        table[j] = v

    if normalize:
        normalize_peak(table)

    var data = List[List[Float64]]()
    data.append(table^)
    return Buffer(data^, 48000.0)

def lambert_w_exp(log_x: Float64) -> Float64:
    """The principal branch of the Lambert W function, of `exp(log_x)`.

    Uses the same Halley's method iteration as the Esqueda et al. paper.

    Args:
        log_x: The natural log of the argument. The argument itself is
            positive, so only the upper branch is ever wanted.

    Returns:
        W(exp(log_x)).
    """
    var iters = 12

    if log_x < -600.0:
        return exp(log_x)  # W(x) approaches x as x approaches 0

    if log_x <= 1.0:
        var x = exp(log_x)
        var w = x / (1.0 + x)
        for _ in range(iters):
            var e = exp(w)
            var f = w * e - x
            w -= f / (e * (w + 1.0) - (w + 2.0) * f / (2.0 * w + 2.0))
        return w

    var w = log_x - log(log_x) if log_x > 3.0 else 0.8
    for _ in range(iters):
        w -= (w + log(w) - log_x) / (1.0 + 1.0 / w)
    return w