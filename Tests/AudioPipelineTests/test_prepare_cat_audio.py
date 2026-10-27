import importlib.util
import hashlib
import json
import math
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / 'Tools/AudioPipeline/prepare_cat_audio.py'
SPEC = importlib.util.spec_from_file_location('prepare_cat_audio', SCRIPT)
AUDIO = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIO)


class AudioPreparationTests(unittest.TestCase):
    def test_runtime_purr_is_reproducible_from_real_recording(self):
        root = SCRIPT.parents[2]
        source = root / 'Characters/PaperCat/Assets/AudioSources/Kerzoven/cat_purrsleepy_loop.wav'
        raw, rate = AUDIO.read_pcm(source)
        prepared, _ = AUDIO.prepare(raw, rate, True)
        with tempfile.TemporaryDirectory() as directory:
            generated = pathlib.Path(directory) / 'purr.wav'
            AUDIO.write_pcm(generated, prepared, rate)
            runtime = root / 'Apps/ForestCabin/Resources/Audio/purr.wav'
            self.assertEqual(generated.read_bytes(), runtime.read_bytes(), '不能重新混入合成震动声')
        provenance = json.loads((runtime.parent / 'purr-source.json').read_text())
        self.assertEqual(provenance['source_sha256'], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(provenance['sha256'], hashlib.sha256(runtime.read_bytes()).hexdigest())
        self.assertEqual(provenance['license'], 'CC0-1.0')
    def test_one_shot_removes_dc_and_fades_without_clipping(self):
        rate = 44100
        original = [.4 + .25 * math.sin(2 * math.pi * 440 * i / rate) for i in range(rate)]
        prepared, _ = AUDIO.prepare(original, rate, False)
        metrics = AUDIO.statistics(prepared, rate)
        self.assertEqual(len(prepared), len(original))
        self.assertEqual(prepared[0], 0)
        self.assertEqual(prepared[-1], 0)
        self.assertLess(abs(metrics['dc_offset']), .001)
        self.assertAlmostEqual(metrics['rms'], .065, places=4)
        self.assertLessEqual(metrics['peak'], .4)
        self.assertEqual(original[0], .4, '处理不应修改原始样本')

    def test_nonperiodic_recording_can_form_a_continuous_quiet_loop(self):
        rate = 44100
        original = [.35 * math.sin(2 * math.pi * 27.3 * i / rate)
                    + .08 * math.sin(2 * math.pi * 113.7 * i / rate) for i in range(rate * 3)]
        self.assertGreater(abs(original[-1] - original[0]), .1)
        prepared, _ = AUDIO.prepare(original, rate, True)
        metrics = AUDIO.statistics(prepared, rate)
        self.assertLess(metrics['loop_boundary_step'], .002)
        self.assertAlmostEqual(metrics['rms'], .035, places=4)
        self.assertEqual(metrics['clipped_samples'], 0)
        self.assertGreater(metrics['duration_seconds'], 2)

    def test_silent_or_short_loop_is_rejected(self):
        with self.assertRaises(ValueError):
            AUDIO.prepare([0] * 44100, 44100, False)
        with self.assertRaises(ValueError):
            AUDIO.prepare([.1] * 100, 44100, True)

    def test_pcm_roundtrip_preserves_samples_and_rate(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'test.wav'
            expected = [-.4, -.1, 0, .1, .4]
            AUDIO.write_pcm(path, expected, 44100)
            actual, rate = AUDIO.read_pcm(path)
            self.assertEqual(rate, 44100)
            self.assertEqual(len(actual), len(expected))
            for source, decoded in zip(expected, actual):
                self.assertLessEqual(abs(source - decoded), 1 / 32768)


if __name__ == '__main__':
    unittest.main()
