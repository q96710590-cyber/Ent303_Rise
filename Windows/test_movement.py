from types import SimpleNamespace
import pytest
from engine import ACTIONS, Cycle, Workout, Wallet, classify, extract_pose


def pose(action=None):
    p = {11:(.4,.65),12:(.6,.65),13:(.38,.48),14:(.62,.48),
         15:(.38,.35),16:(.62,.35),23:(.42,.35),24:(.58,.35)}
    if action == 'reach': p.update({13:(.36,.78),14:(.64,.78),15:(.37,.94),16:(.63,.94)})
    if action == 'wings': p.update({13:(.28,.65),14:(.72,.65),15:(.12,.65),16:(.88,.65)})
    if action == 'curl': p.update({15:(.39,.64),16:(.61,.64)})
    return p


@pytest.mark.parametrize('action', ACTIONS)
def test_geometry_and_cycle(action):
    assert classify(pose(), action) == 'neutral'
    assert classify(pose(action), action) == 'target'
    cycle, t, count = Cycle(), 0., 0
    def feed(value, n=12):
        nonlocal t, count
        for _ in range(n):
            t += .1
            count += cycle.update(value, t)
    feed('target', 50)
    assert count == 0
    feed('neutral'); feed('target', 50)
    assert count == 0
    feed('neutral')
    assert count == 1
    feed('target', 2); feed(None, 10); feed('target'); feed('neutral')
    assert count == 1
    feed('target', 2); t += 5; feed('target'); feed('neutral')
    assert count == 1


def test_bad_landmarks():
    landmarks = [SimpleNamespace(x=.5, y=.5, presence=1., visibility=1.) for _ in range(33)]
    assert extract_pose(landmarks)
    landmarks[15].visibility = .1
    assert extract_pose(landmarks) is None
    landmarks[15].visibility = 1.; landmarks[11].x = float('nan')
    assert extract_pose(landmarks) is None
    assert classify({11:(.5,.5)}, 'reach') is None
    assert classify(None, 'reach') is None


def test_relaxed_landmarks_optional_elbows_and_hips():
    landmarks = [SimpleNamespace(x=.5, y=.5, presence=.3, visibility=.3) for _ in range(33)]
    for i in (13,14,23,24): landmarks[i].visibility = .01
    p = extract_pose(landmarks)
    assert p is not None and set(p) == {11,12,15,16}
    landmarks[16].visibility = .1
    assert extract_pose(landmarks) is None


@pytest.mark.parametrize('action,wrists', [
    ('reach', ((.38,.70),(.62,.69))),  # Barely above shoulders; elbows need not straighten.
    ('reach', ((.38,.74),(.62,.64))),  # Uneven arms.
    ('wings', ((.24,.52),(.76,.55))),  # Bent, angled down instead of exactly level.
    ('curl', ((.35,.55),(.65,.56))),   # Partial curl, wrists still below shoulders.
])
def test_relaxed_targets_without_hips_or_elbows(action, wrists):
    p = {11:(.4,.65),12:(.6,.65),15:wrists[0],16:wrists[1]}
    assert classify(p, action) == 'target'
    p.update({15:(.38,.52),16:(.62,.53)})
    # A small lowering is enough; no need to hang wrists down to the hips.
    assert classify(p, action) == 'neutral'


def test_short_occlusion_and_jitter_keep_cycle_but_do_not_count_absence():
    c = Cycle(); now = 0.; reps = 0
    def feed(value, frames):
        nonlocal now, reps
        for _ in range(frames):
            now += .1; reps += c.update(value, now)
    feed('neutral', 4)
    assert c.phase == 'target'
    feed('target', 2)
    previous = c.progress
    feed(None, 2)
    assert c.progress == previous and c.phase == 'target' and reps == 0
    feed('target', 1); feed('middle', 1); feed('target', 3)
    assert c.phase == 'lower' and reps == 0
    feed(None, 3)
    assert c.phase == 'lower' and reps == 0
    feed('neutral', 4)
    assert reps == 1


def test_all_actions_stationary_pose_never_earns(tmp_path):
    wallet = Wallet(tmp_path/'wallet.db')
    for action in ACTIONS:
        w = Workout([action], 1, wallet)
        for i in range(500): w.update(pose(action), i*.1)
        assert w.reps == 0 and w.completed == 0
    assert wallet.coins == 20
    wallet.db.close()


def test_rewards_pause_partial_and_persistence(tmp_path):
    path = tmp_path/'wallet.db'; wallet = Wallet(path)
    w = Workout(list(ACTIONS), 2, wallet); now = 0.
    def feed(p, frames=12):
        nonlocal now
        events = []
        for _ in range(frames):
            now += .1
            events.append(w.update(p, now))
        return events
    feed(pose()); w.pause(True); feed(pose('reach'), 30); feed(pose())
    assert w.reps == 0 and wallet.coins == 20
    w.pause(False)
    for group in (1, 2):
        for action in ACTIONS:
            feed(pose())
            for _ in range(3): feed(pose(action)); feed(pose())
        assert w.completed == group and wallet.coins == 20+group*5
    assert w.finished and w.progress == 1
    feed(pose('reach')); feed(pose())
    assert wallet.coins == 30
    assert not wallet.credit_set(w.session, 1)
    assert wallet.coins == 30
    wallet.db.close(); wallet = Wallet(path)
    assert wallet.coins == 30
    assert wallet.buy('accs_00', False)
    assert not wallet.buy('accs_00', False)
    assert wallet.coins == 29 and wallet.quantity('accs_00') == 1
    assert wallet.buy('food_00') and wallet.buy('food_00')
    assert wallet.quantity('food_00') == 2
    wallet.db.close()


def test_insufficient_balance_and_distinct_sessions(tmp_path):
    wallet = Wallet(tmp_path/'wallet.db')
    for _ in range(20): assert wallet.buy('food_00')
    assert wallet.coins == 0 and not wallet.buy('food_00')
    assert wallet.credit_set('session-a', 1)
    assert wallet.credit_set('session-b', 1)
    assert wallet.coins == 10
    wallet.db.close()


def test_partial_set_has_no_reward(tmp_path):
    wallet = Wallet(tmp_path/'wallet.db')
    w = Workout(['reach'], 1, wallet)
    now = 0.
    for p in (pose(), pose('reach'), pose()):
        for _ in range(12): now += .1; w.update(p, now)
    assert w.reps == 1 and w.completed == 0 and wallet.coins == 20
    wallet.db.close()


def test_wallet_failure_is_retryable(tmp_path):
    wallet = Wallet(tmp_path/'wallet.db')
    w = Workout(['reach'], 1, wallet)
    original = wallet.credit_set
    def fail(*args): raise OSError('disk unavailable')
    wallet.credit_set = fail
    now = 0.
    with pytest.raises(OSError):
        for _ in range(3):
            for p in (pose(), pose('reach'), pose()):
                for _ in range(12): now += .1; w.update(p, now)
    assert w.index == 0 and w.reps == 2 and wallet.coins == 20
    wallet.credit_set = original
    for p in (pose(), pose('reach'), pose()):
        for _ in range(12): now += .1; w.update(p, now)
    assert w.finished and wallet.coins == 25
    wallet.db.close()


@pytest.mark.parametrize('actions,sets', [([],1),(['unknown'],1),(['reach'],0),(['reach'],21)])
def test_invalid_plan(tmp_path, actions, sets):
    wallet = Wallet(tmp_path/'wallet.db')
    with pytest.raises(ValueError): Workout(actions,sets,wallet)
    wallet.db.close()
