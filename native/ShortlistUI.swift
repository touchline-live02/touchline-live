import AppKit

/// Navigation and persistence actions reuse the existing browser and query worker.
extension AppDelegate:NSMenuDelegate {
    @objc func showPlayers() {
        showingShortlist=false;updateShortlistNavigation();applyQuery();focusSearch()
    }
    @objc func showShortlist() {
        showingShortlist=true;updateShortlistNavigation();applyQuery()
    }
    func updateShortlistNavigation() {
        browserTitle.stringValue=showingShortlist ? "Shortlist" : "Players"
        shortlistButton.title="  Shortlist · \(shortlist.entries.count.formatted())"
        for (view,selected) in [(playersNavigation,!showingShortlist),(shortlistNavigation,showingShortlist)] {
            view?.layer?.backgroundColor=(selected ? NSColor(calibratedWhite:0.25,alpha:1) : .clear).cgColor
            view?.layer?.borderWidth=selected ? 0.5 : 0
        }
    }
    func selectedSourceRowIndices()->IndexSet {
        selectedSourceRows(table.selectedRowIndexes,visible:visible).intersection(IndexSet(rows.indices))
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        let selection=selectedSourceRowIndices()
        let resolution=shortlistIndex.resolve(shortlist.entries)
        let multiple=selection.count>1
        for (action,title,available) in [
            (#selector(addSelectedToShortlist),multiple ? "Add Selected to Shortlist" : "Add to Shortlist",!resolution.additions(from:selection).isEmpty),
            (#selector(removeSelectedFromShortlist),multiple ? "Remove Selected from Shortlist" : "Remove from Shortlist",!resolution.removals(from:selection).isEmpty)
        ] {
            guard let item=menu.items.first(where:{$0.action==action}) else {continue}
            item.title=title;item.isHidden = !available
            item.isEnabled=available && shortlist.loadError == nil
        }
    }
    @objc func addSelectedToShortlist() {changeSelectedShortlist(adding:true)}
    @objc func removeSelectedFromShortlist() {changeSelectedShortlist(adding:false)}
    private func changeSelectedShortlist(adding:Bool) {
        let selection=selectedSourceRowIndices()
        guard !selection.isEmpty else {return}
        let resolution=shortlistIndex.resolve(shortlist.entries)
        do {
            if adding {
                let additions=resolution.additions(from:selection).map {ShortlistEntry(rows[$0].player)}
                try shortlist.add(additions)
            } else {try shortlist.remove(entryIndices:resolution.removals(from:selection))}
            updateShortlistNavigation()
            if showingShortlist {applyQuery()}
        } catch {
            status.stringValue="Could not save shortlist: "+error.localizedDescription
        }
    }
    func updateBrowserSummary(results:Int,total:Int,unresolved:Int) {
        playerTableContainer.positionEmptyLabel()
        emptyShortlist.isHidden = !showingShortlist || results>0
        if showingShortlist {
            count.stringValue="\(results.formatted()) of \(total.formatted()) shortlisted players"
            if unresolved>0 {count.stringValue+=" · \(unresolved.formatted()) not in this cache"}
            emptyShortlist.stringValue=shortlist.entries.isEmpty ? "No players shortlisted" :
                (total==0 ? "No shortlisted players in this cache" : "No shortlisted players match these filters")
        } else {count.stringValue="\(results.formatted()) of \(total.formatted()) players"}
        guard !busy && !loading else {return}
        if let error=shortlist.loadError {status.stringValue="Could not open shortlist: "+error}
        else if showingShortlist && shortlist.entries.isEmpty {status.stringValue="Add players from the Players table with right-click → Add to Shortlist."}
        else if showingShortlist && total==0 {status.stringValue="Saved shortlist entries are retained. Open a matching cache to browse them."}
        else {status.stringValue=results==0 ? "No players match these filters. Clear or adjust the conditions." : "Browsing locally · FM24 detached"}
    }
}
