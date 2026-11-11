"""Headless GUI and local model smoke test; never opens a camera or production wallet."""
import os
os.environ['QT_QPA_PLATFORM'] = 'offscreen'
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import numpy as np
import mediapipe as mp
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QImage
from app import MainWindow, STYLE, ROOT
from test_movement import pose

app = QApplication([])
app.setStyle('Fusion'); app.setStyleSheet(STYLE)
with TemporaryDirectory() as temp:
    window = MainWindow(temp)
    window.show(); app.processEvents()
    assert window.wallet.coins == 20 and window.workout is None
    assert not hasattr(window, 'start_button')
    assert window.cat_movie.isValid() and window.coin_movie.isValid()
    window.sets.setValue(5); app.processEvents()
    assert '25' in window.estimate.text()
    window.tabs.setCurrentIndex(1); app.processEvents()
    assert window.shop_grid.count() == 16
    window.purchase('food_00', True)
    assert window.wallet.coins == 19 and window.wallet.quantity('food_00') == 1
    window.shop_mode.setCurrentIndex(1); app.processEvents()
    assert window.shop_grid.count() == 1
    window.category.setCurrentIndex(1); app.processEvents()
    window.tabs.setCurrentIndex(0); app.processEvents()
    window.current_image = QImage(640,480,QImage.Format_RGB888)
    window.current_image.fill(0); window.draw_preview(); app.processEvents()
    assert not window.preview.pixmap().isNull()

    # Feed real UI callbacks with a fake camera; no camera access or production credits.
    class FakeCamera:
        stopped = False
        def isInterruptionRequested(self): return self.stopped
        def requestInterruption(self): self.stopped = True
        def deleteLater(self): pass

    window.worker = FakeCamera()
    window.sets.setValue(1)
    for action, box in window.choices.items(): box.setChecked(action == 'reach')
    now = 100.
    def feed(points, frames=12, age=.01):
        global now
        for _ in range(frames):
            now += .1
            with patch('app.time.monotonic', return_value=now+age):
                window.on_frame(window.current_image, points, '测试姿势', now)

    feed(None)
    assert window.workout is None
    feed(pose(), age=1.)
    assert window.workout is None, 'Old frames must never auto-start'
    feed(pose(), frames=3); feed(None, frames=1)
    assert window.workout is None, 'Brief detection must not auto-start'
    for box in window.choices.values(): box.setChecked(False)
    feed(pose())
    assert window.workout is None, 'Empty action selection must not auto-start'
    window.choices['reach'].setChecked(True)
    window.tabs.setCurrentIndex(1); feed(pose())
    assert window.workout is None, 'Shop tab must not auto-start a workout'
    window.tabs.setCurrentIndex(0); feed(pose())
    assert window.workout is not None and window.workout.reps == 0
    assert window.wallet.coins == 19, 'Detection alone never credits coins'
    session = window.workout.session
    window.workout.pause(True); feed(pose('reach')); feed(pose())
    assert window.workout.paused and window.workout.session == session and window.workout.reps == 0
    window.workout.pause(False)
    for _ in range(3):
        feed(pose()); feed(pose('reach')); feed(pose())
    assert window.workout.finished and window.wallet.coins == 24
    assert window.worker.stopped, 'Meeting the selected goal should release the camera'
    feed(pose('reach')); feed(pose())
    assert window.wallet.coins == 24, 'Finished goals must not repeat rewards'
    window.camera_finished()
    window.close(); app.processEvents()

options = mp.tasks.vision.PoseLandmarkerOptions(
    base_options=mp.tasks.BaseOptions(model_asset_path=str(ROOT/'models/pose_landmarker_lite.task')),
    running_mode=mp.tasks.vision.RunningMode.VIDEO, num_poses=2)
with mp.tasks.vision.PoseLandmarker.create_from_options(options) as model:
    result = model.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.zeros((480,640,3),np.uint8)),1)
    assert not result.pose_landmarks
print('Runtime checks passed: automatic start, invalid/stale/brief poses, empty selection, shop exclusion, pause, exactly 5 coins per set, goal stop, window, animations, shop/inventory, preview, offline model. No webcam used.')
