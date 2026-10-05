"""
This example demonstrates how to use YIN pitch detection, RMS amplitude analysis, and spectral centroid analysis in MMM-Audio.
"""

from mmm_python import *
ma = MMMAudio(128, graph_name="AnalysisExample", package_name="examples.ML_examples")
ma.start_audio()

ma.send_float("freq", 290.5)
ma.send_float("which", 2.0)
ma.stop_audio()