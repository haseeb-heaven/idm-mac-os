#!/usr/bin/env python3
"""Verify real loopback fixture downloads without reverse DNS availability."""
import hashlib
from pathlib import Path
import selectors
import socket
import subprocess
import sys
import unittest
from unittest.mock import patch
from urllib.request import urlopen

from browser_fixture import Fixture, SHA256

ROOT = Path(__file__).resolve().parent.parent


class FixtureStartupChecks(unittest.TestCase):
    def test_browser_fixture_does_not_reverse_resolve(self):
        with patch.object(socket, 'getfqdn', side_effect=AssertionError('Unexpected reverse DNS')):
            with Fixture() as fixture:
                with urlopen(fixture.url + '/file.bin', timeout=5) as response:
                    self.assertEqual(hashlib.sha256(response.read()).hexdigest(), SHA256)

    def test_core_fixture_does_not_reverse_resolve(self):
        command = "import socket,runpy;socket.getfqdn=lambda *a: (_ for _ in ()).throw(AssertionError('Unexpected reverse DNS'));runpy.run_path('scripts/http_fixture.py',run_name='__main__')"
        process = subprocess.Popen([sys.executable, '-c', command], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                self.assertTrue(selector.select(5), 'Fixture startup exceeded 5 seconds')
                port = int(process.stdout.readline())
            with urlopen(f'http://127.0.0.1:{port}/file', timeout=5) as response:
                self.assertEqual(hashlib.sha256(response.read()).hexdigest(), SHA256)
        finally:
            process.terminate()
            process.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main()
