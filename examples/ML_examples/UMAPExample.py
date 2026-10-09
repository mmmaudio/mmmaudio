from PySide6.QtWidgets import QApplication
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from mmm_python import *
from umap import UMAP
from sklearn.neighbors import KDTree

app = QApplication([])

mfccs = MBufAnalysis.mfcc({"path": "resources/Shiverer.wav"})
print("MFCC shape:", mfccs.shape)

reducs = UMAP().fit_transform(mfccs)
kdtree = KDTree(reducs)

def get_nearest(view, x, y, button, is_dragging, key, dblclick, step):
    if step is None:
        dist, idx = kdtree.query([[x, y]], k=1)
        view.highlight_index(int(idx[0][0]))
        print(
            f"Nearest idx: {idx[0][0]}, dist: {dist[0][0]:.4f}"
        )

win = MPlot(reducs, mouse_callback=get_nearest)
win.resize(700, 500)
win.show()
app.exec()