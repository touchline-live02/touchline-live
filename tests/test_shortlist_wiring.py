"""Source boundaries only; never instantiates AppKit or launches Touchline."""
import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ShortlistWiring(unittest.TestCase):
    def test_one_browser(self):
        app=(ROOT/'native/App.swift').read_text()
        self.assertIn('offline,shortlistRow],spacing:12)',app)
        self.assertIn('context.delegate=self',app)
        self.assertIn('candidates:resolution?.rowIndices',app)
        self.assertIn('self.generation==token',app)
        self.assertIn('self.shortlistIndex=shortlistIndex',app)
        self.assertIn('self.detail.show(self.selectedPlayer())',app)
    def test_actions_do_not_capture(self):
        ui=(ROOT/'native/ShortlistUI.swift').read_text()
        for forbidden in ['refreshLive(', 'load(', 'Process(', 'DetailView(', 'NSTableView(']:
            self.assertNotIn(forbidden,ui)
        self.assertIn('showingShortlist=false',ui)
        self.assertIn('showingShortlist=true',ui)
        self.assertIn('resolution.removals(from:selection)',ui)
    def test_native_multiple_selection_and_context(self):
        app=(ROOT/'native/App.swift').read_text()
        self.assertIn('table.allowsMultipleSelection=true',app)
        self.assertIn('if !selectedRowIndexes.contains(row)',app)
        self.assertIn('restoredPlayerSelection(selectedUIDs,results:indices,rows:source)',app)
        ui=(ROOT/'native/ShortlistUI.swift').read_text()
        self.assertIn('table.selectedRowIndexes',ui)
        self.assertIn('Add Selected to Shortlist',ui)
        self.assertIn('Remove Selected from Shortlist',ui)
        self.assertIn('try shortlist.add(additions)',ui)
    def test_empty_state_is_in_body_viewport(self):
        app=(ROOT/'native/App.swift').read_text()
        views=(ROOT/'native/Views.swift').read_text()
        self.assertIn('split.addArrangedSubview(playerTableContainer)',app)
        self.assertNotIn('tableScroll.addSubview(emptyShortlist)',app)
        self.assertIn('addSubview(emptyLabel,positioned:.above,relativeTo:scrollView)',views)
        self.assertIn('scrollView.contentView.convert(scrollView.contentView.bounds,to:self).intersection(bounds)',views)
        self.assertIn('body.midY-height/2',views)
        self.assertIn('scrollView.tile()',views)
        self.assertNotIn('emptyShortlist.topAnchor.constraint(equalTo:tableScroll.topAnchor',app)
    def test_store_is_separate(self):
        store=(ROOT/'native/Shortlist.swift').read_text()
        for forbidden in ['AppKit','Process(', 'address:','Person.Id =']:
            self.assertNotIn(forbidden,store)
        build=(ROOT/'build-app.sh').read_text()
        self.assertIn('native/Shortlist.swift native/ShortlistUI.swift',build)
if __name__=='__main__':unittest.main()
