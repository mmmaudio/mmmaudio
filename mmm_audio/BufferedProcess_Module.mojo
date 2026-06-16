from mmm_audio import *
from std.math import floor

# Eventually, I think it would be better for the user defined BufferProcessable
# struct to be where the `window_size` is set as a parameter and then this value
# can be retrieved
# by the BufferedProcess struct. Mojo currently doesn't allow this traits to have
# parameters. I think `hop_size` would still be a parameter of the BufferedProcess struct.
trait BufferedProcessable(Movable, Copyable, ImplicitlyDestructible):
    """Trait that user structs must implement to be used with a BufferedProcess.
    
    Requires two functions:

    - `next_window(buffer: List[Float64]) -> None`: This function is called when enough samples have been buffered.
      The user can process the input buffer in place meaning that the samples you want to return to the output need
      to replace the samples that you receive in the input list.
    
    - `get_messages() -> None`: This function is called at the top of each audio block to allow the user to retrieve any messages
      they may have sent to this process. Put your [Messenger](Messenger.md) message retrieval code here. (e.g. `self.messenger.update("param_name", self.param)`)
    """
    def next_window(mut self, mut samples: List[Float64]) -> None:
        return None

    def next_stereo_window(mut self, mut samples: List[MFloat[2]]) -> None:
        return None
    
    def get_messages(mut self) -> None:
        return None

struct BufferedProcess[T: BufferedProcessable, output: Bool = True, input_window_shape: WindowType = WindowType.hann, output_window_shape: WindowType = WindowType.hann](Movable, Copyable):
    """Buffers input samples and hands them over to be processed in 'windows'.

    Parameters:
        T: A user defined struct that implements the [BufferedProcessable](BufferedProcess.md/#trait-bufferedprocessable) trait.
        output: A boolean specifying whether this BufferedProcess will be outputting audio. It can be useful to set this to `false` if you only want to analyze the input audio in windows without outputting any audio.
        input_window_shape: Window shape to apply to the input samples before passing them to the user defined struct. Use comptime variables from [WindowType](MMMWorld.md/#struct-windowtype) struct (e.g. WindowType.hann).
        output_window_shape: Window shape to apply to the output samples after processing by the user defined struct. Use comptime variables from [WindowType](MMMWorld.md/#struct-windowtype) struct (e.g. WindowType.hann).
    """
    var world: World
    var window_size: Int
    var hop_size: Int
    var input_buffer: List[Float64]
    var passing_buffer: List[Float64]
    var output_buffer: List[Float64]

    var st_input_buffer: List[SIMD[DType.float64,2]]
    var st_passing_buffer: List[SIMD[DType.float64,2]]
    var st_output_buffer: List[SIMD[DType.float64,2]]

    var last_idx: Float64

    var input_buffer_write_head: Int
    var read_head: Int
    var hop_counter: Int
    var process: Self.T
    var output_buffer_write_head: Int
    var input_attenuation_window: List[Float64]
    var output_attenuation_window: List[Float64]

    def get_process(mut self) -> ref[self.process] Self.T:
        return self.process

    def __init__(out self, world: World, var process: Self.T, window_size: Int, hop_size: Int, hop_start: Int = 0):
        """Initializes a BufferedProcess struct.

        Args:
            world: A pointer to the MMMWorld.
            process: A user defined struct that implements the BufferedProcessable trait.
            window_size: The size of the window to use for processing. This will determine how many samples are passed to the user defined struct's `.next_window()` method at a time, and also determines the size of the internal buffers.
            hop_size: The number of samples between each processed window.
            hop_start: The initial value of the hop counter. Default is 0. This can be used to offset the processing start time, if for example, you need to offset the start time of the first frame. This can be useful when separating windows into separate BufferedProcesses, and therefore separate audio streams, so that each window could be routed or processed with different FX chains.

        Returns:
            An initialized BufferedProcess struct.
        """
        
        self.world = world
        self.window_size = window_size
        self.hop_size = hop_size
        self.input_buffer_write_head = 0
        self.output_buffer_write_head = 0
        self.hop_counter = hop_start
        self.read_head = 0
        self.process = process^
        self.input_buffer = List[Float64](length=self.window_size * 2, fill=0.0)
        self.passing_buffer = List[Float64](length=self.window_size, fill=0.0)
        self.output_buffer = List[Float64](length=self.window_size, fill=0.0)

        self.st_input_buffer = List[SIMD[DType.float64,2]](length=self.window_size * 2, fill=0.0)
        self.st_passing_buffer = List[SIMD[DType.float64,2]](length=self.window_size, fill=0.0)
        self.st_output_buffer = List[SIMD[DType.float64,2]](length=self.window_size, fill=0.0)

        self.last_idx = 0
        
        self.input_attenuation_window = Windows.make_window[Self.input_window_shape](self.window_size)
        self.output_attenuation_window = Windows.make_window[Self.output_window_shape](self.window_size)

    def next(mut self, input: Float64 = 0.0) -> Float64:
        """Process the next input sample and return the next output sample.
        
        This function is called in the audio processing loop for each input sample. It buffers the input samples,
        and internally here calls the user defined struct's `.next_window()` method every `hop_size` samples.

        Args:
            input: The next input sample to process.
        
        Returns:
            The next output sample.
        """
        if self.world[].top_of_block():
            self.process.get_messages()
    
        self.input_buffer[self.input_buffer_write_head] = input
        self.input_buffer[self.input_buffer_write_head + self.window_size] = input
        self.input_buffer_write_head = (self.input_buffer_write_head + 1) % self.window_size
        
        if self.hop_counter == 0:

            for i in range(self.window_size):
                self.passing_buffer[i] = self.input_buffer[self.input_buffer_write_head + i] * self.input_attenuation_window[i]

            self.process.next_window(self.passing_buffer)

            comptime if Self.output:
                for i in range(self.window_size):
                    self.output_buffer[(self.output_buffer_write_head + i) % self.window_size] += self.passing_buffer[i] * self.output_attenuation_window[i]

                self.output_buffer_write_head = (self.output_buffer_write_head + self.hop_size) % self.window_size
    
        self.hop_counter = (self.hop_counter + 1) % self.hop_size

        comptime if not Self.output:
            return 0.0

        outval = self.output_buffer[self.read_head]
        self.output_buffer[self.read_head] = 0.0

        self.read_head = (self.read_head + 1) % self.window_size
        return outval

    def next_stereo(mut self, input: SIMD[DType.float64,2]) -> SIMD[DType.float64,2]:
        """Process the next input sample and return the next output sample.
        
        This function is called in the audio processing loop for each input sample. It buffers the input samples,
        and internally here calls the user defined struct's `.next_window()` method every `hop_size` samples.

        Args:
            input: The next input sample to process.
        
        Returns:
            The next output sample.
        """
        if self.world[].top_of_block():
            self.process.get_messages()

        self.st_input_buffer[self.input_buffer_write_head] = input
        self.st_input_buffer[self.input_buffer_write_head + self.window_size] = input
        self.input_buffer_write_head = (self.input_buffer_write_head + 1) % self.window_size
        
        if self.hop_counter == 0:

            for i in range(self.window_size):
                self.st_passing_buffer[i] = self.st_input_buffer[self.input_buffer_write_head + i] * self.input_attenuation_window[i]

            self.process.next_stereo_window(self.st_passing_buffer)

            comptime if Self.output:
                for i in range(self.window_size):
                    self.st_output_buffer[(self.output_buffer_write_head + i) % self.window_size] += self.st_passing_buffer[i] * self.output_attenuation_window[i]

                self.output_buffer_write_head = (self.output_buffer_write_head + self.hop_size) % self.window_size
    
        self.hop_counter = (self.hop_counter + 1) % self.hop_size

        comptime if not Self.output:
            return 0.0

        outval = self.st_output_buffer[self.read_head]
        self.st_output_buffer[self.read_head] = 0.0

        self.read_head = (self.read_head + 1) % self.window_size
        return outval

    def next_from_buffer[interp: Interp = Interp.none, bWrap: Bool = False](mut self, ref buffer: SIMDBuffer[1], phase: Float64, chan: Int = 0) -> Float64:
        """Used for non-real-time, buffer-based, processing. At the onset of the next window, reads a block of window_size samples from the provided buffer, starting at the given phase and channel. Phase values between zero and one will read samples within the provided buffer. If the provided phase tries to read samples with an index below zero or above the duration of the buffer, zeros will be returned.

        Parameters:
            interp: The interpolation method to use when reading from the buffer. Do not use sinc interpolation.
            bWrap: Whether to wrap around the buffer at the end or to return zeros when the phase tries to read beyond the buffer duration.

        Args:
            buffer: The input buffer to read samples from.
            phase: The current phase to start reading from the buffer.
            chan: The channel to read from the buffer.
        
        Returns:
            The next output sample.
        """

        comptime assert interp != Interp.sinc, "Sinc interpolation is not supported in the `next_from_buffer` method of BufferedProcess. Please use a different interpolation method."
        
        if self.world[].top_of_block():
            self.process.get_messages()

        if self.hop_counter == 0:

            for i in range(self.window_size):
                index = phase * buffer.num_frames_f64 + Float64(i) * buffer.sample_rate / self.world[].sample_rate
                self.passing_buffer[i] = SpanInterpolator.read[interp=interp, bWrap=bWrap](self.world, buffer.data, index, 0.0) * self.input_attenuation_window[i]

            self.process.next_window(self.passing_buffer)

            comptime if Self.output:

                for i in range(self.window_size):
                    self.output_buffer[(self.output_buffer_write_head + i) % self.window_size] += self.passing_buffer[i] * self.output_attenuation_window[i]

                self.output_buffer_write_head = (self.output_buffer_write_head + self.hop_size) % self.window_size
    
        self.hop_counter = (self.hop_counter + 1) % self.hop_size

        if not Self.output:
            return 0.0

        outval = self.output_buffer[self.read_head]
        self.output_buffer[self.read_head] = 0.0
        
        self.read_head = (self.read_head + 1) % self.window_size
        return outval

    def next_from_stereo_buffer[interp: Interp = Interp.none, bWrap: Bool = False](mut self, ref buffer: SIMDBuffer[2], phase: Float64) -> SIMD[DType.float64,2]:
        """Used for non-real-time, buffer-based, processing of stereo files. At the onset of the next window, reads a window_size block of samples from the provided buffer, starting at the given phase and channel. Phase values between zero and one will read samples within the provided buffer. If the provided phase results in reading samples with an index below zero or above the duration of the buffer, zeros will be returned.

        Parameters:
            interp: The interpolation method to use when reading from the buffer. Do not use sinc interpolation.
            bWrap: Whether to wrap around the buffer at the end or to return zeros when the phase tries to read beyond the buffer duration.

        Args:
            buffer: The input buffer to read samples from.
            phase: The current phase to read from the buffer.

        Returns:
            The next output sample.
        """
        
        if self.world[].top_of_block():
            self.process.get_messages()
            
        if self.hop_counter == 0:
           
            for i in range(self.window_size):
                index = (phase * buffer.num_frames_f64) + Float64(i)
                self.st_passing_buffer[i] = SpanInterpolator.read[interp=interp, bWrap=bWrap](self.world, buffer.data, index, 0.0) * self.input_attenuation_window[i]

            self.process.next_stereo_window(self.st_passing_buffer)

            comptime if Self.output:
               
                for i in range(self.window_size):
                    self.st_output_buffer[(self.output_buffer_write_head + i) % self.window_size] += self.st_passing_buffer[i] * self.output_attenuation_window[i]
                self.output_buffer_write_head = (self.output_buffer_write_head + self.hop_size) % self.window_size
    
        self.hop_counter = (self.hop_counter + 1) % self.hop_size

        if not Self.output:
            return 0.0

        outval = self.st_output_buffer[self.read_head]
        self.st_output_buffer[self.read_head] = 0.0

        self.read_head = (self.read_head + 1) % self.window_size
        return outval

