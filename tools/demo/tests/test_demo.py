import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('boop_demo', Path(__file__).parents[1] / 'demo.py')
demo = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = demo
spec.loader.exec_module(demo)


class Serial:
    def __init__(self):
        self.writes = []
        self.info = dict(board='ws-amoled164', contract=2, usbOnly=False)
        self.current = dict(mute=1, snapName='Real buddy', snapTasks=42, skin='default',
                            accessory='', silhouette='', level=1, streak=3, firstWake=False,
                            frozen=False, badFrames=0, creature='idle', momentVisible=False,
                            layer='face', cardId='', bubble='', threadCount=0, recentCount=0)
        self.reject = False

    def framed_json(self, command, tag, timeout):
        return dict(self.info if command == 'ping' else self.current)

    def write_line(self, wire):
        self.writes.append(wire)
        value = json.loads(wire)
        if self.reject:
            self.current['badFrames'] += 1
            return
        self.current.update(creature=value['state'], mute=value['mute'],
                            momentVisible='moment' in value, cardId=value.get('card', {}).get('id', ''),
                            threadCount=len(value.get('threads', [])))


class DemoTests(unittest.TestCase):
    def test_all_frames_preserve_persistent_fields_and_fit_contract(self):
        for scenes in demo.flows().values():
            for scene in scenes:
                for mute in range(4):
                    value = json.loads(demo.encode(scene.frame, mute))
                    self.assertEqual(value.pop('mute'), mute)
                    self.assertTrue(set(value) <= demo.ALLOWED)
                    for row in value.get('agents', []):
                        self.assertIn(row['source'], ['codex', 'claude-code', 'cursor', 'other'])
                    m = value.get('moment')
                    if m:
                        self.assertLessEqual(len(m['text']), 48 if m['kind'] == 'completed' else 24)
                        self.assertGreater(m['id'], 0)
                        self.assertLessEqual(m['id'], 2**32 - 1)
                        self.assertTrue(m['text'].isascii())

    def test_persistent_and_command_fields_are_refused(self):
        for key in ['snap', 'cosmetic', 't', 'cmd', 'mute']:
            with self.assertRaises(ValueError):
                demo.encode({**demo.frame(), key: {}}, 1)

    def test_keepalive_counts_down_and_does_not_revive_moment(self):
        original = demo.frame('working', moment=demo.moment('start', 'On it!'))
        later = demo.at_age(original, 1)
        self.assertEqual(later['moment']['age'], 1000)
        self.assertEqual(later['moment']['left'], 500)
        self.assertEqual(original['moment']['left'], 1500)
        self.assertNotIn('moment', demo.at_age(original, 1.5))

    def test_success_and_retry_have_intended_durations(self):
        flows = demo.flows()
        self.assertEqual(sum(s.seconds or 0 for s in flows['success'] if s.frame['state'] == 'working'), 4.5)
        self.assertEqual(flows['success'][3].frame['moment']['tier'], 'full')
        self.assertEqual(flows['failure'][-2].frame['moment']['tier'], 'caption')
        self.assertEqual(flows['attention'][3].frame['state'], 'needsYou')
        self.assertNotIn('approval', flows['attention'][3].frame['card'])

    def test_reset_clears_attention_text_and_tasks_preserving_settings(self):
        serial = Serial()
        device = demo.Device(serial)
        serial.current.update(cardId='demo-123', momentVisible=True, threadCount=1)
        before = {k: serial.current[k] for k in demo.PRESERVED}
        device.reset()
        self.assertEqual(serial.current['creature'], 'asleep')
        self.assertFalse(serial.current['cardId'])
        self.assertFalse(serial.current['momentVisible'])
        self.assertEqual({k: serial.current[k] for k in demo.PRESERVED}, before)
        self.assertFalse(any('snap' in json.loads(w) for w in serial.writes))

    def test_interruption_eof_and_failure_all_attempt_cleanup(self):
        for exception in [KeyboardInterrupt(), EOFError(), RuntimeError('USB error')]:
            serial = Serial()
            device = demo.Device(serial)
            def fail(*args):
                device.send(demo.flows()['attention'][3].frame)
                raise exception
            with patch.object(demo, 'play', side_effect=fail):
                with self.assertRaises(type(exception)):
                    demo.run(device, ['attention'])
            self.assertEqual(serial.current['creature'], 'asleep')
            self.assertFalse(serial.current['cardId'])

    def test_rejected_frames_and_failed_restoration_are_not_reported_as_success(self):
        serial = Serial()
        device = demo.Device(serial)
        serial.reject = True
        with self.assertRaises(RuntimeError):
            device.reset()
        serial = Serial()
        device = demo.Device(serial)
        serial.current['snapTasks'] += 1
        with self.assertRaisesRegex(RuntimeError, 'Saved-state'):
            device.reset()

    def test_preflight_rejects_unsafe_or_incompatible_device_without_writes(self):
        for key, value in [('firstWake', True), ('frozen', True)]:
            serial = Serial()
            serial.current[key] = value
            with self.assertRaises(RuntimeError):
                demo.Device(serial)
            self.assertEqual(serial.writes, [])
        serial = Serial()
        serial.info['usbOnly'] = True
        with self.assertRaises(RuntimeError):
            demo.Device(serial)
        self.assertEqual(serial.writes, [])


if __name__ == '__main__':
    unittest.main()
