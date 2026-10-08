from std.os.path import exists

@fieldwise_init
struct TensorInfo(Copyable, Movable):
    """Where one tensor lives in a safetensors file, and how it is stored."""

    var dtype: String
    """The safetensors dtype name, such as "F32" or "BF16"."""
    var shape: List[Int]
    """The tensor's dimensions, outermost first."""
    var start: Int
    """Offset of the first byte of the tensor's data in the file."""
    var end: Int
    """Offset one past the last byte of the tensor's data in the file."""

    def num_elements(self) -> Int:
        """Number of elements in the tensor.

        Returns:
            The product of the dimensions in `shape` (1 for a scalar).
        """
        var n = 1
        for d in self.shape:
            n *= d
        return n

struct SafeTensors(Movable):
    """Reads a [safetensors](https://huggingface.co/docs/safetensors) file, the format MMMAudio saves its trainings in.

    The whole file is read into memory when the struct is made. A safetensors file is an
    8 byte little endian header length, a JSON header that gives each tensor's dtype,
    shape and byte range, and then the raw little endian tensor data. The header can also
    carry a `__metadata__` object of string key/value pairs.

    ```
    var st = SafeTensors("training.safetensors")
    var weight = st.get[DType.float32]("layers.0.weight")
    var shape = st.shape("layers.0.weight")
    var format = st.metadata("format")
    ```

    Supported dtypes are F64, F32, F16, BF16, I64, I32, I16, I8, U8 and BOOL. `get`
    converts from whichever of these the tensor is stored as.
    """

    var data: List[UInt8]
    var tensors: Dict[String, TensorInfo]
    var metadata_dict: Dict[String, String]

    def __init__(out self, path: String) raises:
        """Read and parse a safetensors file.

        Args:
            path: Path to the `.safetensors` file.

        Raises:
            Error: If the file is missing or is not a valid safetensors file.
        """
        if not exists(path):
            raise Error("safetensors file not found: " + path)
        with open(path, "r") as f:
            self.data = f.read_bytes()
        self.tensors = Dict[String, TensorInfo]()
        self.metadata_dict = Dict[String, String]()

        if len(self.data) < 8:
            raise Error("not a safetensors file (too short): " + path)
        var header_size = Int(self.data.unsafe_ptr().unsafe_bitcast[UInt64]().unsafe_load[alignment=1]())
        var data_start = 8 + header_size
        if header_size <= 0 or data_start > len(self.data):
            raise Error("not a safetensors file (bad header size): " + path)

        var tensors = Dict[String, TensorInfo]()
        var metadata = Dict[String, String]()
        _parse_header(Span(self.data)[8:data_start], data_start, tensors, metadata)
        for entry in tensors.items():
            ref info = entry.value
            if info.start > info.end or info.end > len(self.data):
                raise Error("tensor '" + entry.key + "' points outside the file: " + path)
            if info.end - info.start != info.num_elements() * _dtype_size(info.dtype):
                raise Error("tensor '" + entry.key + "' has the wrong number of bytes for its shape: " + path)
        self.tensors = tensors^
        self.metadata_dict = metadata^

    def __contains__(self, name: String) -> Bool:
        """Whether the file has a tensor called `name`.

        Args:
            name: The tensor name.

        Returns:
            True if the tensor exists.
        """
        return name in self.tensors

    def names(self) -> List[String]:
        """The names of all the tensors in the file.

        Returns:
            The tensor names, in no particular order.
        """
        var result = List[String]()
        for name in self.tensors:
            result.append(name)
        return result^

    def info(self, name: String) raises -> TensorInfo:
        """The dtype, shape and location of a tensor.

        Args:
            name: The tensor name.

        Returns:
            The tensor's `TensorInfo`.

        Raises:
            Error: If there is no tensor called `name`.
        """
        if name not in self.tensors:
            raise Error("no tensor called '" + name + "' in safetensors file")
        return self.tensors[name].copy()

    def shape(self, name: String) raises -> List[Int]:
        """The dimensions of a tensor.

        Args:
            name: The tensor name.

        Returns:
            The tensor's shape, outermost dimension first.

        Raises:
            Error: If there is no tensor called `name`.
        """
        return self.info(name).shape.copy()

    def has_metadata(self, key: String) -> Bool:
        """Whether the file's `__metadata__` has `key`.

        Args:
            key: The metadata key.

        Returns:
            True if the key exists.
        """
        return key in self.metadata_dict

    def metadata(self, key: String) raises -> String:
        """A value from the file's `__metadata__`.

        Args:
            key: The metadata key.

        Returns:
            The value stored at `key`.

        Raises:
            Error: If the key is not in the metadata.
        """
        if key not in self.metadata_dict:
            raise Error("no '" + key + "' in safetensors metadata")
        return self.metadata_dict[key]

    def get[dtype: DType](self, name: String) raises -> List[Scalar[dtype]]:
        """A tensor's values, flattened in row-major order and converted to `dtype`.

        Parameters:
            dtype: The type to convert the values to.

        Args:
            name: The tensor name.

        Returns:
            The tensor's values, with the last dimension changing fastest.

        Raises:
            Error: If there is no tensor called `name`, or its dtype is not supported.
        """
        var info = self.info(name)
        if info.dtype == "F64":
            return self._read[DType.float64, dtype](info)
        elif info.dtype == "F32":
            return self._read[DType.float32, dtype](info)
        elif info.dtype == "F16":
            return self._read[DType.float16, dtype](info)
        elif info.dtype == "BF16":
            return self._read[DType.bfloat16, dtype](info)
        elif info.dtype == "I64":
            return self._read[DType.int64, dtype](info)
        elif info.dtype == "I32":
            return self._read[DType.int32, dtype](info)
        elif info.dtype == "I16":
            return self._read[DType.int16, dtype](info)
        elif info.dtype == "I8":
            return self._read[DType.int8, dtype](info)
        elif info.dtype == "U8" or info.dtype == "BOOL":
            return self._read[DType.uint8, dtype](info)
        raise Error("unsupported safetensors dtype '" + info.dtype + "' for tensor '" + name + "'")

    @doc_hidden
    def _read[src: DType, dst: DType](self, info: TensorInfo) -> List[Scalar[dst]]:
        var n = info.num_elements()
        var result = List[Scalar[dst]](capacity=n)
        var p = self.data.unsafe_ptr().unsafe_offset(info.start).unsafe_bitcast[Scalar[src]]()
        for i in range(n):
            result.append(p.unsafe_load[alignment=1](i).cast[dst]())
        return result^

@doc_hidden
def _dtype_size(dtype: String) raises -> Int:
    """Bytes per element of a safetensors dtype.

    Args:
        dtype: The safetensors dtype name.

    Returns:
        The element size in bytes.
    """
    if dtype == "F64" or dtype == "I64" or dtype == "U64":
        return 8
    elif dtype == "F32" or dtype == "I32" or dtype == "U32":
        return 4
    elif dtype == "F16" or dtype == "BF16" or dtype == "I16" or dtype == "U16":
        return 2
    elif dtype == "I8" or dtype == "U8" or dtype == "BOOL" or dtype == "F8_E4M3" or dtype == "F8_E5M2":
        return 1
    raise Error("unsupported safetensors dtype '" + dtype + "'")

@doc_hidden
def _parse_header(text: Span[UInt8, _], data_start: Int, mut tensors: Dict[String, TensorInfo], mut metadata: Dict[String, String]) raises:
    """Parse the safetensors JSON header into tensor entries and `__metadata__`.

    Args:
        text: The header bytes.
        data_start: File offset where the tensor data starts.
        tensors: Receives one `TensorInfo` per tensor.
        metadata: Receives the `__metadata__` key/value pairs.
    """
    var p = _HeaderParser(text)
    p.expect(ord("{"))
    if p.next_is(ord("}")):
        return
    while True:
        var name = p.parse_string()
        p.expect(ord(":"))
        if name == "__metadata__":
            p.expect(ord("{"))
            if not p.next_is(ord("}")):
                while True:
                    var key = p.parse_string()
                    p.expect(ord(":"))
                    metadata[key] = p.parse_string()
                    if not p.comma_or_end(ord("}")):
                        break
        else:
            var dtype = String()
            var shape = List[Int]()
            var offsets = List[Int]()
            p.expect(ord("{"))
            if not p.next_is(ord("}")):
                while True:
                    var key = p.parse_string()
                    p.expect(ord(":"))
                    if key == "dtype":
                        dtype = p.parse_string()
                    elif key == "shape":
                        shape = p.parse_int_list()
                    elif key == "data_offsets":
                        offsets = p.parse_int_list()
                    else:
                        p.skip_value()
                    if not p.comma_or_end(ord("}")):
                        break
            if dtype.byte_length() == 0 or len(offsets) != 2:
                raise Error("safetensors tensor '" + name + "' is missing dtype or data_offsets")
            tensors[name] = TensorInfo(dtype, shape^, data_start + offsets[0], data_start + offsets[1])
        if not p.comma_or_end(ord("}")):
            break

@doc_hidden
struct _HeaderParser[origin: ImmOrigin]:
    """A minimal JSON reader for the safetensors header, which only holds objects, arrays, strings and integers."""

    var text: Span[UInt8, Self.origin]
    var pos: Int

    def __init__(out self, text: Span[UInt8, Self.origin]):
        self.text = text
        self.pos = 0

    def _at(self, i: Int) -> Int:
        return Int(self.text[i])

    def _is_space(self, c: Int) -> Bool:
        return c == ord(" ") or c == ord("\n") or c == ord("\r") or c == ord("\t")

    def _peek(mut self) raises -> Int:
        while self.pos < len(self.text) and self._is_space(self._at(self.pos)):
            self.pos += 1
        if self.pos >= len(self.text):
            raise Error("safetensors header ends unexpectedly")
        return self._at(self.pos)

    def expect(mut self, c: Int) raises:
        """Consume the character `c`, or raise."""
        if self._peek() != c:
            raise Error("malformed safetensors header: expected '" + chr(c) + "' at byte " + String(self.pos))
        self.pos += 1

    def next_is(mut self, c: Int) raises -> Bool:
        """Consume the character `c` if it is next, and return whether it was."""
        if self._peek() == c:
            self.pos += 1
            return True
        return False

    def comma_or_end(mut self, end: Int) raises -> Bool:
        """After a value in an object or array: True on a comma (more to come), False on `end`."""
        if self.next_is(ord(",")):
            return True
        self.expect(end)
        return False

    def _next_char(mut self) raises -> Int:
        if self.pos >= len(self.text):
            raise Error("safetensors header has an unterminated string")
        var c = self._at(self.pos)
        self.pos += 1
        return c

    def parse_string(mut self) raises -> String:
        """Parse a JSON string, decoding its escapes."""
        self.expect(ord('"'))
        var bytes = List[UInt8]()
        while True:
            var c = self._next_char()
            if c == ord('"'):
                break
            if c != ord("\\"):
                bytes.append(UInt8(c))
                continue
            var e = self._next_char()
            if e == ord("n"):
                bytes.append(UInt8(ord("\n")))
            elif e == ord("t"):
                bytes.append(UInt8(ord("\t")))
            elif e == ord("r"):
                bytes.append(UInt8(ord("\r")))
            elif e == ord("b"):
                bytes.append(8)
            elif e == ord("f"):
                bytes.append(12)
            elif e == ord("u"):
                var cp = self._parse_hex4()
                # join a UTF-16 surrogate pair
                if cp >= 0xD800 and cp < 0xDC00 and self.pos + 6 <= len(self.text) and self._at(self.pos) == ord("\\") and self._at(self.pos + 1) == ord("u"):
                    self.pos += 2
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (self._parse_hex4() - 0xDC00)
                _append_utf8(bytes, cp)
            else:
                bytes.append(UInt8(e))  # the escaped character itself: " \ /
        return String(from_utf8=Span(bytes))

    def _parse_hex4(mut self) raises -> Int:
        var v = 0
        for _ in range(4):
            var c = self._next_char()
            v *= 16
            if c >= ord("0") and c <= ord("9"):
                v += c - ord("0")
            elif c >= ord("a") and c <= ord("f"):
                v += c - ord("a") + 10
            elif c >= ord("A") and c <= ord("F"):
                v += c - ord("A") + 10
            else:
                raise Error("safetensors header has a bad unicode escape")
        return v

    def parse_int(mut self) raises -> Int:
        """Parse a non-negative integer."""
        _ = self._peek()
        var start = self.pos
        var v = 0
        while self.pos < len(self.text):
            var c = self._at(self.pos)
            if c < ord("0") or c > ord("9"):
                break
            v = v * 10 + (c - ord("0"))
            self.pos += 1
        if self.pos == start:
            raise Error("malformed safetensors header: expected an integer at byte " + String(start))
        return v

    def parse_int_list(mut self) raises -> List[Int]:
        """Parse an array of non-negative integers."""
        var result = List[Int]()
        self.expect(ord("["))
        if self.next_is(ord("]")):
            return result^
        while True:
            result.append(self.parse_int())
            if not self.comma_or_end(ord("]")):
                break
        return result^

    def skip_value(mut self) raises:
        """Skip over any JSON value."""
        var c = self._peek()
        if c == ord('"'):
            _ = self.parse_string()
        elif c == ord("{") or c == ord("["):
            var end = ord("}") if c == ord("{") else ord("]")
            self.pos += 1
            if self.next_is(end):
                return
            while True:
                if c == ord("{"):
                    _ = self.parse_string()
                    self.expect(ord(":"))
                self.skip_value()
                if not self.comma_or_end(end):
                    break
        else:
            # a number, true, false or null
            while self.pos < len(self.text):
                var d = self._at(self.pos)
                if d == ord(",") or d == ord("}") or d == ord("]") or self._is_space(d):
                    break
                self.pos += 1

@doc_hidden
def _append_utf8(mut bytes: List[UInt8], cp: Int):
    """Append the UTF-8 encoding of code point `cp`."""
    if cp < 0x80:
        bytes.append(UInt8(cp))
    elif cp < 0x800:
        bytes.append(UInt8(0xC0 | (cp >> 6)))
        bytes.append(UInt8(0x80 | (cp & 0x3F)))
    elif cp < 0x10000:
        bytes.append(UInt8(0xE0 | (cp >> 12)))
        bytes.append(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        bytes.append(UInt8(0x80 | (cp & 0x3F)))
    else:
        bytes.append(UInt8(0xF0 | (cp >> 18)))
        bytes.append(UInt8(0x80 | ((cp >> 12) & 0x3F)))
        bytes.append(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        bytes.append(UInt8(0x80 | (cp & 0x3F)))
