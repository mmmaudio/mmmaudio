import numpy as np
import math
import random
from typing import overload

def mprint(
    *values: object,
    sep: str | None = " ",
    end: str | None = "\n"
) -> object:
    """print and return the valus(s) passed to the function."""
    print(*values, sep=sep, end=end)
    return values[0] if len(values) == 1 else values

def choose(a: list) -> object:
    """Return a random element from the list a."""
    return random.choice(a)

def wchoose(items: list, weights: list) -> object:
    """
    Return a value from the list based on the list of weights provided.

    Args:
        items: The values to choose from.
        weights: The weights for the values.

    Returns:
        A value from the list.
    """
    if len(items) != len(weights):
            raise ValueError("Items and weights must have the same length.")
    
    max = 0
    selected_item = None

    for item, weight in zip(items, weights):
        if weight <= 0:
            continue

        u = rrand(0.001, 1.0)
        
        # Calculate the Efraimidis-Spirakis sort key: k_i = u_i ** (1 / w_i)
        key = u ** (1.0 / weight)
        if key > max:
            max = key
            selected_item = item

    return selected_item if selected_item is not None else choose(items)

def swap(a: object, b: object) -> tuple:
    """Swap the values of a and b, returning them in a tuple."""
    return b, a

def linlin(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
    """
    Linear-linear transform: map value from input range to output range
    
    Args:
        value: Input value to transform
        in_min: Minimum of input range
        in_max: Maximum of input range
        out_min: Minimum of output range
        out_max: Maximum of output range
    
    Returns:
        Transformed value in output range
    """
    if in_min > in_max:
        in_min, in_max = in_max, in_min
    normalized = (value - in_min) / (in_max - in_min)

    if out_min > out_max:
        out_min, out_max = out_max, out_min
        normalized = 1 - normalized
        
    result = out_min + normalized * (out_max - out_min)
    return clip(result, out_min, out_max)

def dbamp(db: float) -> float:
    """Converts decibel values to amplitude.

    amplitude = 10^(dB/20).

    Args:
        db: The decibel values to convert.

    Returns:
        The corresponding amplitude values.
    """
    return 10.0 ** (db / 20.0)

def ampdb(amp: float) -> float:
    """Converts amplitude values to decibels.

    dB = 20 * log10(amplitude).
    
    Args:
        amp: The amplitude values to convert.

    Returns:
        The corresponding decibel values.
    """
    return 20.0 * math.log10(amp)

def linexp(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
    """
    Linear-to-exponential transform
    
    Args:
        value: Input value to transform
        in_min: Minimum of input range (linear)
        in_max: Maximum of input range (linear)
        out_min: Minimum of output range (exponential)
        out_max: Maximum of output range (exponential)
    
    Returns:
        Exponentially scaled output value
    """
    if out_min <= 0 or out_max <= 0:
        raise ValueError("Output range must be positive for exponential scaling")
    value = clip(value, in_min, in_max)
    if in_min > in_max:
        in_min, in_max = in_max, in_min
    normalized = (value - in_min) / (in_max - in_min)

    flip = out_min > out_max
    if flip:
        out_min, out_max = out_max, out_min

    ratio = out_max / out_min
    result = out_min * (ratio ** normalized)

    if flip:
        result = out_min * out_max / result
    
    return clip(result, out_min, out_max)

def explin(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
    """
    Exponential-to-linear transform (inverse of linexp)
    
    Args:
        value: Input value to transform (exponential scale)
        in_min: Minimum of input range (exponential)
        in_max: Maximum of input range (exponential)
        out_min: Minimum of output range (linear)
        out_max: Maximum of output range (linear)
    
    Returns:
        Linearly scaled output value
    """
    
    if in_min <= 0 or in_max <= 0:
        raise ValueError("Input range must be positive for exponential scaling")
    if value <= 0:
        raise ValueError("Value must be positive for exponential-to-linear conversion")
    
    if in_min > in_max:
        in_min, in_max = in_max, in_min

    ratio = in_max / in_min
    normalized = math.log(value / in_min) / math.log(ratio)

    if out_min > out_max:
        out_min, out_max = out_max, out_min
        normalized = 1 - normalized

    result = out_min + normalized * (out_max - out_min)
    return clip(result, out_min, out_max)


def expexp(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
    """
    Exponential-to-exponential transform
    
    Args:
        value: Input value to transform (exponential scale)
        in_min: Minimum of input range (exponential)
        in_max: Maximum of input range (exponential)
        out_min: Minimum of output range (exponential)
        out_max: Maximum of output range (exponential)
    
    Returns:
        Exponentially scaled output value
    """
    
    if in_min <= 0 or in_max <= 0:
        raise ValueError("Input range must be positive")
    if out_min <= 0 or out_max <= 0:
        raise ValueError("Output range must be positive")
    if value <= 0:
        raise ValueError("Value must be positive")
    
    if in_min > in_max:
        in_min, in_max = in_max, in_min

    in_ratio = in_max / in_min
    normalized = math.log(value / in_min) / math.log(in_ratio)
    
    if out_min > out_max:
        out_min, out_max = out_max, out_min
        normalized = 1 - normalized

    out_ratio = out_max / out_min
    result = out_min * (out_ratio ** normalized)
    return clip(result, out_min, out_max)

def lincurve(
    value: float,
    in_min: float,
    in_max: float,
    out_min: float,
    out_max: float,
    curve: float = 0
) -> float:
    """
    Linear-to-curve transform.
    
    Args:
        value: Input value to transform
        in_min: Minimum of input range (linear)
        in_max: Maximum of input range (linear)
        out_min: Minimum of output range
        out_max: Maximum of output range
        curve: Curve parameter (pow(normalized, curve))
               curve = 1: linear
               curve > 1: exponential-like (slow start, steep end)
               curve > 0 and < 1: logarithmic-like (steep start, slow end)
    
    Returns:
        Curved output value
    
    Raises:
        ValueError: If in_min equals in_max
    """

    normalized = clip((value - in_min) / (in_max - in_min), 0.0, 1.0)

    if in_min >= in_max:
        normalized = 1 - normalized
    
    curve = clip(curve, 1e-4, 100)

    if out_max >= out_min:
        curved = np.pow(normalized, curve)
    else:
        curved = np.pow(normalized, 1/curve)
        curved = 1-curved
        out_min, out_max = out_max, out_min

    return clip(float(out_min + curved * (out_max - out_min)), out_min, out_max)    

def midicps(midi_note: float) -> float:
    """Convert MIDI note number to frequency in Hz
    
    Args:
        midi_note: MIDI note number

    Returns:
        Frequency in Hz
    """
    return 440.0 * (2.0 ** ((midi_note - 69.0) / 12.0))

def cpsmidi(frequency: float) -> float:
    """Convert frequency in Hz to MIDI note number
    
    Args:
        frequency: Frequency in Hz

    Returns:
        MIDI note number
    """
    return 69.0 + 12 * math.log2(frequency / 440.0)

@overload
def clip(val: int, min_val: int, max_val: int) -> int: ...
@overload
def clip(val: float, min_val: float, max_val: float) -> float: ...

def clip(val: float, min_val: float, max_val: float) -> float | int:
    """Clip a value to be within a specified range.
    
    Args:
        val: The value to clip.
        min_val: The minimum allowable value.
        max_val: The maximum allowable value.
    
    Returns:
        The clipped value.
    """
    return max(min_val, min(max_val, val))

def fold(value: float, min_val: float, max_val: float) -> float:
    """Fold a value into a specified range.
    
    Args:
        value: The value to fold.
        min_val: The minimum of the range.
        max_val: The maximum of the range.
    
    Returns:
        The folded value within the range [min_val, max_val].
    """
    if min_val > max_val:
        min_val, max_val = max_val, min_val
    range_size = max_val - min_val
    if range_size == 0:
        return min_val
    while value < min_val or value > max_val:
        if value < min_val:
            value = min_val + (min_val - value)
        elif value > max_val:
            value = max_val - (value - max_val)
    return value

def wrap(value: float, min_val: float, max_val: float) -> float:
    """Wrap a value into a specified range.
    
    Args:
        value: The value to wrap.
        min_val: The minimum of the range.
        max_val: The maximum of the range.
    
    Returns:
        The wrapped value within the range [min_val, max_val].
    """
    if min_val > max_val:
        min_val, max_val = max_val, min_val
    range_size = max_val - min_val
    if range_size == 0:
        return min_val
    while value < min_val or value > max_val:
        if value < min_val:
            value += range_size
        elif value > max_val:
            value -= range_size
    return value

def ampdb(amp: float) -> float:
    """Convert amplitude to decibels.
    
    Args:
        amp: Amplitude value.

    Returns:    
        Decibel value.
    """
    if amp <= 0:
        return -float('inf')  # Return negative infinity for zero or negative amplitude
    return 20.0 * math.log10(amp)

def dbamp(db: float) -> float:
    """Converts decibel values to amplitude.

    amplitude = 10^(dB/20).

    Args:
        db: The decibel values to convert.

    Returns:
        The corresponding amplitude values.
    """
    return 10.0 ** (db / 20.0)

def power_to_db(value: float, zero_db_ref: float = 1.0, amin: float = 1e-10) -> float:
    """Convert a power value to decibels.

    This mirrors librosa's power_to_db behavior for a single scalar: 10 * log10(max(amin, value) / zero_db_ref).

    Args:
        value: Power value to convert.
        zero_db_ref: Reference power for 0 dB.
        amin: Minimum value to avoid log of zero.

    Returns:
        The value in decibels.
    """
    return 10.0 * math.log10(max(value, amin) / zero_db_ref)

def polar_to_complex(mags: np.ndarray, phases: np.ndarray) -> np.ndarray:
    """
    Convert polar coordinates (magnitude and phase) to complex numbers.
    
    Args:
        mags: Magnitude spectrum (numpy array)
        phases: Phase spectrum (numpy array)
    
    Returns:
        complex_signal: Complex representation (numpy array)
    """
    complex_signal = mags * np.exp(1j * phases)
    return complex_signal

@overload
def rrand(min_val: float, max_val: float) -> float: ...
@overload
def rrand(min_val: int, max_val: int) -> int: ...

def rrand(min_val: float, max_val: float) -> float | int:
    """Generate a random value between min_val and max_val. Will return an int if both min_val and max_val are ints, otherwise returns a float.
    
    Args:
        min_val: Minimum value.
        max_val: Maximum value.
    Returns:
        Random value between min_val and max_val.
    """
    if isinstance(min_val, int) and isinstance(max_val, int):
        return random.randint(min_val, max_val)
    return random.uniform(min_val, max_val)

@overload
def exprand(min_val: float, max_val: float) -> float: ...
@overload
def exprand(min_val: int, max_val: int) -> int: ...
def exprand(min_val: float, max_val: float) -> float | int:
    """Generate a random value from an exponential distribution with given range. Will return an int if both min_val and max_val are ints, otherwise returns a float.
    
    Args:
        min_val: Minimum value.
        max_val: Maximum value.

    """
    if isinstance(min_val, int) and isinstance(max_val, int):
        return int(linexp(random.uniform(0.0, 1.0), 0.0, 1.0, min_val, max_val))
    return linexp(random.uniform(0.0, 1.0), 0.0, 1.0, min_val, max_val)

def coin(p: float) -> bool:
    """Return True with probability p, False otherwise.
    
    Args:
        p: Probability of returning True (between 0 and 1).
    
    Returns:
        True with probability p, False otherwise.
    """
    p = clip(p, 0.0, 1.0) 
    return random.random() < p

def raw_midi_to_list(message: list[int]) -> list[int]:
    """Convert a raw MIDI message to a list of integers.

    Args:
        message: The raw MIDI message as a list of integers.

    Returns:
        The raw MIDI message as a list of integers.
    """
    if len(message) < 2 or message[0] < 0x80 or message[0] >= 0xF0:
        return [0,0,0]
    kind = message[0] & 0xF0
    channel = (message[0] & 0x0F) + 1
    return [channel, message[1], message[2]]