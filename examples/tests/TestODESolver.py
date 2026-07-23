"""
Test the ODE solvers.

TestODEOscillator: RK4 simple harmonic oscillator, should produce a clean sine wave.
TestODEFilter: Euler RC lowpass filter, mouse X controls cutoff frequency.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from mmm_python.MMMAudio import MMMAudio

# -- Oscillator test --
osc = MMMAudio(128, graph_name="TestODEOscillator", package_name="examples.tests")
osc.start_audio()
osc.send_float("frequency", 220.0)  # A3
osc.send_float("frequency", 440.0)  # A4
osc.send_float("frequency", 880.0)  # A5
osc.stop_audio()

# -- Filter test --
filt = MMMAudio(128, graph_name="TestODEFilter", package_name="examples.tests")
filt.start_audio()
# Move mouse left/right to sweep cutoff frequency
filt.stop_audio()
