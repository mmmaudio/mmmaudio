from mmm_audio import *

struct Recorder[num_chans: Int = 1](Movable, Copyable):
    """
    A struct for storing a buffer and recording audio into it.

    Parameters:
        num_chans: The number of channels in the buffer. Default is 1 (mono).
    """

    var world: World
    var write_head: Int
    var buf: SIMDBuffer[Self.num_chans]

    def __init__(out self, world: World, num_frames: Int, sample_rate: Float64):
        """
        Initialize the Recorder struct.

        Args:
            world: A pointer to the MMMWorld instance.
            num_frames: The number of frames in the empty buffer to be recorded to.
            sample_rate: The sample rate of the empty buffer.
        """
        self.world = world
        self.write_head = 0
        self.buf = SIMDBuffer[Self.num_chans].zeros(num_frames, sample_rate)

    def replace_buffer(mut self, new_buf: SIMDBuffer[Self.num_chans]):
        """
        Replace the internal buffer with a new buffer. The new buffer must have the same number of channels as the existing buffer. Write head is reset to 0.

        Args:
            new_buf: The new buffer to replace the existing buffer with.
        """
        self.buf = new_buf.copy()
        self.write_head = 0

    def zero_buffer(mut self):
        """
        Utility function to set all samples in the buffer to zero. Can be useful to clear the buffer for a new recording without having to create a new Recorder instance.
        """
        self.buf.zero()

    # Write SIMD input to buffer
    def write(mut self, input: MFloat[Self.num_chans], index: Int):
        """
        Write SIMD input to buffer at specified index. Used internally by write_next and write_previous, which will be more appropriate for most use cases.

        Args:
            input: The SIMD input to write to the buffer.
            index: The index in the buffer to write the input to.
        """

        if index >= self.buf.num_frames:
            print("Recorder::write: Index out of bounds:", index)

        self.buf.data[index] = input

    def write_next[loop: Bool = True](mut self, value: MFloat[Self.num_chans]):
        """
        Write SIMD input to buffer at current write head and advance write head forward. This is the correct option in most use cases.

        Parameters:
            loop: Whether to wrap the write head when it reaches the end of the buffer.
        
        Args:
            value: The SIMD input to write to the buffer.
        """
        comptime if loop:
            self.write(value, self.write_head)
            self.write_head = (self.write_head + 1) % self.buf.num_frames
        else:
            if self.write_head < self.buf.num_frames:
                self.write(value, self.write_head)
                self.write_head += 1
    
    def write_previous(mut self, value: MFloat[Self.num_chans]):
        """
        Write SIMD input to buffer at current write head and move write head backward. This is useful for things like delay lines, which write backwards through a buffer so they can interpolate forwards.

        Args:
            value: The SIMD input to write to the buffer.
        """
        self.write(value, self.write_head)
        self.write_head = ((self.write_head - 1) + self.buf.num_frames) % self.buf.num_frames
