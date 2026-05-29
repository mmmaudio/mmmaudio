from mmm_audio import *
from std.math import sin, log2, ceil, floor
from std.sys import simd_width_of
from std.pathlib import Path


struct SIMDBuffer[num_chans: Int = 2](Movable, Copyable):
    """A multi-channel audio buffer for storing audio data.

    Audio data is stored in the `data` variable as a `List[MFloat[Self.num_chans]]` where each `MFloat[Self.num_chans]` represents a single frame of audio data for all channels. For example, if `num_chans` is 2, each element of `data` would be an `MFloat[2]` where the first element is the sample value for the left channel and the second element is the sample value for the right channel.
    """
    var data: List[MFloat[Self.num_chans]]
    var num_frames: Int
    var num_frames_f64: Float64
    var sample_rate: Float64
    var duration: Float64

    def __init__(out self, data: List[MFloat[Self.num_chans]], sample_rate: Float64):
        """Initialize a SIMDBuffer with the given audio data and sample rate.

        Args:
            data: A `List` of `List`s of `Float64` representing the audio data for each channel.
            sample_rate: The sample rate of the audio data.
        """

        if len(data) > 1:
            for chan in range(1,len(data)):
                if len(data[chan]) != len(data[0]):
                    print("SIMDBuffer::__init__ All channels must have the same number of frames")

        self.data = data.copy()
        self.sample_rate = sample_rate

        self.num_frames = len(data) if self.num_chans > 0 else 0
        self.num_frames_f64 = Float64(self.num_frames)
        self.duration = self.num_frames_f64 / self.sample_rate

    @staticmethod
    def zeros(num_frames: Int, sample_rate: Float64 = 48000.0) -> SIMDBuffer[Self.num_chans]:
        """Initialize a SIMDBuffer with zeros.

        Args:
            num_frames: Number of frames in the buffer.
            sample_rate: Sample rate of the buffer.
        """

        var data = [MFloat[Self.num_chans](0.0) for _ in range(num_frames)]

        return SIMDBuffer(data, sample_rate)

    def zero(mut self):
        """Utility function to set all samples in the buffer to zero."""
        for i in range(self.num_frames):
            self.data[i] = MFloat[Self.num_chans](0.0)

    @staticmethod
    def load(file_name: String, num_wavetables: Int = 1, verbose: Bool = False) -> SIMDBuffer[Self.num_chans]:
        """
        Initialize a SIMDBuffer by loading data from a WAV file using SciPy and NumPy.

        Args:
            file_name: Path to the WAV file to load.
            num_wavetables: Number of wavetables per channel. This is only used if the sound file being loaded contains multiple wavetables concatenated in a single channel.
            verbose: Whether to print verbose output.
        """
        if file_name != "":
            try:
                header = read_wav_header(file_name)
                if verbose:
                    print("Loading file into SIMDBuffer: ", file_name)
                    print_wav_info(header)

                data = read_wav_SIMDs[Self.num_chans](file_name, header, num_wavetables)
                
                return SIMDBuffer(data^, MFloat[](header.sample_rate))
                
            except err:
                print("SIMDBuffer::__init__ Error loading file: ", file_name, " Error: ", err)
                return SIMDBuffer[Self.num_chans].zeros(0,48000.0)
        else:
            print("SIMDBuffer::__init__ No file_name provided")
            return SIMDBuffer[Self.num_chans].zeros(0,48000.0)

    @doc_hidden
    def do_the_write(self, file_name: String, num_samps: Int = -1):
        if num_samps < 0 or num_samps > self.num_frames:
            try:
                write_wav_file(file_name, self.data, Int(self.sample_rate))
            except err:
                print("SIMDBuffer::write_file Error writing file: ", file_name, " Error: ", err)
        else:
            try:
                write_wav_file(file_name, self.data[0:num_samps], Int(self.sample_rate))
            except err:
                print("SIMDBuffer::write_file Error writing file: ", file_name, " Error: ", err)

    def write_to_file(self, file_name: String, num_samps: Int = -1, verbose: Bool = False):
        """Write the SIMDBuffer to a WAV file.

        Args:
            file_name: Path to the WAV file to write to.
            num_samps: Number of samples to write.
            verbose: Whether to print confirmation of written file.
        """
        self.do_the_write(file_name, num_samps)
        if verbose:
            print("SIMDBuffer written to file: ", file_name)

    # this is untested
    def write_circular_buf_to_file(mut self, write_head: Int, file_name: String, num_samps: Int = -1, rotate_back: Bool = False, verbose: Bool = False):
        """Write the SIMDBuffer to a WAV file in a circular manner, starting from the current write head position.

        Args:
            write_head: The current write head position in the buffer. This is the index of the most recently written sample.
            file_name: Path to the WAV file to write to.
            num_samps: Number of samples to write. If -1, the entire buffer will be written.
            rotate_back: Whether to rotate the buffer back to its original order after writing.
            verbose: Whether to print confirmation of written file.
        """

        rotate_left_inplace(self.data, write_head)
        self.do_the_write(file_name, num_samps)
        if verbose:
            print("SIMDBuffer circularly written to file: ", file_name)

        if rotate_back:
            rotate_left_inplace(self.data, len(self.data) - write_head)

    def get_num_chans(self) -> Int:
        """Get the number of channels in the SIMDBuffer."""
        return Self.num_chans


struct Buffer(Movable, Copyable):
    """A multi-channel audio buffer for storing audio data.

    Audio data is stored in the `data` variable as a `List[List[Float64]]`, where each inner `List` represents a channel of audio samples.
    """
    var data: List[List[Float64]]
    var num_chans: Int 
    var num_frames: Int
    var num_frames_f64: Float64
    var sample_rate: Float64
    var duration: Float64

    def __init__(out self, data: List[List[Float64]], sample_rate: Float64):
        """Initialize a Buffer with the given audio data and sample rate.

        Args:
            data: A `List` of `List`s of `Float64` representing the audio data for each channel.
            sample_rate: The sample rate of the audio data.
        """

        if len(data) > 1:
            for chan in range(1,len(data)):
                if len(data[chan]) != len(data[0]):
                    print("Buffer::__init__ All channels must have the same number of frames")

        self.data = data.copy()
        self.sample_rate = sample_rate

        self.num_chans = len(data)
        self.num_frames = len(data[0]) if self.num_chans > 0 else 0
        self.num_frames_f64 = Float64(self.num_frames)
        self.duration = self.num_frames_f64 / self.sample_rate

    @staticmethod
    def zeros(num_frames: Int, num_chans: Int = 1, sample_rate: Float64 = 48000.0) -> Buffer:
        """Initialize a Buffer with zeros.

        Args:
            num_frames: Number of frames in the buffer.
            num_chans: Number of channels in the buffer.
            sample_rate: Sample rate of the buffer.
        """

        var data = List[List[Float64]]()
        for _ in range(num_chans):
            channel_data = List[Float64]()
            for _ in range(num_frames):
                channel_data.append(0.0)
            data.append(channel_data^)

        return Buffer(data, sample_rate)

    def zero(mut self):
        """Utility function to set all samples in the buffer to zero."""
        for chan in range(self.num_chans):
            for i in range(self.num_frames):
                self.data[chan][i] = 0.0

    @staticmethod
    def load(file_name: String, num_wavetables: Int = 1, verbose: Bool = False) -> Buffer:
        """
        Initialize a Buffer by loading data from a WAV file using SciPy and NumPy.

        Args:
            file_name: Path to the WAV file to load.
            num_wavetables: Number of wavetables per channel. This is only used if the sound file being loaded contains multiple wavetables concatenated in a single channel.
            verbose: Whether to print verbose output.
        """

        if file_name != "":
            # Load the file if a file_name is provided
            try:
                header = read_wav_header(file_name)
                if verbose:
                    print("Loading file into Buffer: ", file_name)
                    print_wav_info(header)

                data = read_wav_samples(file_name, header, num_wavetables)
                
                return Buffer(data^, MFloat[](header.sample_rate))
                
            except err:
                print("Buffer::__init__ Error loading file: ", file_name, " Error: ", err)
                return Buffer.zeros(0,0,48000.0)
        else:
            print("Buffer::__init__ No file_name provided")
            return Buffer.zeros(0,0,48000.0)



struct SpanInterpolator(Movable, Copyable):
    """
    A collection of static methods for interpolating values from a `List[Float64]` or `InlineArray[Float64]`.
    
    `SpanInterpolator` supports various interpolation methods including
    
    * no interpolation (none)
    * linear interpolation
    * quadratic interpolation
    * cubic interpolation
    * lagrange interpolation (4th order)
    * sinc interpolation

    The available interpolation methods are defined in the struct [Interp](MMMWorld.md#struct-interp).
    """

    @always_inline
    @staticmethod
    def idx_in_range[num_chans: Int = 1](data: Span[MFloat[num_chans], ...], idx: Int) -> Bool:
        return idx >= 0 and idx < len(data)

    # Once structs are allowed to have static variables, the since table will be stored in here so that 
    # a reference to the MMMWorld is not needed for every read call.
    @always_inline
    @staticmethod
    def read[num_chans: Int = 1, interp: Interp = Interp.none, bWrap: Bool = True, mask: Int = 0](world: World, data: Span[MFloat[num_chans], ...], f_idx: Float64, prev_f_idx: Float64 = 0.0) -> MFloat[num_chans]:
        """Read a value from a Span[MFloat[num_chans], ...] using provided index and interpolation method, which is determined at compile time.
        
        Parameters:
            num_chans: Number of channels in the data.
            interp: Interpolation method to use (from [Interp](MMMWorld.md#struct-interp) enum).
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            world: Pointer to the MMMWorld instance.
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
            prev_f_idx: The previous floating-point index (used for [SincInterpolation](SincInterpolator.md)).
        """
        
        comptime if interp == Interp.none:
            return SpanInterpolator.read_none[num_chans,bWrap,mask](data, f_idx)
        elif interp == Interp.linear:
            return SpanInterpolator.read_linear[num_chans,bWrap,mask](data, f_idx)
        elif interp == Interp.quad:
            return SpanInterpolator.read_quad[num_chans,bWrap,mask](data, f_idx)
        elif interp == Interp.cubic:
            return SpanInterpolator.read_cubic[num_chans,bWrap,mask](data, f_idx)
        elif interp == Interp.lagrange4:
            return SpanInterpolator.read_lagrange4[num_chans,bWrap,mask](data, f_idx)
        elif interp == Interp.sinc:
            return SpanInterpolator.read_sinc[num_chans,bWrap,mask](world,data, f_idx, prev_f_idx)
        else:
            print("SpanInterpolator def read:: Unsupported interpolation method")
            return 0.0

    @always_inline
    @staticmethod
    def read_none[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with no interpolation.
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
        """

        idx = Int(f_idx)
        return SpanInterpolator.read_none[num_chans,bWrap,mask](data, idx)
    
    @always_inline
    @staticmethod
    def read_none[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], idx: Int) -> MFloat[num_chans]:
        idx2 = idx
        comptime if bWrap:
            comptime if mask != 0:
                idx2 = idx2 & mask
            else:
                idx2 = idx2 % len(data)
            return data[idx2]
        else:
            return data[idx2] if SpanInterpolator.idx_in_range(data,idx2) else 0.0

    @always_inline
    @staticmethod
    def read_linear[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with linear interpolation.
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
        """
        idx0: Int = Int(f_idx)
        idx1: Int = idx0 + 1
        frac: Float64 = f_idx - Float64(idx0)
        comptime if bWrap:
            comptime if mask != 0:
                idx0 = idx0 & mask
                idx1 = idx1 & mask
            else:
                length = len(data)
                idx0 = idx0 % length
                idx1 = idx1 % length
            
            y0 = data[idx0]
            y1 = data[idx1]

        else:
            # not wrapping
            y0 = data[idx0] if SpanInterpolator.idx_in_range(data, idx0) else 0.0
            y1 = data[idx1] if SpanInterpolator.idx_in_range(data, idx1) else 0.0

        return linear_interp(y0,y1,frac)

    @always_inline
    @staticmethod
    def read_quad[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with quadratic interpolation.
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
        """

        idx0 = Int(f_idx)
        idx1 = idx0 + 1
        idx2 = idx0 + 2
        frac: Float64 = f_idx - Float64(idx0)

        comptime if bWrap:
            comptime if mask != 0:
                idx0 = idx0 & mask
                idx1 = idx1 & mask
                idx2 = idx2 & mask
            else:
                length = len(data)
                idx0 = idx0 % length
                idx1 = idx1 % length
                idx2 = idx2 % length

            y0 = data[idx0]
            y1 = data[idx1]
            y2 = data[idx2]

            return quadratic_interp(y0, y1, y2, frac)
        else:
            y0 = data[idx0] if SpanInterpolator.idx_in_range(data, idx0) else 0.0
            y1 = data[idx1] if SpanInterpolator.idx_in_range(data, idx1) else 0.0
            y2 = data[idx2] if SpanInterpolator.idx_in_range(data, idx2) else 0.0
            return quadratic_interp(y0, y1, y2, frac)

    @always_inline
    @staticmethod
    def read_cubic[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with cubic interpolation.
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used. (only valid for power-of-two lengths).

        Args:
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
        """
        idx1 = Int(f_idx)
        idx0 = idx1 - 1
        idx2 = idx1 + 1
        idx3 = idx1 + 2
        frac: Float64 = f_idx - Float64(idx1)

        comptime if bWrap:
            comptime if mask != 0:
                idx0 = idx0 & mask
                idx1 = idx1 & mask
                idx2 = idx2 & mask
                idx3 = idx3 & mask
            else:
                length = len(data)
                idx0 = idx0 % length
                idx1 = idx1 % length
                idx2 = idx2 % length
                idx3 = idx3 % length

            y0 = data[idx0]
            y1 = data[idx1]
            y2 = data[idx2]
            y3 = data[idx3]
            return cubic_interp(y0, y1, y2, y3, frac)
        else:
            y0 = data[idx0] if SpanInterpolator.idx_in_range(data, idx0) else 0.0
            y1 = data[idx1] if SpanInterpolator.idx_in_range(data, idx1) else 0.0
            y2 = data[idx2] if SpanInterpolator.idx_in_range(data, idx2) else 0.0
            y3 = data[idx3] if SpanInterpolator.idx_in_range(data, idx3) else 0.0
            return cubic_interp(y0, y1, y2, y3, frac)

    @always_inline
    @staticmethod
    def read_lagrange4[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](data: Span[MFloat[num_chans], ...], f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with lagrange4 interpolation.
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
        """
       
        idx0 = Int(f_idx)
        idx1 = idx0 + 1
        idx2 = idx0 + 2
        idx3 = idx0 + 3
        idx4 = idx0 + 4
        frac: Float64 = f_idx - Float64(idx0)

        comptime if bWrap:
            comptime if mask != 0:
                idx0 = idx0 & mask
                idx1 = idx1 & mask
                idx2 = idx2 & mask
                idx3 = idx3 & mask
                idx4 = idx4 & mask
            else:
                length = len(data)
                idx0 = idx0 % length
                idx1 = idx1 % length
                idx2 = idx2 % length
                idx3 = idx3 % length
                idx4 = idx4 % length

            y0 = data[idx0]
            y1 = data[idx1]
            y2 = data[idx2]
            y3 = data[idx3]
            y4 = data[idx4]
            # print(idx0,idx1,idx2,idx3,idx4,y0,y1,y2,y3,y4)
            return lagrange4(y0, y1, y2, y3, y4, frac)
        else:
            y0 = data[idx0] if SpanInterpolator.idx_in_range(data, idx0) else 0.0
            y1 = data[idx1] if SpanInterpolator.idx_in_range(data, idx1) else 0.0
            y2 = data[idx2] if SpanInterpolator.idx_in_range(data, idx2) else 0.0
            y3 = data[idx3] if SpanInterpolator.idx_in_range(data, idx3) else 0.0
            y4 = data[idx4] if SpanInterpolator.idx_in_range(data, idx4) else 0.0
            return lagrange4(y0, y1, y2, y3, y4, frac)

    @always_inline
    @staticmethod
    def read_sinc[num_chans: Int = 1, bWrap: Bool = True, mask: Int = 0](world: World, data: Span[MFloat[num_chans], ...], f_idx: Float64, prev_f_idx: Float64) -> MFloat[num_chans]:
        """Read a value from a `Span[MFloat[num_chans], ...]` using provided index with [SincInterpolation](SincInterpolator.md).
        
        Parameters:
            num_chans: Number of channels in the data.
            bWrap: Whether to wrap indices that go out of bounds.
            mask: Bitmask for wrapping indices (if applicable). If 0, standard modulo wrapping is used. If non-zero, bitwise AND wrapping is used (only valid for power-of-two lengths).

        Args:
            world: Pointer to the MMMWorld instance.
            data: The `Span[MFloat[num_chans], ...]` to read from.
            f_idx: The floating-point index to read at.
            prev_f_idx: The previous floating-point index.
        """
        return world[].sinc_interpolator.sinc_interp[num_chans,bWrap,mask](data, f_idx, prev_f_idx)
