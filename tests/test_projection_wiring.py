"""Static integration boundaries only; never creates AppKit or launches the GUI."""
import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ProjectionWiring(unittest.TestCase):
    def test_foundation_only(self):
        source=(ROOT/'native/Projection.swift').read_text()
        self.assertIn('import Foundation',source)
        for forbidden in ['import AppKit','Process(', 'FileManager', 'Data(contentsOf:', 'Date()']:
            self.assertNotIn(forbidden,source)
    def test_toggle_does_not_rebuild_or_query(self):
        source=(ROOT/'native/Views.swift').read_text()
        action=source.split('@objc private func toggleProjected')[1].split('    func show(')[0]
        for forbidden in ['show(', 'applyQuery', 'Process(', 'scroll(to:']:
            self.assertNotIn(forbidden,action)
        self.assertIn('private var projectedMode=false',source)
        show=source.split('    func show(_ p:Player?)')[1].split('final class RuleView')[0]
        self.assertNotIn('projectedMode=',show)
        self.assertIn('values:p.visibleAttributes,register:register',show)
        hidden=show.split('label("HIDDEN ATTRIBUTES")')[1]
        self.assertNotIn('register:register',hidden)
        self.assertNotIn('projection.',hidden)
    def test_existing_cache_inputs_only(self):
        source=(ROOT/'native/App.swift').read_text()
        self.assertIn('self.detail.projectionDate=snapshot.projectionDate',source)
        build=(ROOT/'build-app.sh').read_text()
        self.assertIn('native/Projection.swift',build)
        self.assertNotIn('research/',build)
        self.assertNotIn('projection-vectors',build)
if __name__=='__main__':unittest.main()
