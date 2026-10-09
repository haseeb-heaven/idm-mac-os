#!/usr/bin/env python3
"""Reject Blob staging bytes and downloads without durable completed job evidence."""
import json
from pathlib import Path
import tempfile
import unittest
from browser_fixture import PAYLOAD
from browser_integration_tests import matching_final_files, wait_files

class CompletedDownloadChecks(unittest.TestCase):
    def test_staging_and_unfinished_final_bytes_never_pass(self):
        with tempfile.TemporaryDirectory(prefix='mdm-browser-helper-') as temporary:
            qa=Path(temporary);downloads=qa/'downloads';downloads.mkdir()
            staging=downloads/'.mdm-blob-test';staging.write_bytes(PAYLOAD)
            (qa/'jobs.json').write_text(json.dumps([{'destination':str(staging),'state':'completed'}]))
            self.assertEqual(matching_final_files(downloads,set()),[])
            final=downloads/'file.bin';final.write_bytes(PAYLOAD)
            (qa/'jobs.json').write_text(json.dumps([{'destination':str(final),'state':'downloading'}]))
            self.assertEqual(matching_final_files(downloads,set()),[])
            with self.assertRaises(TimeoutError):wait_files(downloads,set(),1,timeout=0)
            (qa/'jobs.json').write_text(json.dumps([{'destination':str(final),'state':'completed'}]))
            self.assertEqual(wait_files(downloads,set(),1,timeout=0),[final])
            self.assertEqual(matching_final_files(downloads,{final}),[])
            final.unlink()
            self.assertEqual(matching_final_files(downloads,set()),[])

if __name__=='__main__':unittest.main()
