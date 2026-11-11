"""Camera-independent movement rules, workout state and transactional local wallet."""
from dataclasses import dataclass
from math import hypot, isfinite
from pathlib import Path
import sqlite3
import uuid

ACTIONS = {
    'reach': ('向上伸展', '双手抬到肩膀上方即可，不必完全伸直，再放下。'),
    'wings': ('双臂侧平举', '双臂向两侧打开即可，可以弯肘，不必严格平举，再放下。'),
    'curl': ('双臂弯举', '双手向肩膀方向抬近一些，再放下，不要求肘部标准。'),
}
JOINTS = (11, 12, 13, 14, 15, 16, 23, 24)
REQUIRED_JOINTS = (11, 12, 15, 16)
LANDMARK_CONFIDENCE = .25
EDGES = ((11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24))


def extract_pose(landmarks):
    if len(landmarks) != 33:
        return None
    points = {}
    for i in JOINTS:
        p = landmarks[i]
        if (not all(isfinite(v) for v in (p.x, p.y, p.visibility, p.presence))
                or min(p.visibility, p.presence) < LANDMARK_CONFIDENCE or not (0 <= p.x <= 1 and 0 <= p.y <= 1)):
            if i in REQUIRED_JOINTS:
                return None
            continue
        points[i] = (p.x, 1 - p.y)
    return points


def classify(p, action):
    """Coordinates are normalized, bottom-left origin, before mirroring."""
    if not p or any(i not in p for i in REQUIRED_JOINTS):
        return None
    if not all(isfinite(v) for point in p.values() for v in point):
        return None
    ls, rs, lw, rw = (p[i] for i in REQUIRED_JOINTS)
    shoulder_width = hypot(ls[0] - rs[0], ls[1] - rs[1])
    if shoulder_width < .04:
        return None
    # Shoulder-based scaling works even when elbows/hips are hidden by a desk.
    scale = max(.10, shoulder_width * 1.4)
    if action == 'reach':
        heights = (lw[1] - ls[1], rw[1] - rs[1])
        target = (min(heights) > scale * .08 or
                  (max(heights) > scale * .25 and min(heights) > -scale * .08))
    elif action == 'wings':
        target = (abs(lw[1] - ls[1]) < scale * .7 and abs(rw[1] - rs[1]) < scale * .7
                  and abs(lw[0] - ls[0]) > scale * .4 and abs(rw[0] - rs[0]) > scale * .4
                  and (lw[0] - ls[0]) * (rw[0] - rs[0]) < 0)
    elif action == 'curl':
        target = (hypot(lw[0] - ls[0], lw[1] - ls[1]) < scale * .9
                  and hypot(rw[0] - rs[0], rw[1] - rs[1]) < scale * .9
                  and lw[1] > ls[1] - scale * .45 and rw[1] > rs[1] - scale * .45)
    else:
        raise ValueError(action)
    if target:
        return 'target'
    if lw[1] < ls[1] - scale * .15 and rw[1] < rs[1] - scale * .15:
        return 'neutral'
    return 'middle'


@dataclass
class Cycle:
    phase: str = 'ready'
    last: float | None = None
    progress: float = 0
    held: float = 0
    previous_match: bool = False
    interrupted_since: float | None = None
    lost_since: float | None = None

    def reset(self):
        self.phase, self.last, self.progress = 'ready', None, 0
        self.held, self.previous_match = 0, False
        self.interrupted_since = self.lost_since = None

    def update(self, observation, now):
        dt = now - self.last if self.last is not None else 0
        if self.last is not None and (dt > .9 or dt <= 0):
            self.reset()
            dt = 0
        self.last = now
        if observation is None:
            if self.lost_since is None:
                self.lost_since = now
            self.previous_match = False
            if now - self.lost_since > .7:
                self.reset()
            return False
        if self.lost_since is not None and now - self.lost_since > .7:
            self.reset()
            self.last = now
            dt = 0
        self.lost_since = None
        expected = 'target' if self.phase == 'target' else 'neutral'
        if observation != expected:
            self.previous_match = False
            if self.interrupted_since is None:
                self.interrupted_since = now
            if observation in ('neutral', 'target') or now - self.interrupted_since > .35:
                self.held, self.progress = 0, 0
            return False
        self.interrupted_since = None
        # Only consecutive matching evidence adds time; missing/jitter frames never add time.
        if self.previous_match:
            self.held += dt
        self.previous_match = True
        self.progress = min(1., self.held / (.25 if self.phase == 'target' else .15))
        if self.progress < 1:
            return False
        self.held, self.progress, self.previous_match = 0, 0, False
        if self.phase == 'ready':
            self.phase = 'target'
        elif self.phase == 'target':
            self.phase = 'lower'
        else:
            self.phase = 'target'
            return True
        return False


class Wallet:
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path)
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS wallet(id INTEGER PRIMARY KEY CHECK(id=1), coins INTEGER NOT NULL CHECK(coins>=0));
            INSERT OR IGNORE INTO wallet VALUES(1,20);
            CREATE TABLE IF NOT EXISTS rewards(session TEXT, set_index INTEGER, PRIMARY KEY(session,set_index));
            CREATE TABLE IF NOT EXISTS inventory(item TEXT PRIMARY KEY, quantity INTEGER NOT NULL);
        ''')
        self.db.commit()

    @property
    def coins(self):
        return self.db.execute('SELECT coins FROM wallet WHERE id=1').fetchone()[0]

    def credit_set(self, session, index):
        with self.db:
            inserted = self.db.execute('INSERT OR IGNORE INTO rewards VALUES(?,?)', (session, index)).rowcount
            if inserted:
                self.db.execute('UPDATE wallet SET coins=coins+5 WHERE id=1')
        return bool(inserted)

    def buy(self, item, repeatable=True):
        with self.db:
            if not repeatable and self.quantity(item):
                return False
            changed = self.db.execute('UPDATE wallet SET coins=coins-1 WHERE id=1 AND coins>=1').rowcount
            if not changed:
                return False
            self.db.execute('INSERT INTO inventory VALUES(?,1) ON CONFLICT(item) DO UPDATE SET quantity=quantity+1', (item,))
        return True

    def quantity(self, item):
        row = self.db.execute('SELECT quantity FROM inventory WHERE item=?', (item,)).fetchone()
        return row[0] if row else 0


class Workout:
    def __init__(self, actions, sets, wallet):
        if not actions or any(a not in ACTIONS for a in actions) or not 1 <= sets <= 20:
            raise ValueError('请选择动作及 1–20 组')
        self.actions, self.target, self.wallet = list(dict.fromkeys(actions)), sets, wallet
        self.session = uuid.uuid4().hex
        self.completed = self.index = self.reps = 0
        self.paused = False
        self.cycle = Cycle()

    @property
    def finished(self):
        return self.completed >= self.target

    @property
    def current(self):
        return self.actions[self.index]

    @property
    def progress(self):
        return (self.completed * len(self.actions) * 3 + self.index * 3 + self.reps) / (self.target * len(self.actions) * 3)

    def pause(self, value):
        self.paused = value
        self.cycle.reset()

    def update(self, points, now):
        if self.paused or self.finished:
            return None
        if not self.cycle.update(classify(points, self.current), now):
            return None
        self.reps += 1
        if self.reps < 3:
            return 'rep'
        self.reps = 0
        self.index += 1
        self.cycle.reset()
        if self.index < len(self.actions):
            return 'action'
        # Keep progress unchanged if the local transaction fails, allowing a retry.
        try:
            self.wallet.credit_set(self.session, self.completed + 1)
        except Exception:
            self.index = len(self.actions) - 1
            self.reps = 2
            raise
        self.index = 0
        self.completed += 1
        return 'finished' if self.finished else 'set'
