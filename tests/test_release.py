"""Publication membership, integrity and metadata checks; no process or desktop access."""
import importlib.util
import pathlib
import shutil
import struct
import sys
import tempfile
import unittest
import warnings
import zipfile

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('public_source', ROOT/'tools/public_source.py')
public_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(public_source)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = pathlib.Path(self.temporary.name)
        self.source = self.base/'source'
        # Unit fixtures intentionally contain only approved inputs; build outputs may
        # exist in the test checkout, but may never exist in a publication snapshot.
        for source in public_source.files():
            target = self.source/source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def tearDown(self):
        self.temporary.cleanup()

    def test_candidate_has_no_detected_personal_or_secret_patterns(self):
        self.assertEqual(public_source.scan(public_source.files()), [])

    def test_export_membership_and_integrity(self):
        target = self.base/'export'
        count = public_source.export(target, self.source)
        self.assertEqual(public_source.verify_export(target, self.source), count)
        paths = [p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()]
        self.assertTrue((target/'src/probe.cpp').exists())
        self.assertTrue((target/'docs/evidence/trait-labels.json').exists())
        self.assertFalse((target/'touchline-probe').exists())
        self.assertEqual(set(paths), set(public_source.snapshot(self.source)))
        with self.assertRaises(ValueError):
            public_source.export(target, self.source)

    def test_dirty_input_cannot_be_exported_or_archived(self):
        bad = self.source/'tools/__pycache__/anything.pyc'
        bad.parent.mkdir();bad.write_bytes(b'compiled private source path')
        with self.assertRaises(ValueError):
            public_source.export(self.base/'export', self.source)
        with self.assertRaises(ValueError):
            public_source.package(self.base/'source.zip', self.source)
        self.assertFalse((self.base/'source.zip').exists())

    def test_dirty_export_fails_even_if_git_would_ignore_it(self):
        target = self.base/'export';public_source.export(target, self.source)
        bad = target/'tools/__pycache__/anything.pyc'
        bad.parent.mkdir();bad.write_bytes(b'compiled private source path')
        with self.assertRaises(ValueError):
            public_source.verify_export(target, self.source)

    def test_modified_file_or_manifest_fails_verification(self):
        target = self.base/'export';public_source.export(target, self.source)
        (target/'README.md').write_text('changed after export')
        with self.assertRaises(ValueError):
            public_source.verify_export(target, self.source)
        archive = self.base/'source.zip';public_source.package(archive, self.source)
        with zipfile.ZipFile(archive, 'a') as z:
            z.writestr('tools/__pycache__/anything.pyc', b'not approved')
        with self.assertRaises(ValueError):
            public_source.verify_archive(archive, self.source)

    def test_archive_has_exact_members_and_normalized_metadata(self):
        archive = self.base/'source.zip'
        count = public_source.package(archive, self.source)
        self.assertEqual(public_source.verify_archive(archive, self.source), count)
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(set(z.namelist()), set(public_source.snapshot(self.source)))
            self.assertEqual(z.comment, b'')
            self.assertTrue(all(not p.extra and not p.comment and p.date_time == public_source.ZIP_TIME
                                for p in z.infolist()))
            self.assertFalse(any('__pycache__' in p or p.endswith('.pyc') for p in z.namelist()))

    def test_archive_rejects_metadata(self):
        archive = self.base/'source.zip';public_source.package(archive, self.source)
        with zipfile.ZipFile(archive, 'a') as z:
            z.comment = b'unapproved metadata'
        with self.assertRaises(ValueError):
            public_source.verify_archive(archive, self.source)

    def test_archive_rejects_duplicate_member(self):
        archive = self.base/'source.zip';public_source.package(archive, self.source)
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(archive, 'a') as z:
                z.writestr('README.md', (self.source/'README.md').read_bytes())
        with self.assertRaises(ValueError):
            public_source.verify_archive(archive, self.source)

    def test_required_license_is_included_in_archive_and_manifest(self):
        archive = self.base/'source.zip';public_source.package(archive, self.source)
        with zipfile.ZipFile(archive) as z:
            self.assertIn('LICENSE', z.namelist())
            self.assertEqual(z.read('LICENSE'), (ROOT/'LICENSE').read_bytes())
            self.assertIn('  LICENSE\n', z.read(public_source.MANIFEST).decode())

    def test_missing_license_cannot_be_exported_or_archived(self):
        (self.source/'LICENSE').unlink()
        with self.assertRaisesRegex(ValueError, 'LICENSE'):
            public_source.validate_tree(self.source)
        with self.assertRaisesRegex(ValueError, 'LICENSE'):
            public_source.export(self.base/'export', self.source)
        with self.assertRaisesRegex(ValueError, 'LICENSE'):
            public_source.package(self.base/'source.zip', self.source)
        self.assertFalse((self.base/'export').exists())
        self.assertFalse((self.base/'source.zip').exists())

    def test_license_cannot_be_omitted_from_allowlist(self):
        listing = self.source/public_source.FILE_LIST
        listing.write_text('\n'.join(line for line in listing.read_text().splitlines() if line != 'LICENSE')+'\n')
        with self.assertRaisesRegex(ValueError, 'LICENSE'):
            public_source.snapshot(self.source)

    def test_symlinks_and_output_inside_source_are_rejected(self):
        readme = self.source/'README.md';readme.unlink();readme.symlink_to(ROOT/'README.md')
        with self.assertRaises(ValueError):
            public_source.snapshot(self.source)
        readme.unlink();readme.write_bytes((ROOT/'README.md').read_bytes())
        with self.assertRaises(ValueError):
            public_source.package(self.source/'artifact.zip', self.source)

    def test_personal_path_detection_without_echoing_contents(self):
        path = self.base/'fixture.txt'
        path.write_bytes(b'/'+b'Users/'+b'fixture-owner/private-file')
        self.assertEqual(public_source.scan([path], self.base), [('fixture.txt', 'personal home path')])

    def test_icon_source_has_no_nonvisual_provenance_metadata(self):
        data = (ROOT/'assets/TouchlineLive.png').read_bytes();offset = 8;kinds = []
        while offset < len(data):
            size = struct.unpack_from('>I', data, offset)[0]
            kinds.append(data[offset+4:offset+8]);offset += size+12
        self.assertTrue(b'IHDR' in kinds and b'IDAT' in kinds and b'IEND' in kinds)
        self.assertFalse(set(kinds) & {b'caBX', b'eXIf', b'tEXt', b'zTXt', b'iTXt'})
