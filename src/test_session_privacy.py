"""Private transport cleanup; no helper, process attachment, or real memory reads."""
import pathlib
import tempfile
import unittest
from unittest.mock import patch
from touchline_live import Session, authorization_script

class SessionPrivacyTests(unittest.TestCase):
    def test_authorization_retains_unicode_and_escapes_quotes(self):
        script=authorization_script('"/portable/é helper" \'single quoted\'')
        self.assertIn('é helper',script)
        self.assertNotIn('\\u00e9',script)
        self.assertIn('\\"',script)
        self.assertTrue(script.endswith(' with administrator privileges'))
    def test_consumed_success_response_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            response=pathlib.Path(directory)/'response-123.txt'
            response.write_text('REQUEST 123 batch\nREAD 1000 1 00\nMETRICS 1 1 0.01\n')
            with patch('touchline_live.time.time_ns',return_value=123):
                session=Session(directory);lines=session.request('batch 1000 1')
            self.assertIn('READ 1000 1 00',lines)
            self.assertFalse(response.exists())
            self.assertEqual((session.bytes,session.calls),(1,1))
    def test_rejected_response_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            response=pathlib.Path(directory)/'response-123.txt';response.write_text('ERROR read budget\n')
            with patch('touchline_live.time.time_ns',return_value=123),self.assertRaises(RuntimeError):
                Session(directory).request('batch 1000 1')
            self.assertFalse(response.exists())
