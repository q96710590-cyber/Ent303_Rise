import time
import cv2
import mediapipe as mp
from PySide6.QtCore import QThread, Signal
from PySide6.QtGui import QImage
from engine import extract_pose, EDGES


class CameraWorker(QThread):
    frame = Signal(QImage, object, str, float)
    error = Signal(str)

    def __init__(self, index, model, parent=None):
        super().__init__(parent)
        self.index, self.model = index, model

    def run(self):
        cap = detector = None
        try:
            options = mp.tasks.vision.PoseLandmarkerOptions(
                base_options=mp.tasks.BaseOptions(model_asset_path=str(self.model)),
                running_mode=mp.tasks.vision.RunningMode.VIDEO, num_poses=2,
                min_pose_detection_confidence=.35,
                min_pose_presence_confidence=.35,
                min_tracking_confidence=.35)
            detector = mp.tasks.vision.PoseLandmarker.create_from_options(options)
            if self.isInterruptionRequested():
                return
            cap = cv2.VideoCapture(self.index, cv2.CAP_DSHOW)
            if not cap.isOpened():
                raise RuntimeError('无法开启摄像头。请检查设备编号、摄像头连接及 Windows 摄像头权限。')
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            failed, stamp, previous = 0, 0, None
            while not self.isInterruptionRequested():
                begin = time.monotonic()
                ok, bgr = cap.read()
                if not ok:
                    failed += 1
                    if failed >= 5:
                        raise RuntimeError('摄像头连接中断，请重新连接后开启。')
                    self.msleep(80)
                    continue
                failed = 0
                rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                stamp = max(stamp + 1, int(begin * 1000))
                result = detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), stamp)
                points = None
                message = '轻松模式 · 只需让双肩和双手入镜'
                if len(result.pose_landmarks) > 1:
                    message, previous = '画面中有多人，暂不计数，请只保留一人', None
                elif result.pose_landmarks:
                    landmarks = result.pose_landmarks[0]
                    center = ((landmarks[11].x + landmarks[12].x) / 2, (landmarks[11].y + landmarks[12].y) / 2)
                    if previous and ((center[0]-previous[0])**2+(center[1]-previous[1])**2)**.5 > .3:
                        message = '位置变化较大，请站稳后重新准备'
                    else:
                        points = extract_pose(landmarks)
                        message = '已找到你 · 轻松模式，不要求动作标准' if points else '稍微调整位置，让双肩和双手入镜即可，不需要露出髋部'
                    previous = center
                    if points:
                        h, w = rgb.shape[:2]
                        for a, b in EDGES:
                            if a not in points or b not in points:
                                continue
                            pa, pb = [(int(points[i][0]*w), int((1-points[i][1])*h)) for i in (a, b)]
                            cv2.line(rgb, pa, pb, (255, 206, 99), 3, cv2.LINE_AA)
                            cv2.circle(rgb, pa, 5, (255, 250, 224), -1, cv2.LINE_AA)
                            cv2.circle(rgb, pb, 5, (255, 250, 224), -1, cv2.LINE_AA)
                else:
                    previous = None
                rgb = cv2.flip(rgb, 1).copy()
                h, w = rgb.shape[:2]
                image = QImage(rgb.data, w, h, rgb.strides[0], QImage.Format_RGB888).copy()
                # Timestamp represents image acquisition, not delayed delivery to the UI.
                self.frame.emit(image, points, message, begin)
                self.msleep(max(1, int((.09 - (time.monotonic() - begin)) * 1000)))
        except Exception as exc:
            self.error.emit(str(exc))
        finally:
            if cap is not None:
                cap.release()
            if detector is not None:
                detector.close()
