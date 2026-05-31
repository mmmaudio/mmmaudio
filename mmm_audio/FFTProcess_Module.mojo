from mmm_audio import *

@doc_hidden
struct FFTProcessor[T: FFTProcessable, ifft: Bool = True](BufferedProcessable):
    """This is a private struct that the user doesn't *need* to see or use. This is the
    connective tissue between FFTProcess (which the user *does* see and uses to
    create spectral processes) and BufferedProcess. To learn how this whole family of structs 
    works to create spectral processes, see the `FFTProcessable` trait.
    """
    var world: World
    var process: Self.T
    
    var window_size: Int
    var fft: RealFFT[1]
    var fft2: RealFFT[2]

    @doc_hidden
    def __init__(out self, world: World, var process: Self.T, window_size: Int):
        self.world = world
        self.process = process^
        self.window_size = window_size
        self.fft = RealFFT[1](self.window_size)
        self.fft2 = RealFFT[2](self.window_size)

    def next_window(mut self, mut input: List[Float64]) -> None:
        self.fft.fft(input)
        self.process.next_frame(self.fft.mags,self.fft.phases)
        comptime if Self.ifft:
            self.fft.ifft(input)
    
    def next_stereo_window(mut self, mut input: List[SIMD[DType.float64,2]]) -> None:
        self.fft2.fft(input)
        self.process.next_stereo_frame(self.fft2.mags,self.fft2.phases)
        comptime if Self.ifft:
            self.fft2.ifft(input)

    @doc_hidden
    def get_messages(mut self) -> None:
        self.process.get_messages()

trait FFTProcessable(Movable,Copyable, ImplicitlyDestructible):
    """Implement this trait in a custom struct to pass to `FFTProcess`
    as a Parameter.

    See `TestFFTProcess.mojo` for an example on how to create a spectral process 
    using a struct that implements FFTProcessable.
    """
    def next_frame(mut self, mut magnitudes: List[Float64], mut phases: List[Float64]) -> None:
        return None
    def next_stereo_frame(mut self, mut magnitudes: List[SIMD[DType.float64,2]], mut phases: List[SIMD[DType.float64,2]]) -> None:
        return None
    def get_messages(mut self) -> None:
        return None

struct FFTProcess[T: FFTProcessable, ifft: Bool = True,input_window_shape: WindowType = WindowType.hann, output_window_shape: WindowType = WindowType.hann](Movable,Copyable):
    """Create an FFTProcess for audio manipulation in the frequency domain.

    Parameters:
        T: A user defined struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.
        ifft: A boolean specifying whether to perform an IFFT after processing in the frequency domain. Set to `false` if you only want to analyze the magnitudes and phases without converting back to the time domain.
        input_window_shape: Int specifying what window shape to use to modify the amplitude of the input samples before the FFT. See [WindowType](MMMWorld.md/#struct-windowtype) for the options.
        output_window_shape: Int specifying what window shape to use to modify the amplitude of the output samples after the IFFT. See [WindowType](MMMWorld.md/#struct-windowtype) for the options.
    """
    var world: World
    var window_size: Int
    var hop_size: Int
    var buffered_process: BufferedProcess[FFTProcessor[Self.T, Self.ifft], output=Self.ifft, input_window_shape=Self.input_window_shape, output_window_shape=Self.output_window_shape]

    def get_process(mut self) -> ref[self.buffered_process.process.process] Self.T:
        return self.buffered_process.process.process

    def __init__(out self, world: World, var process: Self.T, window_size: Int, hop_size: Int):
        """Initializes a `FFTProcess` struct.

        Args:
            world: A pointer to the MMMWorld.
            process: A user defined struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.
            window_size: The size of the window to use for processing. This will determine how many samples are passed to the user defined struct's `.next_window()` method.
            hop_size: The number of samples between the beginning of FFT windows.

        Returns:
            An initialized `FFTProcess` struct.
        """
        self.world = world
        self.window_size = window_size
        self.hop_size = hop_size
        p = FFTProcessor[Self.T, Self.ifft](self.world, process=process^, window_size=self.window_size)
        self.buffered_process = BufferedProcess[FFTProcessor[Self.T, Self.ifft], output=Self.ifft, input_window_shape=Self.input_window_shape, output_window_shape=Self.output_window_shape](self.world, process=p^,window_size=self.window_size, hop_size=self.hop_size)

    def next(mut self, input: Float64 = 0.0) -> Float64:
        """Processes the next input sample and returns the next output sample.
        
        Args:
            input: The next input sample to process.
        
        Returns:
            The next output sample.
        """
        return self.buffered_process.next(input)

    def next_stereo(mut self, input: MFloat[2]) -> MFloat[2]:
        """Processes the next stereo input sample and returns the next output sample.
        
        Args:
            input: The next input samples to process.
        
        Returns:
            The next output samples.
        """
        return self.buffered_process.next_stereo(input)

    def next_from_buffer(mut self, ref buffer: SIMDBuffer[1], phase: Float64) -> Float64:
        """Returns the next output sample from the internal buffered process. The buffered process reads a block of samples from the provided buffer at the given phase and channel on each hop.

        Args:
            buffer: The input buffer to read samples from.
            phase: The current phase to read from the buffer. Between 0 (beginning) and 1 (end).
        
        Returns:
            The next output sample.
        """
        return self.buffered_process.next_from_buffer(buffer, phase)

    def next_from_stereo_buffer(mut self, ref buffer: SIMDBuffer[2], phase: Float64) -> MFloat[2]:
        """Returns the next stereo output sample from the internal buffered process. The buffered process reads a block of samples from the provided buffer at the given phase and channel on each hop.

        Args:
            buffer: The input buffer to read samples from.
            phase: The current phase to read from the buffer. Between 0 (beginning) and 1 (end).

        Returns:
            The next stereo output sample.
        """
        return self.buffered_process.next_from_stereo_buffer(buffer, phase)

