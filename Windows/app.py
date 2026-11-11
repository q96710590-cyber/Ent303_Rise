import logging
import math
import sys
import time
from pathlib import Path

from PySide6.QtCore import Qt, QSize, QTimer, QPointF
from PySide6.QtGui import QColor, QFont, QIcon, QImage, QMovie, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QCheckBox, QSpinBox, QFrame, QProgressBar, QMessageBox,
    QTabWidget, QGridLayout, QComboBox, QScrollArea)

from engine import ACTIONS, Wallet, Workout

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parent / 'Resources'
BROWN, SAGE, YELLOW = '#5c4f4d', '#67896d', '#ffce63'

STYLE = '''
QMainWindow, QWidget#root { background: #fffbe5; }
QWidget { color: #5c4f4d; font-family: 'Microsoft YaHei UI'; font-size: 13px; }
QLabel { background: transparent; }
QFrame#card { background: #fffef6; border: 1px solid #eee3c8; border-radius: 18px; }
QFrame#guide { background: #fff0bf; border: 1px solid #f2dd9c; border-radius: 20px; }
QLabel#title { font-size: 26px; font-weight: 700; }
QLabel#section { font-size: 17px; font-weight: 700; }
QLabel#muted { color: #93877c; font-size: 12px; }
QLabel#balance { background: #ffce63; border-radius: 20px; padding: 12px 22px; font-size: 18px; font-weight: 700; }
QLabel#bubble { background: #fffef6; border-radius: 16px; padding: 16px; font-size: 15px; }
QLabel#preview { background: #f2ead7; border: 1px solid #e9dec0; border-radius: 16px; color: #918274; }
QPushButton { background: #f3ecd6; border: 1px solid #e7dcba; border-radius: 12px; padding: 9px 15px; }
QPushButton:hover { background: #f8e6ab; border-color: #ddbf72; }
QPushButton:pressed { background: #ebcf85; }
QPushButton:disabled { color: #b4aa98; background: #efe9d8; border-color: #e7e0cf; }
QPushButton#primary { background: #ffce63; border-color: #ecc05d; font-weight: 700; padding: 12px 24px; }
QPushButton#primary:hover { background: #ffd77f; }
QPushButton#primary:disabled { background: #eee5cc; color: #b6ab92; border-color: #e7dfca; }
QCheckBox { spacing: 8px; padding: 8px; }
QCheckBox::indicator { width: 16px; height: 16px; border: 2px solid #cfb879; border-radius: 5px; background: #fffef5; }
QCheckBox::indicator:checked { background: #ffce63; border-color: #a98942; }
QSpinBox, QComboBox { background: #fffdf5; border: 1px solid #dfd0a7; border-radius: 8px; padding: 6px; min-height: 22px; }
QProgressBar { border: none; background: #ede6ce; border-radius: 5px; height: 10px; text-align: center; }
QProgressBar::chunk { background: #87a88b; border-radius: 5px; }
QProgressBar#hold::chunk { background: #ffce63; }
QTabWidget::pane { border: none; background: transparent; }
QTabBar::tab { background: transparent; padding: 10px 20px; margin-right: 6px; color: #998a73; border-bottom: 3px solid transparent; }
QTabBar::tab:selected { color: #5c4f4d; border-bottom: 3px solid #e8bb55; font-weight: 700; }
QScrollArea { border: none; background: transparent; }
QScrollArea > QWidget > QWidget { background: transparent; }
'''


def label(text='', name='', wrap=False):
    widget = QLabel(text)
    widget.setObjectName(name)
    widget.setWordWrap(wrap)
    return widget


def card(name='card'):
    widget = QFrame()
    widget.setObjectName(name)
    layout = QVBoxLayout(widget)
    layout.setContentsMargins(18, 16, 18, 16)
    layout.setSpacing(12)
    return widget, layout


class MovementDemo(QWidget):
    def __init__(self):
        super().__init__()
        self.action = 'reach'
        self.running = True
        self.elapsed = 0
        self.setMinimumHeight(145)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.advance)
        self.timer.start(50)

    def advance(self):
        if self.running:
            self.elapsed += .05
            self.update()

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.translate(self.width()/2, 5)
        raised = self.elapsed % 4 > 2
        p.setPen(QPen(QColor(SAGE), 6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
        p.drawEllipse(QPointF(0, 18), 10, 10)
        def line(a, b):
            p.drawLine(QPointF(*a), QPointF(*b))
        line((0, 35), (0, 88))
        for side in (-1, 1):
            line((0, 44), (side*16, 44))
            start = (side*16, 44)
            if not raised:
                end = (side*25, 94)
            elif self.action == 'reach':
                end = (side*29, 4)
            elif self.action == 'wings':
                end = (side*70, 44)
            else:
                line(start, (side*24, 73))
                start, end = (side*24, 73), (side*22, 44)
            line(start, end)
            line((0, 88), (side*25, 128))
        p.setPen(QColor(BROWN))
        p.setFont(QFont('Microsoft YaHei UI', 9))
        p.drawText(-80, 143, 160, 20, Qt.AlignCenter, '抬起并保持' if raised else '自然放下 · 准备')


class MainWindow(QMainWindow):
    def __init__(self, data_dir=None):
        super().__init__()
        self.setWindowTitle('RISE · 小猫陪练 · Windows')
        self.setWindowIcon(QIcon(str(ASSETS/'logo.png')))
        self.resize(1100, 860)
        self.setMinimumSize(950, 720)
        self.wallet = Wallet((Path(data_dir) if data_dir else ROOT/'data')/'rise.sqlite3')
        self.worker = None
        self.workout = None
        self.last_frame = 0
        self.ready = False
        self.auto_ready_since = None
        self.reward_until = 0
        self.closing = False
        self.current_image = None
        self.last_error = ''
        central = QWidget(); central.setObjectName('root')
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)
        outer.setContentsMargins(28, 20, 28, 20); outer.setSpacing(14)
        header = QHBoxLayout()
        titles = QVBoxLayout()
        titles.addWidget(label('RISE  /  小猫陪你动一动', 'title'))
        titles.addWidget(label('轻松模式 · 动一动就很好，不要求标准姿势。', 'muted'))
        header.addLayout(titles); header.addStretch()
        self.balance = label('', 'balance'); header.addWidget(self.balance)
        outer.addLayout(header)
        self.tabs = QTabWidget()
        outer.addWidget(self.tabs, 1)
        self.build_workout()
        self.build_shop()
        self.tabs.currentChanged.connect(self.tab_changed)
        outer.addWidget(label('摄像头画面仅在本机识别，不录制、不上传。金币与背包保存在这台电脑。', 'muted'))
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(200)
        self.refresh()

    def build_workout(self):
        page = QWidget(); layout = QVBoxLayout(page); layout.setContentsMargins(0, 14, 0, 0)
        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        content = QWidget(); body = QHBoxLayout(content); body.setContentsMargins(0, 0, 8, 4); body.setSpacing(20)
        left = QVBoxLayout(); left.setSpacing(12)
        camera_card, c = card()
        row = QHBoxLayout(); row.addWidget(label('01  看见你的每一次努力', 'section')); row.addStretch()
        self.camera_state = label('● 摄像头关闭', 'muted'); row.addWidget(self.camera_state); c.addLayout(row)
        self.preview = label('准备好了，就开启摄像头吧\n\n只要双肩和双手入镜，坐着或站着都能做', 'preview', True)
        self.preview.setAlignment(Qt.AlignCenter); self.preview.setMinimumSize(500, 300)
        c.addWidget(self.preview, 1)
        self.detection = label('轻松模式：双肩、双手入镜后自动开始，动作大致做到即可。', 'muted', True); c.addWidget(self.detection)
        controls = QHBoxLayout()
        controls.addWidget(label('设备'))
        self.camera_index = QSpinBox(); self.camera_index.setRange(0, 10); controls.addWidget(self.camera_index)
        self.camera_button = QPushButton('开启摄像头'); self.camera_button.clicked.connect(self.toggle_camera)
        controls.addWidget(self.camera_button); controls.addStretch()
        controls.addWidget(label('镜像画面 · 本机处理', 'muted')); c.addLayout(controls)
        left.addWidget(camera_card, 1)

        plan, p = card()
        p.addWidget(label('02  今天，想动几组？', 'section'))
        choices = QHBoxLayout(); self.choices = {}
        for action, (title, _) in ACTIONS.items():
            box = QCheckBox(title); box.setChecked(True); box.toggled.connect(self.refresh)
            self.choices[action] = box; choices.addWidget(box)
        p.addLayout(choices)
        count = QHBoxLayout(); count.addWidget(label('跟练组数'))
        self.sets = QSpinBox(); self.sets.setRange(1, 20); self.sets.setValue(3)
        self.sets.valueChanged.connect(self.refresh); count.addWidget(self.sets)
        count.addStretch(); self.estimate = label(); count.addWidget(self.estimate); p.addLayout(count)
        p.addWidget(label('每组：依次做完已选动作，每个动作 3 次。每完整一组奖励 5 金币。', 'muted', True))
        self.progress_title = label('还没开始，一切都刚刚好。')
        self.total_progress = QProgressBar(); self.total_progress.setRange(0, 1000); self.total_progress.setTextVisible(False)
        self.hold_progress = QProgressBar(); self.hold_progress.setObjectName('hold'); self.hold_progress.setTextVisible(False)
        self.hold_progress.setRange(0, 100); self.hold_progress.setFixedHeight(7)
        p.addWidget(self.progress_title); p.addWidget(self.total_progress); p.addWidget(self.hold_progress)
        left.addWidget(plan)
        body.addLayout(left, 7)

        guide, g = card('guide'); guide.setMinimumWidth(250); guide.setMaximumWidth(300)
        g.addWidget(label('你的专属陪练小猫', 'section'))
        self.cat = label(); self.cat.setAlignment(Qt.AlignCenter); self.cat.setFixedHeight(190)
        self.cat_movie = QMovie(str(ASSETS/'movement/RISE_cat_tail_only_cropped.gif'))
        self.cat_movie.setScaledSize(QSize(185, 180)); self.cat.setMovie(self.cat_movie); self.cat_movie.start()
        g.addWidget(self.cat)
        self.bubble = label('', 'bubble', True); self.bubble.setMinimumHeight(110); g.addWidget(self.bubble)
        self.demo = MovementDemo(); g.addWidget(self.demo)
        self.demo_title = label('向上伸展 · 动作示意'); self.demo_title.setAlignment(Qt.AlignCenter); g.addWidget(self.demo_title)
        self.guide_note = label('大致抬起、稍停一下、再放下就算一次。允许弯肘、左右不齐和短暂遮挡，不必做得标准。', 'muted', True)
        g.addWidget(self.guide_note)
        self.reward = label('完整完成一组，收获 5 金币'); self.reward.setWordWrap(True); self.reward.setAlignment(Qt.AlignCenter)
        self.reward.setStyleSheet('font-weight:700;color:#82601e;padding:10px;'); g.addWidget(self.reward)
        self.coin = label(); self.coin.setAlignment(Qt.AlignCenter); self.coin.setFixedHeight(68)
        self.coin_movie = QMovie(str(ASSETS/'movement/RISE_gold_coin_rise_fade_transparent.gif'))
        self.coin_movie.setScaledSize(QSize(150, 150)); self.coin.setMovie(self.coin_movie)
        self.coin.hide(); g.addWidget(self.coin); g.addStretch()
        body.addWidget(guide, 3)
        scroll.setWidget(content); layout.addWidget(scroll, 1)
        buttons = QHBoxLayout()
        self.end_button = QPushButton('结束本次'); self.end_button.clicked.connect(self.end_workout)
        self.pause_button = QPushButton('暂停一下'); self.pause_button.clicked.connect(self.toggle_pause)
        buttons.addWidget(self.end_button); buttons.addWidget(self.pause_button); buttons.addStretch()
        self.auto_status = label('自动检测 · 等待开启摄像头', 'muted')
        buttons.addWidget(self.auto_status); layout.addLayout(buttons)
        self.tabs.addTab(page, '运动赚金币')

    def build_shop(self):
        page = QWidget(); layout = QVBoxLayout(page); layout.setContentsMargins(0, 18, 0, 0)
        row = QHBoxLayout(); row.addWidget(label('给小猫挑一份礼物', 'section')); row.addStretch()
        self.shop_mode = QComboBox(); self.shop_mode.addItems(['小猫商店', '我的背包']); row.addWidget(self.shop_mode)
        self.category = QComboBox(); self.category.addItems(['食物 FOOD', '植物 PLANT', '小床 BEDS', '配饰 ACCS'])
        row.addWidget(self.category); layout.addLayout(row)
        layout.addWidget(label('沿用原设计素材与每件 1 金币的价格。食物、植物可重复购买，小床和配饰每件限购一次。', 'muted', True))
        scroll = QScrollArea(); scroll.setWidgetResizable(True)
        self.shop_grid_widget = QWidget(); self.shop_grid = QGridLayout(self.shop_grid_widget)
        scroll.setWidget(self.shop_grid_widget); layout.addWidget(scroll, 1)
        self.shop_status = label('用活动赚来的金币，让小猫的日常更丰富。', 'muted'); layout.addWidget(self.shop_status)
        self.category.currentIndexChanged.connect(self.refresh_shop)
        self.shop_mode.currentIndexChanged.connect(self.refresh_shop)
        self.tabs.addTab(page, '小猫商店 / 背包')
        self.refresh_shop()

    def refresh_shop(self, *_):
        while self.shop_grid.count():
            item = self.shop_grid.takeAt(0)
            if item.widget(): item.widget().deleteLater()
        category = ('food', 'plant', 'beds', 'accs')[self.category.currentIndex()]
        backpack = self.shop_mode.currentIndex() == 1
        visible = 0
        for index in range(16):
            key = f'{category}_{index:02d}'
            owned = self.wallet.quantity(key)
            if backpack and not owned: continue
            tile, t = card(); image = label(); image.setAlignment(Qt.AlignCenter)
            pixmap = QPixmap(str(ASSETS/'shop'/category/f'{key}.png'))
            image.setPixmap(pixmap.scaled(120, 105, Qt.KeepAspectRatio, Qt.SmoothTransformation)); t.addWidget(image)
            title = label(f'{self.category.currentText().split()[0]} {index+1:02d}  ·  已有 {owned}')
            title.setAlignment(Qt.AlignCenter); t.addWidget(title)
            if not backpack:
                button = QPushButton('已拥有' if owned and category in ('beds', 'accs') else '购买 · 1 金币')
                button.setEnabled(self.wallet.coins >= 1 and not (owned and category in ('beds', 'accs')))
                button.clicked.connect(lambda checked=False, k=key, r=category in ('food', 'plant'): self.purchase(k, r))
                t.addWidget(button)
            self.shop_grid.addWidget(tile, visible//4, visible%4); visible += 1
        if not visible:
            self.shop_grid.addWidget(label('这里还空空的，去商店给小猫挑一份礼物吧。'), 0, 0)
        self.balance.setText(f'金币  {self.wallet.coins}')

    def purchase(self, item, repeatable):
        try:
            bought = self.wallet.buy(item, repeatable)
            self.shop_status.setText('礼物已放入背包，扣除 1 金币。' if bought else '暂时无法购买：余额不足或已经拥有。')
            self.refresh_shop()
        except Exception as exc:
            QMessageBox.warning(self, '保存失败', f'未能保存购买记录：{exc}')

    def tab_changed(self, index):
        self.auto_ready_since = None
        if index == 1:
            if self.workout and not self.workout.finished: self.workout.pause(True)
            self.refresh_shop(); self.refresh()

    def selected_actions(self):
        return [a for a, box in self.choices.items() if box.isChecked()]

    def toggle_camera(self):
        if self.worker:
            if self.workout and not self.workout.finished: self.workout.pause(True)
            self.stop_camera(); self.refresh(); return
        from camera import CameraWorker
        self.ready = False; self.last_frame = 0; self.last_error = ''
        self.auto_ready_since = None
        self.worker = CameraWorker(self.camera_index.value(), ROOT/'models/pose_landmarker_lite.task', self)
        self.worker.frame.connect(self.on_frame)
        self.worker.error.connect(self.on_error)
        self.worker.finished.connect(self.camera_finished)
        self.detection.setText('正在加载本地模型并连接摄像头…')
        self.camera_button.setText('正在连接…'); self.camera_index.setEnabled(False)
        self.worker.start(); self.refresh()

    def stop_camera(self):
        self.ready = False
        self.auto_ready_since = None
        if self.worker:
            self.worker.requestInterruption(); self.camera_button.setText('正在关闭…')

    def camera_finished(self):
        worker = self.worker
        if worker: worker.deleteLater()
        self.worker = None; self.ready = False; self.current_image = None
        self.preview.clear(); self.preview.setText('摄像头已关闭\n\n' + ('目标完成，辛苦啦！' if self.workout and self.workout.finished else '准备好后，可以重新开启'))
        self.camera_index.setEnabled(True); self.camera_button.setText('开启摄像头')
        self.detection.setText(self.last_error or '摄像头已释放，已完成组的奖励保留。')
        self.refresh()
        if self.closing: self.close()

    def on_error(self, message):
        self.last_error = message
        logging.error('Camera error: %s', message)
        if self.workout and not self.workout.finished: self.workout.pause(True)
        self.detection.setText(message)

    def on_frame(self, image, points, message, captured):
        if not self.worker or self.worker.isInterruptionRequested(): return
        now = time.monotonic()
        previous_frame = self.last_frame
        self.last_frame = captured
        self.current_image = image
        self.draw_preview()
        # Ignore old deliveries so stalled UI cannot finish a hold from buffered frames.
        self.ready = points is not None and now-captured <= .6
        if (not self.ready or self.tabs.currentIndex() != 0 or self.closing
                or not self.selected_actions() or captured <= previous_frame
                or captured-previous_frame > .6):
            self.auto_ready_since = None
        if self.workout is None and self.ready and self.tabs.currentIndex() == 0 and not self.closing and self.selected_actions():
            if self.auto_ready_since is None:
                self.auto_ready_since = captured
            if captured-self.auto_ready_since >= .5:
                self.begin_automatic_workout()
        self.detection.setText(message if now-captured <= .6 else '画面延迟较高，请稍等，暂不计数。')
        self.camera_button.setText('关闭摄像头')
        if self.workout:
            try:
                event = self.workout.update(points if self.ready else None, captured)
            except Exception as exc:
                self.workout.pause(True)
                QMessageBox.warning(self, '奖励保存失败', f'已暂停跟练，避免丢失金币。请检查磁盘后继续：{exc}')
                event = None
            if event in ('set', 'finished'):
                self.reward_until = now + 2.4
                self.reward.setText(f'第 {self.workout.completed} 组完成！ +5 金币')
                self.coin.show(); self.coin_movie.stop(); self.coin_movie.start()
            if event == 'finished':
                self.stop_camera()
        self.refresh()

    def draw_preview(self):
        if self.current_image is not None:
            pix = QPixmap.fromImage(self.current_image)
            self.preview.setPixmap(pix.scaled(self.preview.size()-QSize(4, 4), Qt.KeepAspectRatio, Qt.SmoothTransformation))

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'preview'): self.draw_preview()

    def begin_automatic_workout(self):
        if self.workout is not None or not self.ready or time.monotonic()-self.last_frame > .7 or not self.selected_actions(): return
        self.workout = Workout(self.selected_actions(), self.sets.value(), self.wallet)
        self.reward.setText('每完成一组，金币自动存入钱包。'); self.refresh()

    def toggle_pause(self):
        if self.workout and not self.workout.finished:
            if self.workout.paused and (not self.ready or time.monotonic()-self.last_frame > .7):
                self.detection.setText('请开启摄像头并让完整姿势入镜后继续。'); return
            self.workout.pause(not self.workout.paused); self.refresh()

    def end_workout(self):
        if not self.workout: return
        if not self.workout.finished:
            self.workout.pause(True)
            self.refresh()
            result = QMessageBox.question(self, '结束本次跟练？',
                f'已完成 {self.workout.completed} 组、获得 {self.workout.completed*5} 金币，会保留。\n未完成的一组不计奖励。',
                QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
            if result != QMessageBox.Yes: return
        self.stop_camera(); self.workout = None; self.refresh()

    def tick(self):
        now = time.monotonic()
        if now-self.last_frame > .7:
            self.ready = False
            self.auto_ready_since = None
            if self.workout: self.workout.cycle.reset()
        if self.reward_until and now > self.reward_until:
            self.coin_movie.stop(); self.coin.hide(); self.reward_until = 0
        self.refresh()

    def refresh(self, *_):
        # Choice signals can arrive while the initial controls are being constructed.
        if not hasattr(self, 'auto_status'): return
        w = self.workout
        active = w is not None and not w.finished
        self.balance.setText(f'金币  {self.wallet.coins}')
        self.estimate.setText(f'目标收获  {self.sets.value()*5} 金币')
        for box in self.choices.values(): box.setEnabled(not active)
        self.sets.setEnabled(not active)
        if w and w.finished:
            status = f'目标完成 · 已自动入账 {w.completed*5} 金币'
        elif active:
            status = '已暂停 · 点击继续跟练恢复' if w.paused else '自动计数中 · 每组自动入账 5 金币'
        elif not self.selected_actions():
            status = '请至少选择一种动作'
        else:
            status = '轻松模式 · 双肩双手入镜后自动开始' if self.worker else '轻松模式 · 等待开启摄像头'
        self.auto_status.setText(status)
        self.end_button.setEnabled(w is not None)
        self.end_button.setText('再练一轮' if w and w.finished else '结束本次')
        self.pause_button.setEnabled(active and self.worker is not None and not self.worker.isInterruptionRequested())
        self.pause_button.setText('继续跟练' if w and w.paused else '暂停一下')
        stopping = self.worker is not None and self.worker.isInterruptionRequested()
        self.camera_button.setEnabled(not stopping and not self.closing)
        self.camera_state.setText('● 摄像头使用中' if self.worker else '● 摄像头关闭')
        self.camera_state.setStyleSheet(f'color:{SAGE if self.worker else "#93877c"}')
        self.total_progress.setValue(round(w.progress*1000) if w else 0)
        self.hold_progress.setValue(round(w.cycle.progress*100) if w else 0)
        action = w.current if w else (self.selected_actions() or ['reach'])[0]
        self.demo.action = action
        self.demo_title.setText(ACTIONS[action][0]+' · 动作示意')
        self.demo.running = not (w and w.paused)
        self.cat_movie.setPaused(bool(w and w.paused))
        if not w:
            self.progress_title.setText('准备：自然站立，双手放下。')
            cue = '喵～选好动作和组数，开启摄像头。站稳后我会自动计数，每完成一组就送你 5 枚金币！'
        elif w.finished:
            self.progress_title.setText(f'目标完成！{w.completed} 组 · 已入账 {w.completed*5} 金币')
            cue = f'喵！今天完成 {w.completed} 组，收获 {w.completed*5} 枚金币。去给我挑个礼物吧～'
        else:
            self.progress_title.setText(f'第 {w.completed+1}/{w.target} 组  ·  {ACTIONS[action][0]}  {w.reps}/3 次  ·  已赚 {w.completed*5} 金币')
            if w.paused: cue = '先休息一下吧，已完成的进度和金币都在。准备好再继续。'
            elif not self.ready: cue = '只要让我看到双肩和双手就好，不必露出肘部和髋部。画面中只留你一个人哦。'
            elif w.cycle.phase == 'ready': cue = '先把双手自然放下，稳定片刻。我们准备开始啦！'
            elif w.cycle.phase == 'lower': cue = '做得很好！现在把双手自然放下，稳定片刻，就算完成一次。'
            else: cue = ACTIONS[action][1]+' 稍停一下就好，不用特别标准哦。'
        self.bubble.setText(cue)

    def closeEvent(self, event):
        if self.worker:
            if not self.closing and self.workout and not self.workout.finished:
                self.workout.pause(True); self.refresh()
                result = QMessageBox.question(self, '关闭小猫陪练？', '已完成组的金币已保存，未完成组不计奖励。', QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
                if result != QMessageBox.Yes: event.ignore(); return
            self.closing = True
            self.stop_camera()
            self.detection.setText('正在释放摄像头，随后关闭窗口…')
            event.ignore()
        else:
            self.timer.stop(); self.cat_movie.stop(); self.coin_movie.stop()
            self.wallet.db.close(); event.accept()


def main():
    (ROOT/'data').mkdir(exist_ok=True)
    logging.basicConfig(filename=ROOT/'data/app.log', level=logging.INFO, encoding='utf-8', format='%(asctime)s %(levelname)s %(message)s')
    app = QApplication(sys.argv)
    app.setStyle('Fusion'); app.setStyleSheet(STYLE)
    def handle_error(kind, value, tb):
        logging.error('Unhandled exception', exc_info=(kind, value, tb))
        QMessageBox.critical(None, 'RISE 出现问题', f'{value}\n详情已保存到 Windows/data/app.log。')
    sys.excepthook = handle_error
    window = MainWindow(); window.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    main()
