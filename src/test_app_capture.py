"""Offline native-app lifecycle tests; no authorization or live process access."""
import contextlib
import hashlib
import io
import json
import pathlib
import signal
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import touchline_live as reader

class AppCaptureTests(unittest.TestCase):
    def scenario(self,mode,use_default=False):
        with tempfile.TemporaryDirectory() as root:
            root=pathlib.Path(root);exe=root/'Football Manager 2024/fm.app/Contents/MacOS/fm';exe.parent.mkdir(parents=True);exe.write_bytes(b'test build')
            directory=root/'session';output=root/'app-data/latest' if use_default else root/'latest';output.mkdir(parents=True);target=output/'players.json';target.write_text('{"old":true}')
            calls=[];handlers={};snapshot={'players':[], 'collection':{'count':0},'elapsedSeconds':0.1}
            def authorize(*args,**kwargs):
                directory.mkdir();(directory/'ready.txt').write_text('read_only true')
                if mode=='cancel':handlers[signal.SIGINT](signal.SIGINT,None)
            class FakeSession:
                def __init__(self,path):pass
                def request(self,command):
                    calls.append(command)
                    self_old=json.loads(target.read_text())
                    if self_old!={'old':True}:raise AssertionError('Cache published before detach')
                    return ['BYE'] if mode!='bad_detach' else ['ERROR']
            def capture(session,progress):
                progress('Reading player collection',0.18)
                if mode=='failure':raise RuntimeError('Unreadable collection')
                return SimpleNamespace(snapshot=lambda:snapshot)
            stdout=io.StringIO();code=0
            with contextlib.ExitStack() as stack:
                arguments=['reader','--progress-json'] if use_default else ['reader','--output',str(output),'--progress-json']
                for p in [patch.object(sys,'argv',arguments),patch.object(reader,'PROJECT',root),
                          patch.object(reader,'SHA256',hashlib.sha256(b'test build').hexdigest()),
                          patch.object(reader.subprocess,'check_output',return_value='' if mode=='no_fm' else f'123 {exe}\n'),
                          patch.object(reader.subprocess,'run',side_effect=authorize),
                          patch.object(reader.tempfile,'mkdtemp',return_value=str(directory)),
                          patch.object(reader,'Session',FakeSession),patch.object(reader,'capture_cache',side_effect=capture),
                          patch.object(signal,'signal',side_effect=lambda sig,handler:handlers.update({sig:handler})),
                          contextlib.redirect_stdout(stdout)]:stack.enter_context(p)
                try:reader.main()
                except SystemExit as error:code=error.code
            if mode=='success':
                self.assertEqual({p.name for p in output.iterdir()}, {'players.json','summary.json'})
            return code,calls,json.loads(target.read_text()),[json.loads(line) for line in stdout.getvalue().splitlines()]
    def test_detaches_before_cache_publication(self):
        code,calls,cache,events=self.scenario('success')
        self.assertEqual(code,0);self.assertEqual(calls,['quit']);self.assertIn('players',cache)
        self.assertLess(next(i for i,e in enumerate(events) if e['event']=='detached'),next(i for i,e in enumerate(events) if e.get('message')=='Saving the local player cache'))
    def test_default_output_uses_current_cache_location_without_html(self):
        code,calls,cache,events=self.scenario('success',use_default=True)
        self.assertEqual(code,0);self.assertEqual(calls,['quit']);self.assertIn('players',cache)
        self.assertTrue(events[-1]['path'].endswith('/app-data/latest/players.json'))
    def test_capture_failure_detaches_and_preserves_cache(self):
        code,calls,cache,events=self.scenario('failure')
        self.assertEqual(code,1);self.assertEqual(calls,['quit']);self.assertEqual(cache,{'old':True})
    def test_bad_detach_does_not_publish(self):
        code,calls,cache,events=self.scenario('bad_detach')
        self.assertEqual(code,1);self.assertEqual(cache,{'old':True})
    def test_cancellation_after_authorization_still_detaches(self):
        code,calls,cache,events=self.scenario('cancel')
        self.assertEqual(code,130);self.assertEqual(calls,['quit']);self.assertEqual(cache,{'old':True})
    def test_missing_fm_keeps_offline_cache(self):
        code,calls,cache,events=self.scenario('no_fm')
        self.assertEqual(code,1);self.assertEqual(calls,[]);self.assertEqual(cache,{'old':True})
        self.assertIn('FM24 is not running',events[-1]['message'])

if __name__=='__main__':unittest.main()
