

from std.memory import bitcast
from std.sys import argv
from std.math import sin
from mmm_audio.constants import MFloat

struct WavHeader(Movable, Copyable):
    """Struct containing WAV file header information."""
    var file_size: Int
    var audio_format: Int
    var num_channels: Int
    var sample_rate: Int
    var byte_rate: Int
    var block_align: Int
    var bits_per_sample: Int
    var data_size: Int
    var data_offset: Int
    var duration_seconds: Float64
    var num_samples: UInt64

    def __init__(out self):
        self.file_size = 0
        self.audio_format = 0
        self.num_channels = 0
        self.sample_rate = 0
        self.byte_rate = 0
        self.block_align = 0
        self.bits_per_sample = 0
        self.data_size = 0
        self.data_offset = 0
        self.duration_seconds = 0.0
        self.num_samples = 0

    @doc_hidden
    def _get_format_name(self) -> String:
        """Return the audio format name based on format code."""
        if self.audio_format == 1:
            return "PCM"
        elif self.audio_format == 3:
            return "IEEE Float"
        elif self.audio_format == 6:
            return "A-law"
        elif self.audio_format == 7:
            return "μ-law"
        elif self.audio_format == 0xFFFE:
            return "Extensible"
        else:
            return "Unknown (" + String(self.audio_format) + ")"

# ============================================================================
# Byte conversion utilities
# ============================================================================

@doc_hidden
def bytes_to_uint16_le(data: List[UInt8], offset: Int) -> UInt16:
    """Convert 2 bytes (little-endian) to UInt16."""
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)

@doc_hidden
def bytes_to_uint32_le(data: List[UInt8], offset: Int) -> UInt32:
    """Convert 4 bytes (little-endian) to UInt32."""
    return (
        UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    )

@doc_hidden
def bytes_to_int16_le(data: List[UInt8], offset: Int) -> Float64:
    """Convert 2 bytes (little-endian) to signed Int16."""
    var bytes = SIMD[DType.uint8, 2](
        data[offset], 
        data[offset + 1]
    )
    
    return Float64(bitcast[DType.int16, 1](bytes))

@doc_hidden
def bytes_to_int24_le(data: List[UInt8], offset: Int) -> Float64:
    """Convert 3 bytes (little-endian) to signed Int32 (24-bit audio)."""
    sign_bit = 255 if data[offset + 2] & 0x80 else 0
    var bytes = SIMD[DType.uint8, 4](
        data[offset], 
        data[offset + 1], 
        data[offset + 2], 
        UInt8(sign_bit)
    )
    
    return Float64(bitcast[DType.int32, 1](bytes))

@doc_hidden
def bytes_to_int32_le(data: List[UInt8], offset: Int) -> Float64:
    """Convert 4 bytes (little-endian) to signed Int32."""
    var bytes = SIMD[DType.uint8, 4](
        data[offset], 
        data[offset + 1], 
        data[offset + 2], 
        data[offset + 3]
    )
    
    # 2. Bitcast the 4-byte vector to a Float32
    # This treats the raw bits as an IEEE 754 float
    return Float64(bitcast[DType.int32, 1](bytes))

@doc_hidden
def bytes_to_float32_le(data: List[UInt8], offset: Int) -> Float64:
    """Reinterprets 4 bytes from a list as a Float32."""
    # 1. Extract 4 bytes into a SIMD vector
    var bytes = SIMD[DType.uint8, 4](
        data[offset], 
        data[offset + 1], 
        data[offset + 2], 
        data[offset + 3]
    )
    
    # 2. Bitcast the 4-byte vector to a Float32
    # This treats the raw bits as an IEEE 754 float
    return Float64(bitcast[DType.float32, 1](bytes))

@doc_hidden
def bytes_to_float64_le(data: List[UInt8], offset: Int) -> Float64:
    var bytes = SIMD[DType.uint8, 8](
        data[offset], 
        data[offset + 1], 
        data[offset + 2], 
        data[offset + 3],
        data[offset + 4],
        data[offset + 5],
        data[offset + 6],
        data[offset + 7]
    )
    
    # 2. Bitcast the 4-byte vector to a Float32
    # This treats the raw bits as an IEEE 754 float
    return bitcast[DType.float64, 1](bytes)

@doc_hidden
def check_bytes_match(data: List[UInt8], offset: Int, expected: String) -> Bool:
    """Check if bytes at offset match expected string."""
    if offset + expected.byte_length() > len(data):
        return False
    for i in range(expected.byte_length()):
        if data[offset + i] != UInt8(ord(expected[byte=i])):
            return False
    return True

@doc_hidden
def find_chunk(data: List[UInt8], start_offset: Int, chunk_id: String) raises -> Tuple[Int, UInt32]:
    """
    Find a chunk in the WAV file data.
    
    Returns:
        Tuple of (data_offset, chunk_size) where data_offset points to chunk data
    """
    var offset = start_offset
    var data_len = len(data)
    
    while offset + 8 <= data_len:
        if check_bytes_match(data, offset, chunk_id):
            var chunk_size = bytes_to_uint32_le(data, offset + 4)
            return (offset + 8, chunk_size)
        
        var chunk_size = bytes_to_uint32_le(data, offset + 4)
        offset += 8 + Int(chunk_size)
        
        # Handle odd chunk sizes (chunks are word-aligned)
        if chunk_size % 2 == 1 and offset < data_len:
            offset += 1
    
    raise Error("Could not find '" + chunk_id + "' chunk")


# ============================================================================
# Sample reading functions
# ============================================================================

def read_8bit_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 8-bit unsigned PCM sample and normalize to [-1.0, 1.0]."""
    var bytes = SIMD[DType.uint8, 1](
        data[offset]
    )
    
    return Float64(bitcast[DType.uint8, 1](bytes))/255.0


def read_16bit_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 16-bit signed PCM sample and normalize to [-1.0, 1.0]."""
    var sample = bytes_to_int16_le(data, offset)
    return Float64(sample) / 32768.0


def read_24bit_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 24-bit signed PCM sample and normalize to [-1.0, 1.0]."""
    var sample = bytes_to_int24_le(data, offset)
    return Float64(sample) / 8388608.0  # 2^23


def read_32bit_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 32-bit signed PCM sample and normalize to [-1.0, 1.0]."""
    var sample = bytes_to_int32_le(data, offset)
    return Float64(sample) / 2147483648.0  # 2^31


def read_float32_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 32-bit float sample (already normalized)."""
    return Float64(bytes_to_float32_le(data, offset))


def read_float64_sample(data: List[UInt8], offset: Int) -> Float64:
    """Read 64-bit float sample (already normalized)."""
    return bytes_to_float64_le(data, offset)


# ============================================================================
# Main WAV reading functions
# ============================================================================

def read_wav_header(file_name: String) raises -> WavHeader:
    """
    Parse WAV header from file data.
    
    Args:
        file_name: Path to the WAV file.
    Returns:
        WavHeader struct containing header information.
    """
    with open(file_name, "r") as f:
        file_data = f.read_bytes(-1)

    var file_len = len(file_data)
    
    if file_len < 44:
        raise Error("File too small to be a valid WAV file")
    
    if not check_bytes_match(file_data, 0, "RIFF"):
        raise Error("Not a valid WAV file: missing RIFF header")
    
    var file_size = bytes_to_uint32_le(file_data, 4)
    
    if not check_bytes_match(file_data, 8, "WAVE"):
        raise Error("Not a valid WAV file: missing WAVE format")
    
    # Find fmt chunk
    var fmt_result = find_chunk(file_data, 12, "fmt ")
    var fmt_offset = fmt_result[0]
    var fmt_size = fmt_result[1]
    
    if fmt_size < 16:
        raise Error("Invalid fmt chunk size")
    
    var header = WavHeader()
    header.file_size = Int(file_size) + 8
    header.audio_format = Int(bytes_to_uint16_le(file_data, fmt_offset))
    header.num_channels = Int(bytes_to_uint16_le(file_data, fmt_offset + 2))
    header.sample_rate = Int(bytes_to_uint32_le(file_data, fmt_offset + 4))
    header.byte_rate = Int(bytes_to_uint32_le(file_data, fmt_offset + 8))
    header.block_align = Int(bytes_to_uint16_le(file_data, fmt_offset + 12))
    header.bits_per_sample = Int(bytes_to_uint16_le(file_data, fmt_offset + 14))
    
    # Find data chunk
    var data_search_start = fmt_offset + Int(fmt_size)
    var data_result = find_chunk(file_data, data_search_start, "data")
    
    header.data_offset = data_result[0]
    header.data_size = Int(data_result[1])
    
    if header.byte_rate > 0:
        header.duration_seconds = Float64(header.data_size) / Float64(header.byte_rate)
    
    if header.block_align > 0:
        header.num_samples = UInt64(header.data_size) // UInt64(header.block_align)

    return header^


def read_wav_samples(file_name: String, header: WavHeader, num_wavetables: Int = 1) raises -> List[List[Float64]]:
    """
    Read all audio samples from WAV file data.
    
    Args:
        file_name: Path to the WAV file.
        header: Parsed WAV header.
        num_wavetables: Number of wavetables per channel. If > 1, splits samples into multiple wavetables of equal size (for large files).
    Returns:
        List of channels, each containing normalized Float64 samples [-1.0, 1.0].
    """
    var file_num_channels = Int(header.num_channels)
    var bits_per_sample = Int(header.bits_per_sample)
    var bytes_per_sample = bits_per_sample // 8
    var num_samples = Int(header.num_samples)
    var audio_format = Int(header.audio_format)
    var data_offset = header.data_offset
    
    with open(file_name, "r") as f:
        file_data = f.read_bytes()
    
    # Validate format
    var is_pcm = audio_format == 1
    var is_float = audio_format == 3
    
    if not is_pcm and not is_float:
        raise Error("Unsupported audio format: " + String(audio_format) + ". Only PCM (1) and IEEE Float (3) are supported.")
    
    # Read samples
    var offset = data_offset
    var samples = List[List[Float64]]()

    if num_wavetables <= 1:
        # Initialize channel lists
        for _ in range(file_num_channels):
            samples.append(List[Float64]())
        for _ in range(num_samples):
            for ch in range(file_num_channels):
                sample_value = get_sample(file_data, offset, bits_per_sample, is_pcm, is_float)
                samples[ch].append(sample_value)
                offset += bytes_per_sample
    else:
        # Initialize channel lists
        for _ in range(num_wavetables):
            samples.append(List[Float64]()) 
        var samples_per_wavetable = num_samples // num_wavetables
        for wavetable_idx in range(num_wavetables):
            for _ in range(samples_per_wavetable):
                sample_value = get_sample(file_data, offset + wavetable_idx * bytes_per_sample, bits_per_sample, is_pcm, is_float)
                offset += bytes_per_sample
                samples[wavetable_idx].append(sample_value)
    
    return samples^

def get_sample(file_data: List[UInt8], offset: Int, bits_per_sample: Int, is_pcm: Bool, is_float: Bool) -> Float64:
    sample_value = 0.0
    if is_pcm:
        # PCM format
        if bits_per_sample == 8:
            sample_value = read_8bit_sample(file_data, offset)
        elif bits_per_sample == 16:
            sample_value = read_16bit_sample(file_data, offset)
        elif bits_per_sample == 24:
            sample_value = read_24bit_sample(file_data, offset)
        elif bits_per_sample == 32:
            sample_value = read_32bit_sample(file_data, offset)
        else:
            return 0.0
    elif is_float:
        # IEEE Float format
        if bits_per_sample == 32:
            sample_value = read_float32_sample(file_data, offset)
        elif bits_per_sample == 64:
            sample_value = read_float64_sample(file_data, offset)
        else:
            return 0.0
    return sample_value

def read_wav_SIMDs[num_channels: Int](file_name: String, header: WavHeader, num_wavetables: Int = 1) raises -> List[MFloat[num_channels]]:
    """
    Read all audio samples from s WAV file and return them as a List of SIMD vectors.
    
    Args:
        file_name: Path to the WAV file.
        header: Parsed WAV header.
        num_wavetables: If > 1, split samples into multiple wavetables of equal size (for large files).
    Returns:
        List of channels, each containing normalized Float64 samples [-1.0, 1.0].
    """
    var filenum_channels = Int(header.num_channels)
    var bits_per_sample = Int(header.bits_per_sample)
    var bytes_per_sample = bits_per_sample // 8
    var num_samples = Int(header.num_samples)
    var audio_format = Int(header.audio_format)
    var data_offset = header.data_offset
    
    # Initialize channel lists
    var samples = List[MFloat[num_channels]]()
    
    # Validate format
    var is_pcm = audio_format == 1
    var is_float = audio_format == 3

    with open(file_name, "r") as f:
        file_data = f.read_bytes()
    
    if not is_pcm and not is_float:
        raise Error("Unsupported audio format: " + String(audio_format) + ". Only PCM (1) and IEEE Float (3) are supported.")
    
    # Read samples
    var offset = data_offset
    if num_wavetables <= 1:
        for _ in range(num_samples):
            SIMD_sample = MFloat[num_channels](0.0)
            read_chans = min(num_channels, filenum_channels)
            for ch in range(read_chans):
                sample_value = get_sample(file_data, offset, bits_per_sample, is_pcm, is_float)
                
                SIMD_sample[ch] = sample_value
                offset += bytes_per_sample
            samples.append(SIMD_sample)
    else:
        # definitely need to check this
        var samples_per_wavetable = num_samples // num_wavetables
        for wavetable_idx in range(num_wavetables):
            for sample_idx in range(samples_per_wavetable):
                if wavetable_idx == 0:
                    SIMD_sample = MFloat[num_channels](0.0)
                    samples.append(SIMD_sample)

                sample_value = get_sample(file_data, offset, bits_per_sample, is_pcm, is_float)
                samples[sample_idx][wavetable_idx] = sample_value
                offset += bytes_per_sample
                

    return samples^



# ============================================================================
# Utility functions
# ============================================================================

def print_wav_info(header: WavHeader):
    """Pretty print WAV header information."""
    print("Format:         ", header._get_format_name())
    print("Channels:       ", header.num_channels)
    print("Sample Rate:    ", header.sample_rate, "Hz")
    print("Bits per Sample:", header.bits_per_sample)
    print("Byte Rate:      ", header.byte_rate, "bytes/sec")
    print("Block Align:    ", header.block_align, "bytes")
    print("Data Size:      ", header.data_size, "bytes")
    print("Data Offset:    ", header.data_offset)
    print("Duration:       ", header.duration_seconds, "seconds")
    print("Total Samples:  ", header.num_samples)
    print("File Size:      ", header.file_size, "bytes")


def print_sample_stats(samples: List[List[Float64]]):
    """Print statistics about the audio samples."""
    var num_channels = len(samples)
    
    for ch in range(num_channels):
        ref channel_samples = samples[ch]
        var num_samples = len(channel_samples)
        
        if num_samples == 0:
            print("Channel", ch, ": No samples")
            continue
        
        var min_val: Float64 = channel_samples[0]
        var max_val: Float64 = channel_samples[0]
        var sum_val: Float64 = 0.0
        var sum_sq: Float64 = 0.0
        
        for i in range(num_samples):
            var sample = channel_samples[i]
            if sample < min_val:
                min_val = sample
            if sample > max_val:
                max_val = sample
            sum_val += sample
            sum_sq += sample * sample
        
        var mean = sum_val / Float64(num_samples)
        var rms = (sum_sq / Float64(num_samples)) ** 0.5
        
        print("Channel", ch, ":")
        print("  Samples:", num_samples)
        print("  Min:    ", min_val)
        print("  Max:    ", max_val)
        print("  Mean:   ", mean)
        print("  RMS:    ", rms)


#####################################

def write_f32(mut data: List[UInt8], value: Float32):
    """Write a Float32 as 4 little-endian bytes."""
    var bits = bitcast[DType.uint32](value)
    data.append(UInt8(bits & 0xFF))
    data.append(UInt8((bits >> 8) & 0xFF))
    data.append(UInt8((bits >> 16) & 0xFF))
    data.append(UInt8((bits >> 24) & 0xFF))

def write_wav_file(file_name: String, samples: Span[mut=False, List[Float64], ...], sample_rate: Int = 44100) raises:
    """Write audio samples to a WAV file."""
    var num_channels = len(samples)
    var num_samples = len(samples[0]) if num_channels > 0 else 0
    
    var data = List[UInt8]()
    write_wav_header(data, num_samples, sample_rate, num_channels)
    
    for i in range(num_samples):
        for ch in range(num_channels):
            var sample_value = samples[ch][i]
            write_f32(data, Float32(sample_value))
    
    with open(file_name, "w") as f:
        f.write_bytes(data)

def write_wav_file[num_channels: Int](file_name: String, samples: Span[mut=False, MFloat[num_channels], ...], sample_rate: Int = 44100) raises:
    """Write audio samples to a WAV file."""
    var num_samples = len(samples)
    
    var data = List[UInt8]()
    write_wav_header(data, num_samples, sample_rate, num_channels)
    
    for i in range(num_samples):
        for ch in range(num_channels):
            var sample_value = samples[i][ch]
            write_f32(data, Float32(sample_value))
    
    with open(file_name, "w") as f:
        f.write_bytes(data)

@doc_hidden
def write_wav_header(
    mut data: List[UInt8],
    num_samples: Int,
    sample_rate: Int = 44100,
    num_channels: Int = 2,
    bits_per_sample: Int = 32
):
    """Write a WAV file header to a byte list. Only writes 32-bit float format."""
    var bytes_per_sample = bits_per_sample // 8
    var block_align = num_channels * bytes_per_sample
    var byte_rate = sample_rate * block_align
    var data_size = num_samples * block_align

    print(num_samples, sample_rate, num_channels, bits_per_sample)
    
    # Helper functions
    def write_str(mut d: List[UInt8], s: String):
        for i in range(s.byte_length()):
            d.append(UInt8(ord(s[byte=i])))
    
    def write_u16(mut d: List[UInt8], val: Int):
        d.append(UInt8(val & 0xFF))
        d.append(UInt8((val >> 8) & 0xFF))
    
    def write_u32(mut d: List[UInt8], val: Int):
        d.append(UInt8(val & 0xFF))
        d.append(UInt8((val >> 8) & 0xFF))
        d.append(UInt8((val >> 16) & 0xFF))
        d.append(UInt8((val >> 24) & 0xFF))
    
    # RIFF header
    write_str(data, "RIFF")
    write_u32(data, 36 + data_size)
    write_str(data, "WAVE")
    
    # fmt chunk
    write_str(data, "fmt ")
    write_u32(data, 16)              # Chunk size
    write_u16(data, 3)               # Audio format (3 = IEEE Float)
    write_u16(data, num_channels)
    write_u32(data, sample_rate)
    write_u32(data, byte_rate)
    write_u16(data, block_align)
    write_u16(data, bits_per_sample)
    
    # data chunk header
    write_str(data, "data")
    write_u32(data, data_size)