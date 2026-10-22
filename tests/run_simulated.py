"""Runs LexicalDecision_pupil.osexp end-to-end without a participant or eye tracker.

A simulated participant answers every keyboard request (about 80% correct, RTs of
350-900 ms, so some trials time out once the deadlines get short), the sleep
questions get a fixed answer, and the eye tracker is set to PyGaze's 'Simple dummy'.
Every message sent with eyetracker.log() is written to tests/output/messages.tsv.

Usage (with OpenSesame's Python):
    "C:\\Program Files (x86)\\OpenSesame\\python.exe" tests\\run_simulated.py [--fullscreen]
"""
import os
import random
import sys
import time

EXP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(EXP_DIR, 'tests', 'output')
EXP_FILE = os.path.join(EXP_DIR, 'LexicalDecision_pupil.osexp')
SUBJECT_NR = 999
FULLSCREEN = '--fullscreen' in sys.argv

os.makedirs(OUT_DIR, exist_ok=True)
os.chdir(EXP_DIR)
random.seed(1)

from openexp.backend import configurable
from openexp._keyboard import psycho as psycho_keyboard
import pygaze.eyetracker

MESSAGES = []
SLEEP_KEYS = iter(['7', 'return', '8', 'return'])


@configurable
def simulated_get_key(self):
    keylist = list(self.keylist) if self.keylist is not None else None
    timeout = self.timeout
    clock = self.experiment.clock
    if keylist is not None and 'n' in keylist and 'm' in keylist:
        rt = random.uniform(350, 900)
        if timeout is not None and rt >= timeout:
            clock.sleep(timeout)
            return None, clock.time()
        clock.sleep(rt)
        correct_response = str(self.experiment.var.correct_response)
        if random.random() < 0.8:
            return correct_response, clock.time()
        return ('m' if correct_response == 'n' else 'n'), clock.time()
    clock.sleep(20)
    if keylist is None:
        try:
            return next(SLEEP_KEYS), clock.time()
        except StopIteration:
            return 'space', clock.time()
    return keylist[0], clock.time()


psycho_keyboard.Psycho.get_key = simulated_get_key

_EyeTracker = pygaze.eyetracker.EyeTracker


def recording_eyetracker(*args, **kwargs):
    tracker = _EyeTracker(*args, **kwargs)
    tracker.log = lambda msg: MESSAGES.append((time.perf_counter() * 1000, str(msg)))
    return tracker


pygaze.eyetracker.EyeTracker = recording_eyetracker

from libopensesame.experiment import Experiment

with open(EXP_FILE, encoding='utf-8') as fd:
    script = fd.read()

exp = Experiment(
    string=script,
    experiment_path=EXP_DIR,
    fullscreen=FULLSCREEN,
    subject_nr=SUBJECT_NR,
    logfile=os.path.join(OUT_DIR, 'subject-{}.csv'.format(SUBJECT_NR)),
)
exp.items['pygaze_init'].var.tracker_type = 'Simple dummy'
exp.items['pygaze_init'].var.calbeep = 'no'
exp.items['pygaze_init'].var._logfile = os.path.join(OUT_DIR, 'pygaze_dummy')

try:
    exp.run()
finally:
    with open(os.path.join(OUT_DIR, 'messages.tsv'), 'w', encoding='utf-8') as fd:
        fd.write('time_ms\tmessage\n')
        for t, msg in MESSAGES:
            fd.write('{:.1f}\t{}\n'.format(t, msg))
    print('MESSAGES_WRITTEN', len(MESSAGES))
