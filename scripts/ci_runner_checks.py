#!/usr/bin/env python3
"""Regression checks for bounded CI command execution and process cleanup."""
import contextlib
import io
import signal
import subprocess
import sys
import time
import unittest
from unittest.mock import Mock, call, patch

import ci_checks


class CIRunnerChecks(unittest.TestCase):
    def execute_silently(self, command, timeout):
        with contextlib.redirect_stdout(io.StringIO()):
            return ci_checks.execute(command, timeout)

    def test_successful_command_returns(self):
        self.assertIsNone(self.execute_silently([sys.executable, '-c', 'pass'], 5))

    def test_command_failure_preserves_exit_code(self):
        with self.assertRaises(SystemExit) as result:
            self.execute_silently([sys.executable, '-c', 'raise SystemExit(7)'], 5)
        self.assertEqual(result.exception.code, 7)

    def test_real_timeout_terminates_and_reaps_subprocess(self):
        original_popen = subprocess.Popen
        children = []

        def record_process(*args, **kwargs):
            process = original_popen(*args, **kwargs)
            children.append(process)
            return process

        started = time.monotonic()
        try:
            with patch.object(ci_checks.subprocess, 'Popen', side_effect=record_process):
                with self.assertRaises(SystemExit) as result:
                    self.execute_silently([sys.executable, '-c', 'import time; time.sleep(30)'], .1)
            self.assertEqual(result.exception.code, 124)
            self.assertLess(time.monotonic() - started, 3)
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0].returncode, -signal.SIGTERM)
            self.assertEqual(children[0].poll(), -signal.SIGTERM)
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=5)

    def test_timeout_uses_sigterm_process_group_and_reaps(self):
        process = Mock(pid=123456)
        process.wait.side_effect = [subprocess.TimeoutExpired('fixture', 1), -signal.SIGTERM]
        with patch.object(ci_checks.subprocess, 'Popen', return_value=process) as popen:
            with patch.object(ci_checks.os, 'killpg') as killpg:
                with self.assertRaises(SystemExit) as result:
                    self.execute_silently(['fixture'], 1)
        self.assertEqual(result.exception.code, 124)
        popen.assert_called_once_with(['fixture'], cwd=ci_checks.ROOT, start_new_session=True)
        killpg.assert_called_once_with(process.pid, signal.SIGTERM)
        self.assertEqual(process.wait.call_args_list, [call(timeout=1), call(timeout=5)])

    def test_unresponsive_group_gets_sigkill_then_reaped(self):
        process = Mock(pid=123456)
        process.wait.side_effect = [subprocess.TimeoutExpired('fixture', 1),
                                    subprocess.TimeoutExpired('fixture', 5), -signal.SIGKILL]
        with patch.object(ci_checks.subprocess, 'Popen', return_value=process):
            with patch.object(ci_checks.os, 'killpg') as killpg:
                with self.assertRaises(SystemExit) as result:
                    self.execute_silently(['fixture'], 1)
        self.assertEqual(result.exception.code, 124)
        self.assertEqual(killpg.call_args_list,
                         [call(process.pid, signal.SIGTERM), call(process.pid, signal.SIGKILL)])
        self.assertEqual(process.wait.call_args_list, [call(timeout=1), call(timeout=5), call()])


if __name__ == '__main__':
    unittest.main()
