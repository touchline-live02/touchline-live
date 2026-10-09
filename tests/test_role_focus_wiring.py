"""Presentation boundaries checked without creating AppKit or launching the app."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class RoleFocusWiring(unittest.TestCase):
    def test_selection_is_session_state(self):
        source=(ROOT/'native/Views.swift').read_text()
        self.assertIn('private var roleFocus=RoleFocusState()',source)
        show=source.split('    func show(_ p:Player?)')[1].split('final class RuleView')[0]
        self.assertNotIn('roleFocus=',show)
        self.assertIn('RoleFocusButton(focus:roleFocus)',show)
        self.assertIn('self?.roleFocus.select(id);self?.updateRoleHighlights()',show)
        self.assertIn('updateProjectedValues();updateRoleHighlights()',show)
    def test_independent_in_place_updates(self):
        source=(ROOT/'native/Views.swift').read_text()
        role=source.split('private func updateRoleHighlights()')[1].split('private func updateProjectedValues()')[0]
        projected=source.split('private func updateProjectedValues()')[1].split('    func show(')[0]
        self.assertNotIn('project',role)
        self.assertNotIn('roleFocus',projected)
        for code in [role,projected]:
            for forbidden in ['show(', 'applyQuery', 'Process(', 'capture(', 'scroll(to:']:
                self.assertNotIn(forbidden,code)
    def test_only_visible_rows_registered(self):
        source=(ROOT/'native/Views.swift').read_text()
        show=source.split('    func show(_ p:Player?)')[1].split('final class RuleView')[0]
        self.assertEqual(show.count('registerRole:registerRole'),5)
        self.assertNotIn('registerRole:',show.split('label("HIDDEN ATTRIBUTES")')[1])
        self.assertIn('traits.topAnchor.constraint(equalTo:physicalColumn.bottomAnchor,constant:AttributeGeometry.traitsGap)',show)
    def test_native_menu_and_semantic_colours(self):
        source=(ROOT/'native/RoleFocusControl.swift').read_text()
        self.assertIn('menu.popUp(positioning:nil',source)
        self.assertIn('RoleFocusCatalog.groups',source)
        self.assertIn('roleItem.submenu=duties',source)
        self.assertIn('Clear Role Focus',source)
        self.assertNotIn('Palette.accent',source)
        self.assertNotIn('textColor=',source)
        self.assertNotIn('NSWindow',source)
    def test_pure_catalog_and_normal_build(self):
        source=(ROOT/'native/RoleFocus.swift').read_text()
        for forbidden in ['AppKit','Process(', 'FileManager', 'Data(contentsOf:', 'PlayerProjection']:
            self.assertNotIn(forbidden,source)
        build=(ROOT/'build-app.sh').read_text()
        for file in ['native/RoleFocus.swift','native/RoleFocusControl.swift']:
            self.assertIn(file,build)
if __name__=='__main__': unittest.main()
