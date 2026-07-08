from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QSlider, QPushButton, QLabel, QHBoxLayout, QMainWindow, QWidget, QVBoxLayout, QSizePolicy
from PySide6.QtCore import Qt, Signal, QSize
from PySide6.QtGui import QPainter, QPen, QBrush
from PySide6.QtCore import QPointF
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from matplotlib import colors as mcolors

from .functions import clip, linlin

class ControlSpec:
    """
    Defines the range and response curve for a control parameter.
    
    Args:
        min: Minimum value of the control parameter.
        max: Maximum value of the control parameter.
        exp: Exponent for the response curve. 1.0 = linear, >1.0 = logarithmic, <1.0 = exponential.
    """
    def __init__(self, min: float = 0.0, max: float = 1.0, exp: float = 1.0):
        if min >= max:
            raise ValueError("ControlSpec min must be less than max")
        if exp <= 0:
            raise ValueError("ControlSpec exp must be positive")
        self.min = min
        self.max = max
        self.exp = exp
    
    def normalize(self, val: float) -> float:
        """Take in an unnormalized value and return a value between 0.0 and 1.0"""
        norm_val = linlin(val, self.min, self.max, 0.0, 1.0)
        return clip(norm_val ** (1.0 / self.exp), 0.0, 1.0)

    def unnormalize(self, norm_val: float) -> float:
        """Take in a normalized value between 0.0 and 1.0 and return an unnormalized value"""
        curved_norm = clip(norm_val, 0.0, 1.0) ** self.exp
        return linlin(curved_norm, 0.0, 1.0, self.min, self.max)

class Handle(QWidget):
    """A convenience widget that combines a label, a slider, and a value display."""
    def __init__(self, label: str, spec: ControlSpec = ControlSpec(), default: float = 0.0, callback=None, orientation=Qt.Horizontal, resolution: int = 1000, display_resolution: int = 2, run_callback_on_init: bool = False):
        super().__init__()
        self.resolution = resolution
        self.handle = QSlider(orientation)
        self.display_resolution = display_resolution
        self.display = QLabel(f"{default:.{display_resolution}f}")
        self.label = QLabel(label)
        self.layout = QHBoxLayout()
        self.layout.addWidget(self.label)
        self.layout.addWidget(self.handle)
        self.layout.addWidget(self.display)
        self.setLayout(self.layout)
        self.handle.setMinimum(0)
        self.handle.setMaximum(resolution)
        self.spec = spec
        self.handle.setValue(int(spec.normalize(clip(default, spec.min, spec.max)) * resolution))
        self.callback = callback
        self.handle.valueChanged.connect(self.update)
        if run_callback_on_init:
            self.update()
        
    def update(self):
        v = self.get_value()
        self.display.setText(f"{v:.{self.display_resolution}f}")
        if self.callback:
            self.callback(v)

    def get_value(self):
        return self.spec.unnormalize(self.handle.value() / self.resolution)
    
    def set_value(self, value: float):
        value = self.spec.normalize(clip(value, self.spec.min, self.spec.max))
        self.handle.setValue(int(value * self.resolution))
        
class Slider2D(QWidget):
    """A custom 2D slider widget"""
    
    # Signal emitted when the slider value changes
    valueChanged = Signal(float, float)
    pressed = Signal(bool)
    
    def __init__(self, width=300, height=300, parent=None):
        super().__init__(parent)
        self.setMinimumSize(width, height)
        self.setMaximumSize(width, height)
        
        # Slider position (0.0 to 1.0 for both x and y)
        self._x = 0.5
        self._y = 0.5
        
        self._handle_radius = 10
        
    def get_values(self):
        """Get current X and Y values (0.0 to 1.0)"""
        return self._x, self._y
    
    def set_values(self, x, y):
        """Set X and Y values (0.0 to 1.0)"""
        self._x = max(0.0, min(1.0, x))
        self._y = max(0.0, min(1.0, y))
        self.update()
        self.valueChanged.emit(self._x, self._y)
    
    def _pos_to_values(self, pos):
        """Convert widget position to slider values"""
        margin = self._handle_radius
        width = self.width() - 2 * margin
        height = self.height() - 2 * margin
        
        x = (pos.x() - margin) / width
        y = 1.0 - (pos.y() - margin) / height  # Invert Y so bottom is 0
        
        return max(0.0, min(1.0, x)), max(0.0, min(1.0, y))
    
    def _values_to_pos(self):
        """Convert slider values to widget position"""
        margin = self._handle_radius
        width = self.width() - 2 * margin
        height = self.height() - 2 * margin
        
        x = margin + self._x * width
        y = margin + (1.0 - self._y) * height  # Invert Y so bottom is 0
        
        return QPointF(x, y)
    
    def paintEvent(self, event):
        """Paint the slider"""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # Draw background
        painter.fillRect(self.rect(), Qt.lightGray)
        
        # Draw border
        pen = QPen(Qt.black, 2)
        painter.setPen(pen)
        painter.drawRect(self.rect())
        
        # Draw grid lines
        pen = QPen(Qt.gray, 1)
        painter.setPen(pen)
        
        # Vertical lines
        for i in range(1, 4):
            x = self.width() * i / 4
            painter.drawLine(x, 0, x, self.height())
        
        # Horizontal lines
        for i in range(1, 4):
            y = self.height() * i / 4
            painter.drawLine(0, y, self.width(), y)
        
        # Draw center lines
        pen = QPen(Qt.darkGray, 2)
        painter.setPen(pen)
        center_x = self.width() / 2
        center_y = self.height() / 2
        painter.drawLine(center_x, 0, center_x, self.height())
        painter.drawLine(0, center_y, self.width(), center_y)
        
        # Draw handle
        handle_pos = self._values_to_pos()
        brush = QBrush(Qt.blue)
        painter.setBrush(brush)
        pen = QPen(Qt.darkBlue, 2)
        painter.setPen(pen)
        painter.drawEllipse(handle_pos, self._handle_radius, self._handle_radius)
    
    def mousePressEvent(self, event):
        """Handle mouse press"""
        if event.button() == Qt.LeftButton:
            self.pressed.emit(True)
            x, y = self._pos_to_values(event.position())
            self.set_values(x, y)
    
    def mouseMoveEvent(self, event):
        """Handle mouse move"""
        if self.pressed:
            x, y = self._pos_to_values(event.position())
            self.set_values(x, y)
    
    def mouseReleaseEvent(self, event):
        """Handle mouse release"""
        if event.button() == Qt.LeftButton:
            self.pressed.emit(False)
        

class MPlot(QWidget):
    def __init__(self, points, mouse_callback=None, xlabel=None, ylabel=None, parent=None):
        super().__init__(parent)
        self.mouse_callback = mouse_callback
        self._pressed_button = None
        self._modifiers = set()
        self._points = points

        self.fig = Figure(figsize=(5, 4), dpi=100)
        self.canvas = FigureCanvas(self.fig)
        self.canvas.setFocusPolicy(Qt.StrongFocus)
        self.canvas.setFocus()
        self.ax = self.fig.add_subplot(111)
        self.ax.set_aspect("equal", adjustable="box")

        self._scatter = self.ax.scatter(points[:, 0], points[:, 1], s=4, zorder=1)
        self._highlight_color = mcolors.to_rgba("orange")
        self._highlight_index = None
        self._highlight_marker = self.ax.scatter(
            [],
            [],
            s=30,
            color=self._highlight_color,
            edgecolors="black",
            linewidths=0.5,
            zorder=3,
            animated=True,  # excluded from normal draws; we blit it ourselves
        )
        self._bg = None  # cached background for blitting
    
        if xlabel:
            self.ax.set_xlabel(xlabel)
        if ylabel:
            self.ax.set_ylabel(ylabel)

        self.canvas.mpl_connect("draw_event", self._on_draw)
        self.canvas.mpl_connect("motion_notify_event", self._on_motion)
        self.canvas.mpl_connect("button_press_event", self._on_press)
        self.canvas.mpl_connect("button_release_event", self._on_release)
        self.canvas.mpl_connect("key_press_event", self._on_key_press)
        self.canvas.mpl_connect("key_release_event", self._on_key_release)
        self.canvas.mpl_connect("scroll_event", self._on_scroll)

        layout = QVBoxLayout(self)
        layout.addWidget(self.canvas)
        policy = self.sizePolicy()
        policy.setHeightForWidth(True)
        self.setSizePolicy(policy)

    def hasHeightForWidth(self):
        return True

    def heightForWidth(self, width):
        return width

    def sizeHint(self):
        return QSize(500, 500)

    def _on_motion(self, event):
        # event.xdata, event.ydata are in data coords; None if outside axes
        if self._pressed_button is None:
            return
        self._emit_point(event, is_dragging=True)

    def _on_press(self, event):
        if event.inaxes != self.ax:
            return
        self._pressed_button = event.button
        self._emit_point(event, is_dragging=False)

    def _on_release(self, event):
        if event.button == self._pressed_button:
            self._pressed_button = None

    def _on_scroll(self, event):
        if event.inaxes != self.ax:
            return
        self._emit_point(event, is_dragging=False)

    def _on_key_press(self, event):
        self._update_modifiers(event, pressed=True)

    def _on_key_release(self, event):
        self._update_modifiers(event, pressed=False)

    def _update_modifiers(self, event, pressed):
        if not event.key:
            return
        keys = event.key.split("+")
        for key in keys:
            if pressed:
                self._modifiers.add(key)
            else:
                self._modifiers.discard(key)

    def _emit_point(self, event, is_dragging):
        if event.inaxes != self.ax or event.xdata is None or event.ydata is None:
            return
        key = self._modifiers_from_event(event)
        button = event.button if event.button is not None else self._pressed_button
        step = getattr(event, "step", None)
        step = step if step != 0 else None
        dblclick = getattr(event, "dblclick", False)
        if self.mouse_callback:
            self.mouse_callback(
                self,
                event.xdata,
                event.ydata,
                button,
                is_dragging,
                key,
                dblclick,
                step,
            )

    def _modifiers_from_event(self, event):
        gui_event = getattr(event, "guiEvent", None)
        if gui_event is not None:
            mods = gui_event.modifiers()
            names = []
            if mods & Qt.ShiftModifier:
                names.append("shift")
            if mods & Qt.ControlModifier:
                names.append("cmd")
            if mods & Qt.AltModifier:
                names.append("alt")
            if mods & Qt.MetaModifier:
                names.append("ctrl")
            return "+".join(names) if names else None
        if self._modifiers:
            return "+".join(sorted(self._modifiers))
        return None

    def _on_draw(self, event):
        """Cache the background (without the animated highlight) after every full redraw."""
        self._bg = self.canvas.copy_from_bbox(self.ax.bbox)
        # Re-blit the highlight if one is active so it reappears after a resize/zoom
        if self._highlight_index is not None:
            self.ax.draw_artist(self._highlight_marker)
            self.canvas.blit(self.ax.bbox)

    def highlight_index(self, idx):
        if idx is None or idx < 0 or idx >= len(self._points):
            return
        self._highlight_index = idx
        self._highlight_marker.set_offsets(self._points[idx])
        if self._bg is not None:
            # Fast path: restore static background, paint only the orange dot
            self.canvas.restore_region(self._bg)
            self.ax.draw_artist(self._highlight_marker)
            self.canvas.blit(self.ax.bbox)
        else:
            # Fallback before the first full draw has happened
            self.canvas.draw_idle()


class MWaveform(QWidget):
    def __init__(self, wave, slice_points, parent=None):
        super().__init__(parent)
        self._slice_points = slice_points
        self._wave_length = len(wave)

        fig = Figure(figsize=(6, 3), dpi=100)
        self.canvas = FigureCanvas(fig)
        self.ax = fig.add_subplot(111)

        self.ax.plot(wave, color="black", linewidth=0.6, alpha=0.85)

        if slice_points is not None and len(slice_points) > 0:
            self.ax.vlines(
                slice_points,
                ymin=wave.min(),
                ymax=wave.max(),
                color="steelblue",
                linewidth=0.6,
                alpha=0.6,
                zorder=2,
            )

        # Create a persistent highlight Polygon (animated=True excludes it from normal draws)
        self._slice_highlight = self.ax.axvspan(
            0, 1, color="orange", alpha=0.25, zorder=3, animated=True, visible=False
        )
        self._bg = None  # cached background for blitting

        self.ax.set_xlabel("Samples")
        self.ax.set_ylabel("Amplitude")

        self.canvas.mpl_connect("draw_event", self._on_draw)
        layout = QVBoxLayout(self)
        layout.addWidget(self.canvas)

    def _on_draw(self, event):
        """Cache the static background after every full redraw."""
        self._bg = self.canvas.copy_from_bbox(self.ax.bbox)
        if self._slice_highlight.get_visible():
            self.ax.draw_artist(self._slice_highlight)
            self.canvas.blit(self.ax.bbox)

    def highlight(self, start_frame, num_frames):
        if num_frames <= 0 or self._wave_length <= 0:
            return

        start_frame = int(max(0, start_frame))
        end_frame = int(min(start_frame + num_frames, self._wave_length))
        if start_frame >= end_frame:
            return

        # axvspan returns a Rectangle — update its position and width in-place
        self._slice_highlight.set_x(start_frame)
        self._slice_highlight.set_width(end_frame - start_frame)
        self._slice_highlight.set_visible(True)

        if self._bg is not None:
            self.canvas.restore_region(self._bg)
            self.ax.draw_artist(self._slice_highlight)
            self.canvas.blit(self.ax.bbox)
        else:
            self.canvas.draw_idle()