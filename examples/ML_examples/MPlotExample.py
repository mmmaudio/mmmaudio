from PySide6.QtWidgets import QApplication, QMainWindow, QWidget, QVBoxLayout, QSizePolicy
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from mmm_python import *
from umap import UMAP
from sklearn.neighbors import KDTree
import librosa
import numpy as np
import pickle
from sklearn.preprocessing import StandardScaler
import argparse

def main():
    parser = argparse.ArgumentParser(description="Run the MPlotExample.")
    parser.add_argument("--analysis", type=str, help="Path to pickled analysis dict with keys 'data_umap' and 'slice_points'", required=False)
    args = parser.parse_args()

    if not args.analysis:
        # parameters for analysis
        d = {
            "path": "resources/Shiverer.wav",
            # "path": "/Users/ted/Desktop/all_flucoma.wav",
            # threshold for spectral flux onset detection, lower is more sensitive, higher is less sensitive
            "thresh":2.0,
            # minimum length of slices in seconds
            "min_slice_len":0.1,
            # window size and hop size used for all analyses
            "window_size":1024,
            "hop_size":512,
            # num mfcc coefficients to compute (including 0th), we will discard the 0th coefficient later
            "num_coeffs": 14
        }

        # use librosa to load audio file to get sample rate and samples for plotting waveform
        y, sr = librosa.load(d["path"], sr=None)
        
        # slice using spectral flux
        slice_points = MBufAnalysis.spectral_flux_onsets(d)

        print("num slice points:", len(slice_points))
        print("avg slice duration:", np.diff(slice_points).mean() / sr)

        slice_points = np.insert(slice_points, 0, 0) # add start of file as first slice point
        slice_points = np.append(slice_points, len(y)) # add end of file as last slice point
        data = np.ndarray((len(slice_points)-1, 13)) # create array to hold slice features

        for i in range(len(slice_points)-1):
            start = int(slice_points[i])
            end = int(slice_points[i+1])
            print(f"Slice {i} / {len(slice_points)-1}: start={start}, end={end}, duration={(end-start)/sr:.2f} seconds")
            d["start_frame"] = start
            d["num_frames"] = end - start
            mfccs = MBufAnalysis.mfcc(d)
            # remove 0th coefficient and take mean across time axis to get one feature vector per slice
            data[i] = mfccs[:, 1:].mean(axis=0)

        data = StandardScaler().fit_transform(data)

        print("data shape:", data.shape)

        data_umap = UMAP(n_components=2,learning_rate=0.1,min_dist=0.01,n_epochs=200).fit_transform(data)

        # pickle analysis
        with open("examples/ML_examples/MPlotExample_Analysis.pkl", "wb") as f:
            pickle.dump({
                "data_umap": data_umap,
                "slice_points": slice_points,
                "path": d["path"]
            }, f)
    else:
        with open(args.analysis, "rb") as f:
            d = pickle.load(f)
        data_umap = d["data_umap"]
        slice_points = d["slice_points"]
        y, sr = librosa.load(d["path"], sr=None)

    kdtree = KDTree(data_umap)

    ma = MMMAudio(128,graph_name="MPlotExample", package_name="examples.ML_examples", in_device=None, out_device="default")
    ma.send_string("load_sound", d["path"])

    prev = None

    def get_nearest(view, x, y, button, is_dragging, key, dblclick, step):
        nonlocal prev
        if step is None:
            dist, idx = kdtree.query([[x, y]], k=1)
            nearest = int(idx[0][0])
            if nearest != prev:
                prev = nearest
                start = slice_points[nearest]
                num = slice_points[nearest+1] - start
                
                view.highlight_index(nearest)
                
                waveform_win.highlight(start, num)
                
                ma.send_ints("play_data", [start, num])
                print(f"x: {x:.2f}, y: {y:.2f}")
                print(f"Nearest idx: {idx[0][0]}, dist: {dist[0][0]:.4f}")

    app = QApplication([])
    main = QMainWindow()
    root = QWidget()
    layout = QVBoxLayout(root)

    win = MPlot(data_umap, mouse_callback=get_nearest,xlabel="UMAP 1", ylabel="UMAP 2")
    waveform_win = MWaveform(y, slice_points)
    waveform_win.setFixedHeight(220)
    waveform_win.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)

    layout.addWidget(win)
    layout.addWidget(waveform_win)
    layout.setStretch(0, 1)
    layout.setStretch(1, 0)
    main.setCentralWidget(root)

    def shutdown_audio():
        ma.stop_audio()
        ma.stop_process()

    app.aboutToQuit.connect(shutdown_audio)
    main.closeEvent = lambda event: (shutdown_audio(), event.accept())

    main.resize(900, 850)
    main.show()

    ma.start_audio()

    sys.exit(app.exec())

if __name__ == "__main__":
    main()