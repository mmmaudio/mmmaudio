from mmm_audio import *

struct Print(Copyable, Movable):
    """
    A struct for printing values in the MMMWorld environment.
    """
    var impulse: Impulse[1]
    var world: World

    def __init__(out self, world: World):
        """
        Initialize the Print struct.

        Args:
            world: A pointer to the MMMWorld instance.
        """
        self.world = world
        self.impulse = Impulse(world)

    def next[T: Writable](mut self, value: T, label: Optional[String] = None, freq: Float64 = 10.0) -> None:
        """
        Print the value at a given frequency.

        Parameters:
            T: Type of the printable value.

        Args:
            value: The value to print.
            label: An optional label to prepend to the printed value.
            freq: The frequency (in Hz) at which to print the value.
        """
        if self.impulse.next_bool(freq):
            if label:
                print(label.value() + ": ", value)
            else:
                print(value)