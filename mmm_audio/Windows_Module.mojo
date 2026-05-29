from mmm_audio import *
from std.math import exp, sin, sqrt, cos, pi

struct Windows(Movable, Copyable):
    """Stores various window functions used in audio processing. This struct precomputes several common window types."""
    var hann: List[Float64]
    var hamming: List[Float64]
    var blackman: List[Float64]
    var sine: List[Float64]
    var kaiser: List[Float64]
    var pan2: List[MFloat[2]]
    comptime size: Int = 2048
    comptime size_f64: Float64 = 2048.0
    comptime mask: Int = 2047 # yep, gotta make sure this is size - 1

    def __init__(out self):
        self.hann = hann_window(self.size)
        self.hamming = hamming_window(self.size)
        self.blackman = blackman_window(self.size)
        self.sine = sine_window(self.size)
        self.kaiser = kaiser_window(self.size, 5.0)
        self.pan2 = pan2_window(256)

    def at_phase[window_type: Int,interp: Interp = Interp.none](self, world: World, phase: Float64, prev_phase: Float64 = 0.0) -> Float64:
        """Get window value at given phase (0.0 to 1.0) for specified window type."""

        comptime if window_type == WindowType.hann:
            return SpanInterpolator.read[1,interp,True,self.mask](world,self.hann, phase * self.size_f64, prev_phase * self.size_f64)
        elif window_type == WindowType.hamming:
            return SpanInterpolator.read[1,interp,True,self.mask](world,self.hamming, phase * self.size_f64, prev_phase * self.size_f64)
        elif window_type == WindowType.blackman:
            return SpanInterpolator.read[1,interp,True,self.mask](world,self.blackman, phase * self.size_f64, prev_phase * self.size_f64)
        elif window_type == WindowType.kaiser:
            return SpanInterpolator.read[1,interp,True,self.mask](world,self.kaiser, phase * self.size_f64, prev_phase * self.size_f64)
        elif window_type == WindowType.sine:
            return SpanInterpolator.read[1,interp,True,self.mask](world,self.sine, phase * self.size_f64, prev_phase * self.size_f64)
        elif window_type == WindowType.rect:
            return 1.0 
        elif window_type == WindowType.tri:
            return 1-2*abs(phase - 0.5)
        else:
            print("Windows.at_phase: Unsupported window type")
            return 0.0

    @staticmethod
    def make_window[window_type: Int](size: Int, beta: Float64 = 5.0) -> List[Float64]:
        """Generate a window of specified type and size.
        
        Parameters:
            window_type: Type of window to generate. Use comptime variables from [WindowType](MMMWorld.md/#struct-windowtype) struct (e.g. WindowType.hann).
        
        Args:
            size: Length of the window.
            beta: Shape parameter only used for Kaiser window. See kaiser_window() for details.
        """
        comptime if window_type == WindowType.rect:
            return rect_window(size)
        elif window_type == WindowType.hann:
            return hann_window(size)
        elif window_type == WindowType.hamming:
            return hamming_window(size)
        elif window_type == WindowType.blackman:
            return blackman_window(size)
        elif window_type == WindowType.sine:
            return sine_window(size)
        elif window_type == WindowType.kaiser:
            return kaiser_window(size, beta)
        elif window_type == WindowType.tri:
            return tri_window(size)
        elif window_type == WindowType.pan2:
            print("Windows.make_window: pan2 window requires MFloat[2] output, use pan2_window() function instead.")
            return List[Float64]()
        else:
            print("Windows.make_window: Unsupported window type")
            return List[Float64]()

def rect_window(size: Int) -> List[Float64]:
    """
    Generate a rectangular window of length size.

    Args:
        size: Length of the window.

    Returns:
        List containing the rectangular window values (all ones).
    """
    var window = List[Float64]()
    for _ in range(size):
        window.append(1.0)
    return window.copy()

def tri_window(size: Int) -> List[Float64]:
    """
    Generate a triangular window of length size.
    Args:
        size: Length of the window.
    Returns:
        List containing the triangular window values.
    """
    var window = List[Float64]()
    for i in range(size):
        var value = 1 - 2 * abs((Float64(i) / Float64(size - 1)) - 0.5)
        window.append(value)
    return window.copy()

def bessel_i0(x: Float64) -> Float64:
    """
    Calculate the modified Bessel function of the first kind, order 0 (I₀). Uses polynomial approximation for accurate results.
    
    Args:
        x: Input value.
    
    Returns:
        I₀(x).
    """
    var abs_x = abs(x)
    
    if abs_x < 3.75:
        # For |x| < 3.75, use polynomial approximation
        var t = (x / 3.75) ** 2
        return 1.0 + 3.5156229 * t + 3.0899424 * (t ** 2) + 1.2067492 * (t ** 3) + \
               0.2659732 * (t ** 4) + 0.0360768 * (t ** 5) + 0.0045813 * (t ** 6)
    else:
        # For |x| >= 3.75, use asymptotic expansion
        var t = 3.75 / abs_x
        var result = (exp(abs_x) / (abs_x ** 0.5)) * \
                    (0.39894228 + 0.01328592 * t + 0.00225319 * (t ** 2) - \
                     0.00157565 * (t ** 3) + 0.00916281 * (t ** 4) - \
                     0.02057706 * (t ** 5) + 0.02635537 * (t ** 6) - \
                     0.01647633 * (t ** 7) + 0.00392377 * (t ** 8))
        return result

def kaiser_window(size: Int, beta: Float64) -> List[Float64]:
    """
    Create a Kaiser window of length n with shape parameter beta.

    - beta = 0: rectangular window.
    - beta = 5: similar to Hamming window.
    - beta = 6: similar to Hanning window.
    - beta = 8.6: similar to Blackman window.
    
    Args:
        size: Length of the window.
        beta: Shape parameter that controls the trade-off between main lobe width and side lobe level. See description for details.
    
    Returns:
        List[Float64] containing the Kaiser window coefficients.
    """
    var window = List[Float64]()

    if size == 1:
        window.append(1.0)
        return window.copy()
    
    # Calculate the normalization factor
    var i0_beta = bessel_i0(beta)
    
    # Generate window coefficients
    for i in range(size):
        # Calculate the argument for the Bessel function
        var alpha = (Float64(size) - 1.0) / 2.0
        var arg = beta * sqrt(1.0 - ((Float64(i) - alpha) / alpha) ** 2)

        # Calculate Kaiser window coefficient
        var coeff = bessel_i0(arg) / i0_beta
        window.append(coeff)

    return window.copy()

def hann_window(size: Int) -> List[Float64]:
    """
    Generate a Hann window of length size.
    
    Args:
        size: Length of the window.
    
    Returns:
        List containing the Hann window values.
    """
    var window = List[Float64]()
    
    for i in range(size):
        var value = 0.5 * (1.0 - cos(2.0 * pi * Float64(i) / Float64(size - 1)))
        window.append(value)
    
    return window.copy()

def hamming_window(size: Int) -> List[Float64]:
    """
    Generate a Hamming window of length size.

    Args:
        size: Length of the window.

    Returns:
        List containing the Hamming window values.
    """
    var window = List[Float64]()
    for i in range(size):
        var value = 0.54 - 0.46 * cos(2.0 * pi * Float64(i) / Float64(size - 1))
        window.append(value)

    return window.copy()

def blackman_window(size: Int) -> List[Float64]:
    """Generate a Blackman window of length size.

    Args:
        size: Length of the window.

    Returns:
        List containing the Blackman window values.
    """
    var window = List[Float64]()
    for i in range(size):
        var value = 0.42 - 0.5 * cos(2.0 * pi * Float64(i) / Float64(size - 1)) + \
                    0.08 * cos(4.0 * pi * Float64(i) / Float64(size - 1))
        window.append(value)
    return window.copy()

def sine_window(size: Int) -> List[Float64]:
    """
    Generate a Sine window of length size.

    Args:
        size: Length of the window.

    Returns:
        List containing the Sine window values.
    """
    var window = List[Float64]()
    for i in range(size):
        var value = sin(pi * Float64(i) / Float64(size - 1))
        window.append(value)
    return window.copy()

# Create a compile-time function to generate values
def pan2_window(size: Int) -> List[MFloat[2]]:
    """
    Generate a MFloat[2] quarter cosine window for panning. The first element of the SIMD vector is the multiplier for the left channel, and the second element is for the right channel. This allows any sample to be panned at one of `size` positions between left and right channels smoothly.
    
    Args:
        size: Length of the window.

    Returns:
        List containing the quarter cosine window values.
    """
    var table = List[MFloat[2]]()

    for i in range(size):
        var angle = (pi / 2.0) * Float64(i) / Float64(size-1)
        table.append(cos(MFloat[2](angle, (pi / 2.0) - angle)))
    return table^