"""Release artifacts must install the same flash layout as the shipping build."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GENERATOR = Path(__file__).resolve().parents[1] / 'tools/generate_release_manifests.py'


class ReleaseManifestTests(unittest.TestCase):
    def test_s3_install_and_ota_artifacts_agree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            build, out = root / 'build', root / 'release'
            build.mkdir()
            for name in ('firmware', 'bootloader', 'partitions', 'boot_app0'):
                (build / (name + '.bin')).write_bytes(name.encode())
            subprocess.run([sys.executable, str(GENERATOR), '--version', 'v1.2.3',
                            '--base-url', 'https://example.invalid/firmware/',
                            '--build-dir', str(build), '--boot-app0', str(build / 'boot_app0.bin'),
                            '--out-dir', str(out)], check=True, capture_output=True)
            ota = json.loads((out / 'manifest.json').read_text())
            web = json.loads((out / 'esp-web-tools-manifest.json').read_text())
            self.assertEqual(ota['version'], web['version'])
            self.assertEqual(ota['board'], 'ws-amoled164')
            self.assertEqual(ota['sha256'], hashlib.sha256(b'firmware').hexdigest())
            self.assertEqual(web['builds'][0]['chipFamily'], 'ESP32-S3')
            parts = web['builds'][0]['parts']
            self.assertEqual([p['offset'] for p in parts], [0, 0x8000, 0xe000, 0x10000])
            for part, expected in zip(parts, (b'bootloader', b'partitions', b'boot_app0', b'firmware')):
                self.assertEqual((out / part['path'].rsplit('/', 1)[1]).read_bytes(), expected)
            self.assertEqual(parts[-1]['path'], ota['url'])


if __name__ == '__main__':
    unittest.main()
