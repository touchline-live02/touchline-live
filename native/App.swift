import AppKit

final class ScoutingRow:NSTableRowView {
    override func drawSelection(in dirtyRect:NSRect) {
        NSColor.selectedContentBackgroundColor.setFill();bounds.fill()
    }
}

final class ScoutingTable:NSTableView {
    override func menu(for event:NSEvent) -> NSMenu? {
        let row=row(at:convert(event.locationInWindow,from:nil))
        if row>=0 {
            if !selectedRowIndexes.contains(row) {selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            return menu
        }
        return nil
    }
}
final class AppDelegate:NSObject,NSApplicationDelegate,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate,NSWindowDelegate,NSSplitViewDelegate {
    var window:NSWindow!
    private var settingsController:SettingsWindowController?
    let table=ScoutingTable();let detail=DetailView(frame:.zero)
    let playerFaces=PlayerFaceService()
    let shortlist=ShortlistStore(url:ShortlistStore.defaultURL)
    var shortlistIndex=ShortlistIndex([])
    var showingShortlist=false
    let shortlistButton=NSButton()
    var playersNavigation:NSView?;var shortlistNavigation:NSView?
    let browserTitle=text("Players",size:25,weight:.bold)
    let playerTableContainer=PlayerTableContainer(frame:.zero)
    var emptyShortlist:NSTextField {playerTableContainer.emptyLabel}
    let search=NSSearchField();let clubSearch=NSSearchField()
    let position=NSPopUpButton();let employment=NSPopUpButton();let nationality=NSPopUpButton()
    let ageMin=NSTextField();let ageMax=NSTextField()
    let caMin=NSTextField();let caMax=NSTextField();let paMin=NSTextField();let paMax=NSTextField()
    let wageMin=NSTextField();let wageMax=NSTextField();let expiryAfter=NSTextField();let expiryBefore=NSTextField()
    var filterEditor=FilterEditor()
    var filterControls:[FilterField:[NSControl]]=[:]
    let filterContent=NSView()
    let showResults=NSButton()
    var queryPending=false
    let currencyPicker=NSPopUpButton()
    var currencies:[DisplayCurrency]=[]
    var selectedCurrency:DisplayCurrency?
    let refresh=NSButton();let offline=NSButton();let filterToggle=NSButton()
    let status=text("Opening the latest cache…",size:12,color:Palette.muted)
    let timestamp=text("No capture loaded",size:11,color:Palette.muted)
    let count=text("",size:12,weight:.medium)
    let filterMessage=text("",size:10,color:.systemYellow,wrap:true)
    let progress=NSProgressIndicator()
    let ruleStack=NSStackView();var ruleViews:[RuleView]=[]
    private let dividerPreference="TouchlinePlayerProfileDividerPosition"
    private var dividerRestored=false
    let split=NSSplitView();let filterPane=NSScrollView();let filterPopover=NSPopover()
    var rows:[Row]=[];var visible:[Int]=[]
    var query=Query();var sort=SortSpec();var generation=0;var pending:DispatchWorkItem?
    let worker=DispatchQueue(label:"Touchline.local-cache",qos:.userInitiated)
    var process:Process?;var busy=false;var loading=false;var quitting=false;var detached=false;var captureError:String?
    let folder=Bundle.main.bundleURL.deletingLastPathComponent()
    var dataFolder:URL {folder.appendingPathComponent("app-data",isDirectory:true)}
    var latest:URL {dataFolder.appendingPathComponent("latest/players.json")}
    var legacyCache:URL {folder.appendingPathComponent("checkpoint-phase3/players.json")}
    var cachePath:URL {FileManager.default.fileExists(atPath:latest.path) ? latest : legacyCache}

    func applicationDidFinishLaunching(_ notification:Notification){
        NSApp.appearance=NSAppearance(named:.darkAqua);NSApp.setActivationPolicy(.regular)
        buildMenu();buildWindow();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        window.contentView?.layoutSubtreeIfNeeded()
        let saved=(UserDefaults.standard.object(forKey:dividerPreference) as? NSNumber)?.doubleValue
        let position=saved.flatMap {$0.isFinite && $0>0 ? CGFloat($0) : nil} ?? max(395,split.bounds.width*0.40)
        split.setPosition(position,ofDividerAt:0)
        dividerRestored=true
        load(cachePath)
    }
    func buildMenu(){
        let menu=NSMenu();let appItem=NSMenuItem();let app=NSMenu();appItem.submenu=app;menu.addItem(appItem)
        app.addItem(withTitle:"About Touchline Live",action:#selector(about),keyEquivalent:"").target=self
        app.addItem(withTitle:"Settings…",action:#selector(showSettings),keyEquivalent:",").target=self
        app.addItem(.separator());app.addItem(withTitle:"Quit Touchline Live",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let fileItem=NSMenuItem();let file=NSMenu(title:"File");fileItem.submenu=file;menu.addItem(fileItem)
        file.addItem(withTitle:"Refresh Live Data",action:#selector(refreshLive),keyEquivalent:"r").target=self
        file.addItem(withTitle:"Open Latest Cache",action:#selector(openLatest),keyEquivalent:"o").target=self
        let editItem=NSMenuItem();let edit=NSMenu(title:"Edit");editItem.submenu=edit;menu.addItem(editItem)
        for (name,selector,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {edit.addItem(withTitle:name,action:selector,keyEquivalent:key)}
        edit.addItem(.separator());edit.addItem(withTitle:"Find Player",action:#selector(focusSearch),keyEquivalent:"f").target=self
        let viewItem=NSMenuItem();let view=NSMenu(title:"View");viewItem.submenu=view;menu.addItem(viewItem)
        view.addItem(withTitle:"Toggle Filters",action:#selector(toggleFilters),keyEquivalent:"\\").target=self
        NSApp.mainMenu=menu
    }
    func buildWindow(){
        detail.playerFaces=playerFaces
        let frame=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1600,height:1000)
        window=NSWindow(contentRect:NSRect(x:frame.minX+20,y:frame.minY+20,width:min(1640,frame.width-40),height:min(1040,frame.height-40)),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Touchline Live";window.minSize=NSSize(width:1220,height:740);window.delegate=self;window.setFrameAutosaveName("TouchlineLiveMain")
        window.backgroundColor=Palette.background;window.titlebarAppearsTransparent=true
        let root=NSView();root.wantsLayer=true;root.layer?.backgroundColor=Palette.background.cgColor;window.contentView=root
        let sidebar=Surface(NSColor(srgbRed:0.075,green:0.075,blue:0.075,alpha:1),radius:0)
        let work=NSView();work.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(sidebar);root.addSubview(work)
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo:root.leadingAnchor),sidebar.topAnchor.constraint(equalTo:root.topAnchor),sidebar.bottomAnchor.constraint(equalTo:root.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant:192),work.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),work.trailingAnchor.constraint(equalTo:root.trailingAnchor),work.topAnchor.constraint(equalTo:root.topAnchor),work.bottomAnchor.constraint(equalTo:root.bottomAnchor)])
        let brand=stack([text("Touchline",size:15,weight:.bold),text("FM24 · Live scouting",size:10,color:Palette.muted)],spacing:4)
        let symbol=NSImageView(image:NSImage(systemSymbolName:"sportscourt",accessibilityDescription:nil)!);Palette.followAccent(symbol);symbol.widthAnchor.constraint(equalToConstant:24).isActive=true
        let branding=stack([symbol,brand],vertical:false,spacing:10)
        let players=NSButton(title:"  Players",target:self,action:#selector(showPlayers));players.image=NSImage(systemSymbolName:"person.3",accessibilityDescription:nil);players.imagePosition = .imageLeading;players.isBordered=false;players.alignment = .left
        let selected=padded(players,inset:5,color:NSColor(calibratedWhite:0.25,alpha:1));selected.heightAnchor.constraint(equalToConstant:30).isActive=true
        playersNavigation=selected
        shortlistButton.target=self;shortlistButton.action=#selector(showShortlist)
        shortlistButton.image=NSImage(systemSymbolName:"star",accessibilityDescription:nil)
        shortlistButton.imagePosition = .imageLeading;shortlistButton.isBordered=false;shortlistButton.alignment = .left
        let shortlistRow=padded(shortlistButton,inset:5,color:.clear)
        shortlistRow.heightAnchor.constraint(equalToConstant:30).isActive=true
        shortlistNavigation=shortlistRow;updateShortlistNavigation()
        offline.title="  Open latest cache";offline.image=NSImage(systemSymbolName:"folder",accessibilityDescription:nil);offline.imagePosition = .imageLeading;offline.isBordered=false;offline.alignment = .left;offline.target=self;offline.action=#selector(openLatest)
        currencyPicker.controlSize = .regular;currencyPicker.font = .systemFont(ofSize:13)
        currencyPicker.target=self;currencyPicker.action=#selector(changeCurrency)
        currencyPicker.setAccessibilityLabel("Display currency");currencyPicker.addItem(withTitle:"Base units");currencyPicker.isEnabled=false
        let nav=stack([branding,text("TOUCHLINE",size:10,weight:.semibold,color:Palette.muted),selected,text("WORKSPACE",size:10,weight:.semibold,color:Palette.muted),offline,shortlistRow],spacing:12)
        [selected,offline,shortlistRow].forEach {fillWidth($0,nav)}
        let privacy=stack([text("Read-only live memory",size:10,weight:.medium),text("Your data stays on this Mac.",size:10,color:Palette.muted),text("Browse offline after capture.",size:10,color:Palette.muted)],spacing:7)
        let settings=NSButton(title:"  Settings",target:self,action:#selector(showSettings))
        settings.image=NSImage(systemSymbolName:"gearshape",accessibilityDescription:nil);settings.imagePosition = .imageLeading
        settings.isBordered=false;settings.alignment = .left;settings.font = .systemFont(ofSize:12,weight:.semibold)
        settings.setAccessibilityLabel("Settings")
        let bottom=stack([settings,privacy],spacing:18);fillWidth(settings,bottom);fillWidth(privacy,bottom)
        sidebar.addSubview(nav);sidebar.addSubview(bottom)
        NSLayoutConstraint.activate([nav.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:34),nav.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:14),nav.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-14),bottom.leadingAnchor.constraint(equalTo:nav.leadingAnchor),bottom.trailingAnchor.constraint(equalTo:nav.trailingAnchor),bottom.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-22),bottom.topAnchor.constraint(greaterThanOrEqualTo:nav.bottomAnchor,constant:24)])
        let pitch=SidebarPitchView(frame:.zero)
        sidebar.addSubview(pitch,positioned:.below,relativeTo:nav)
        NSLayoutConstraint.activate([
            pitch.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor),
            pitch.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor),
            pitch.topAnchor.constraint(equalTo:nav.bottomAnchor,constant:12),
            pitch.bottomAnchor.constraint(equalTo:bottom.topAnchor,constant:-12)
        ])
        buildFilters()
        let controller=NSViewController();controller.view=filterContent;controller.preferredContentSize=NSSize(width:760,height:650)
        filterPopover.contentViewController=controller;filterPopover.behavior = .transient;filterPopover.contentSize=NSSize(width:760,height:650)
        refresh.title="Refresh Live Data";refresh.image=NSImage(systemSymbolName:"waveform.path.ecg",accessibilityDescription:nil);refresh.imagePosition = .imageLeading;refresh.bezelStyle = .rounded;refresh.controlSize = .small;refresh.target=self;refresh.action=#selector(refreshLive);Palette.followAccent(refresh)
        let titleRow=NSView();titleRow.translatesAutoresizingMaskIntoConstraints=false
        let title=browserTitle;count.font = .systemFont(ofSize:11);count.textColor=Palette.muted
        let titleStack=stack([title,count],spacing:5);titleRow.addSubview(titleStack);titleRow.addSubview(refresh);refresh.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([titleStack.leadingAnchor.constraint(equalTo:titleRow.leadingAnchor),titleStack.topAnchor.constraint(equalTo:titleRow.topAnchor),titleStack.bottomAnchor.constraint(equalTo:titleRow.bottomAnchor),refresh.trailingAnchor.constraint(equalTo:titleRow.trailingAnchor),refresh.centerYAnchor.constraint(equalTo:titleRow.centerYAnchor)])
        search.placeholderString="Search player names";search.delegate=self;search.sendsSearchStringImmediately=true;search.setAccessibilityLabel("Search player names");search.font = .systemFont(ofSize:12);search.heightAnchor.constraint(equalToConstant:30).isActive=true
        filterToggle.title="More filters";filterToggle.image=NSImage(systemSymbolName:"line.3.horizontal.decrease",accessibilityDescription:nil);filterToggle.imagePosition = .imageLeading;filterToggle.bezelStyle = .rounded;filterToggle.controlSize = .small;filterToggle.target=self;filterToggle.action=#selector(toggleFilters)
        caMin.placeholderString="Any";paMin.placeholderString="Any"
        for field in [caMin,paMin,ageMin,ageMax]{field.widthAnchor.constraint(equalToConstant:52).isActive=true;field.controlSize = .small;field.font = .systemFont(ofSize:11)}
        for (field,label) in [(ageMin,"Age minimum"),(ageMax,"Age maximum")] {field.placeholderString="Any";field.delegate=self;field.setAccessibilityLabel(label)}
        position.controlSize = .small;position.widthAnchor.constraint(equalToConstant:110).isActive=true
        let reset=NSButton(title:"Reset",target:self,action:#selector(resetFilters));reset.isBordered=false;reset.controlSize = .small
        let quick=stack([text("Position",size:11),position,text("CA min",size:11),caMin,text("PA min",size:11),paMin,text("Age min",size:11),ageMin,text("Age max",size:11),ageMax,filterToggle,reset],vertical:false,spacing:12)
        let top=stack([titleRow,search,quick],spacing:16);[titleRow,search,quick].forEach {fillWidth($0,top)}
        split.delegate=self;split.isVertical=true;split.dividerStyle = .thin;split.translatesAutoresizingMaskIntoConstraints=false
        let tableScroll=playerTableContainer.scrollView;tableScroll.documentView=table;tableScroll.hasVerticalScroller=true;tableScroll.hasHorizontalScroller=true;tableScroll.autohidesScrollers=true;tableScroll.drawsBackground=true;tableScroll.backgroundColor=Palette.background;tableScroll.translatesAutoresizingMaskIntoConstraints=true
        table.dataSource=self;table.delegate=self;table.rowHeight=34;table.intercellSpacing=NSSize(width:8,height:0);table.style = .plain;table.backgroundColor=Palette.background;table.usesAlternatingRowBackgroundColors=false;table.columnAutoresizingStyle = .noColumnAutoresizing;table.allowsColumnReordering=true;table.allowsColumnResizing=true;table.allowsMultipleSelection=true
        for (id,name,width) in [("name","Player",218.0),("age","Age",40),("ca","CA",42),("pa","PA",42),("position","Positions",122),("club","Club",150),("wage","Wage",104),("expiry","Expiry",96),("cost","Value / Asking Price",130)] {
            let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));col.title=name;col.width=width;col.minWidth=id == "name" ? 160 : 38
            col.sortDescriptorPrototype=NSSortDescriptor(key:id,ascending:true)
            table.addTableColumn(col)
        }
        table.autosaveName="TouchlineV1PlayerTable"
        table.autosaveTableColumns=true
        table.sortDescriptors=[NSSortDescriptor(key:"ca",ascending:false)]
        let context=NSMenu();context.addItem(withTitle:"Copy Player Name",action:#selector(copyName),keyEquivalent:"").target=self
        context.addItem(.separator())
        context.addItem(withTitle:"Add to Shortlist",action:#selector(addSelectedToShortlist),keyEquivalent:"").target=self
        context.addItem(withTitle:"Remove from Shortlist",action:#selector(removeSelectedFromShortlist),keyEquivalent:"").target=self
        context.autoenablesItems=false;context.delegate=self;table.menu=context
        detail.translatesAutoresizingMaskIntoConstraints=true
        split.addArrangedSubview(playerTableContainer);split.addArrangedSubview(detail)
        progress.isIndeterminate=false;progress.minValue=0;progress.maxValue=1;progress.style = .bar;progress.controlSize = .small;progress.isHidden=true;progress.widthAnchor.constraint(equalToConstant:120).isActive=true
        status.font = .systemFont(ofSize:10);timestamp.font = .systemFont(ofSize:10)
        let footer=stack([status,progress,timestamp],vertical:false,spacing:16);status.setContentHuggingPriority(.defaultLow,for:.horizontal)
        [top,split,footer].forEach {work.addSubview($0)}
        NSLayoutConstraint.activate([top.topAnchor.constraint(equalTo:work.topAnchor,constant:20),top.leadingAnchor.constraint(equalTo:work.leadingAnchor,constant:20),top.trailingAnchor.constraint(equalTo:work.trailingAnchor,constant:-20),split.topAnchor.constraint(equalTo:top.bottomAnchor,constant:18),split.leadingAnchor.constraint(equalTo:work.leadingAnchor),split.trailingAnchor.constraint(equalTo:work.trailingAnchor),split.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-6),footer.leadingAnchor.constraint(equalTo:work.leadingAnchor,constant:12),footer.trailingAnchor.constraint(equalTo:work.trailingAnchor,constant:-12),footer.bottomAnchor.constraint(equalTo:work.bottomAnchor,constant:-7),footer.heightAnchor.constraint(equalToConstant:17)])
        root.layoutSubtreeIfNeeded()
    }
    func splitViewDidResizeSubviews(_ notification:Notification) {
        guard dividerRestored, let view=notification.object as? NSSplitView, view === split,
              let left=view.subviews.first else {return}
        UserDefaults.standard.set(Double(left.frame.maxX),forKey:dividerPreference)
    }
    func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat {395}
    func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat {splitView.bounds.width-603}
    func applyQuery(debounce:Bool=false){
        queryPending=true;updateResultAction()
        generation+=1;let token=generation;pending?.cancel()
        let source=rows,q=query,s=sort
        let shortlistOnly=showingShortlist,index=shortlistIndex,entries=shortlist.entries
        let item=DispatchWorkItem { [weak self] in
            let began=Date()
            let resolution=shortlistOnly ? index.resolve(entries) : nil
            let indices=selectRows(source,query:q,sort:s,candidates:resolution?.rowIndices)
            let milliseconds=Date().timeIntervalSince(began)*1000
            DispatchQueue.main.async {
                guard let self=self,self.generation==token else{return}
                // Preserve the latest native selection, including clicks during a debounced query.
                let selectedUIDs=Set(self.selectedSourceRowIndices().map {self.rows[$0].player.uid})
                let selection=restoredPlayerSelection(selectedUIDs,results:indices,rows:source)
                self.visible=indices;self.queryPending=false;self.updateResultAction();self.table.reloadData()
                self.updateBrowserSummary(results:indices.count,total:resolution?.rowIndices.count ?? source.count,unresolved:resolution?.unresolvedCount ?? 0)
                self.table.selectRowIndexes(selection,byExtendingSelection:false)
                // Reload/sort/removal can retain the same numeric index but a different player.
                self.detail.show(self.selectedPlayer())
                self.log(["event":"query","milliseconds":milliseconds,"results":indices.count,"sort":s.key])
            }
        }
        pending=item;worker.asyncAfter(deadline:.now()+(debounce ? 0.16 : 0),execute:item)
    }
    func selectedPlayer()->Player? {let i=table.selectedRow;guard i>=0,i<visible.count,rows.indices.contains(visible[i]) else{return nil};return rows[visible[i]].player}
    func numberOfRows(in tableView:NSTableView)->Int {visible.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard row<visible.count,let id=tableColumn?.identifier else{return nil}
        if id.rawValue == "name" {
            let cell=(table.makeView(withIdentifier:id,owner:self) as? PlayerNameCell) ?? PlayerNameCell()
            cell.identifier=id;let r=rows[visible[row]]
            cell.textField?.stringValue=r.name;cell.club.stringValue=r.club;cell.toolTip=r.name+" · "+r.club
            return cell
        }
        let cell=(table.makeView(withIdentifier:id,owner:self) as? NSTableCellView) ?? {
            let v=NSTableCellView();v.identifier=id;let f=text("",size:12);v.textField=f;v.addSubview(f)
            NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo:v.leadingAnchor,constant:3),f.trailingAnchor.constraint(equalTo:v.trailingAnchor,constant:-3),f.centerYAnchor.constraint(equalTo:v.centerYAnchor)])
            return v
        }()
        let r=rows[visible[row]],p=r.player;var value="";var color=NSColor.labelColor
        switch id.rawValue {
        case "age":value=r.age.map(String.init) ?? "—"
        case "club":value=r.club
        case "position":value=r.position
        case "ca":value=String(p.ca);color=Palette.accent
        case "pa":value=String(p.pa);color=Palette.accent
        case "cost":if let cost=p.cost {value=displayMoney(cost.1,currency:selectedCurrency);cell.toolTip=cost.0} else{value="Unresolved";color=Palette.muted;cell.toolTip="Market Value and Asking Price are unresolved."}
        case "wage":value=p.transfers?.weeklyWage.display(in:selectedCurrency) ?? "Unresolved"
        case "expiry":value=p.transfers?.contractExpiry.display ?? "Unresolved"
        default:break
        }
        cell.textField?.stringValue=value;cell.textField?.textColor=color
        if ["ca","pa"].contains(id.rawValue),let label=cell.textField {Palette.followAccent(label)}
        cell.textField?.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular)
        if id.rawValue != "cost" {cell.toolTip=value}
        return cell
    }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? {
        let view=ScoutingRow();view.backgroundColor = Palette.background;return view
    }
    func tableViewSelectionDidChange(_ notification:Notification){let start=Date();detail.show(selectedPlayer());log(["event":"selection","milliseconds":Date().timeIntervalSince(start)*1000])}
    func tableView(_ tableView:NSTableView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]){if let d=table.sortDescriptors.first {sort=SortSpec(key:d.key ?? "name",ascending:d.ascending);applyQuery()}}
    @objc func copyName(){guard let p=selectedPlayer() else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(p.displayName,forType:.string)}
    @objc func focusSearch(){window.makeFirstResponder(search)}
    @objc func showSettings(){
        if settingsController == nil {settingsController=SettingsWindowController(currencyPicker:currencyPicker,playerFaces:playerFaces,relativeTo:window)}
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }
    func configureCurrencies(_ cached:CurrencyTable?) {
        currencies=cached?.available ?? [];currencyPicker.removeAllItems();currencyPicker.addItem(withTitle:"Base units")
        for c in currencies {currencyPicker.addItem(withTitle:c.name);currencyPicker.lastItem?.toolTip=c.name + (c.symbol.isEmpty ? "" : " · "+c.symbol)}
        let wanted=UserDefaults.standard.string(forKey:"TouchlineDisplayCurrency") ?? "Canadian Dollar"
        if let index=currencies.firstIndex(where:{$0.name==wanted}) {currencyPicker.selectItem(at:index+1)}
        currencyPicker.isEnabled = !currencies.isEmpty
        selectedCurrency=currencyPicker.indexOfSelectedItem>0 ? currencies[currencyPicker.indexOfSelectedItem-1] : nil
        detail.currency=selectedCurrency;detail.hasCurrencies = !currencies.isEmpty
    }
    @objc func changeCurrency() {
        let began=Date();let index=currencyPicker.indexOfSelectedItem
        selectedCurrency=index>0 ? currencies[index-1] : nil
        UserDefaults.standard.set(selectedCurrency?.name ?? "Base units",forKey:"TouchlineDisplayCurrency")
        detail.currency=selectedCurrency
        // Refresh visible cells only. No cache decode, query, sorting or live reads.
        let range=table.rows(in:table.visibleRect)
        if range.location != NSNotFound && range.length>0 {table.reloadData(forRowIndexes:IndexSet(integersIn:range.location..<min(range.location+range.length,visible.count)),columnIndexes:IndexSet(integersIn:0..<table.numberOfColumns))}
        detail.show(selectedPlayer())
        log(["event":"currency_change","currency":selectedCurrency?.name ?? "Base units","milliseconds":Date().timeIntervalSince(began)*1000])
    }
    @objc func openLatest(){guard !busy && !loading else{return};load(cachePath)}
    func load(_ url:URL){
        guard FileManager.default.fileExists(atPath:url.path) else {status.stringValue="No saved cache. Open FM24, load your career, then choose Refresh Live Data.";count.stringValue="No players loaded";return}
        loading=true;offline.isEnabled=false;refresh.isEnabled=false;status.stringValue="Opening saved players…";progress.isHidden=false;progress.isIndeterminate=true;progress.startAnimation(nil)
        worker.async { [weak self] in
            do {
                let (snapshot,rows,seconds)=try loadCache(url)
                let nationalities=availableNationalities(rows)
                let shortlistIndex=ShortlistIndex(rows)
                DispatchQueue.main.async {
                    guard let self=self else{return};self.rows=rows;self.shortlistIndex=shortlistIndex;self.detail.projectionDate=snapshot.projectionDate;self.configureCurrencies(snapshot.currencies);self.configureNationalities(nationalities)
                    self.loading=false;self.offline.isEnabled=true;self.refresh.isEnabled=true;self.progress.stopAnimation(nil);self.progress.isHidden=true;self.progress.isIndeterminate=false
                    let date=ISO8601DateFormatter();date.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
                    let captured=date.date(from:snapshot.capturedAt)
                    self.timestamp.stringValue="Captured "+(captured?.formatted(date:.abbreviated,time:.shortened) ?? snapshot.capturedAt)+String(format:" · %.2f s",snapshot.elapsedSeconds)
                    self.log(["event":"load","seconds":seconds,"count":rows.count,"cache":url.path]);self.applyQuery()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self=self else{return};self.loading=false;self.offline.isEnabled=true;self.refresh.isEnabled=true;self.progress.stopAnimation(nil);self.progress.isHidden=true;self.progress.isIndeterminate=false
                    self.status.stringValue="Could not open cache: "+error.localizedDescription;self.log(["event":"load_error","message":error.localizedDescription])
                }
            }
        }
    }
    @objc func refreshLive(){
        guard !busy && !loading else{return}
        guard let backend=Bundle.main.resourceURL?.appendingPathComponent("backend/src/touchline_live.py") else{return}
        busy=true;detached=false;captureError=nil;refresh.isEnabled=false;offline.isEnabled=false;progress.isHidden=false;progress.isIndeterminate=false;progress.doubleValue=0;status.stringValue="Preparing live capture…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let python=PythonRuntime.resolve()
            DispatchQueue.main.async {
                guard let self=self else {return}
                if self.quitting {self.busy=false;NSApp.reply(toApplicationShouldTerminate:true);return}
                guard let python=python else {
                    self.busy=false;self.refresh.isEnabled=true;self.offline.isEnabled=true;self.progress.isHidden=true
                    self.status.stringValue="Python 3.10 or newer is required for live capture. Install Python, then retry. Offline browsing remains available."
                    return
                }
                self.launchCapture(backend:backend,python:python)
            }
        }
    }
    private func launchCapture(backend:URL,python:URL) {
        let task=Process();task.executableURL=python;task.arguments=["-B","-u",backend.path,"--output",latest.deletingLastPathComponent().path,"--progress-json"]
        let pipe=Pipe();task.standardOutput=pipe;task.standardError=pipe
        process=task
        do {try task.run()} catch {busy=false;process=nil;refresh.isEnabled=true;offline.isEnabled=true;progress.isHidden=true;status.stringValue="Unable to launch the reader: "+error.localizedDescription;return}
        // Reading pipe output never blocks AppKit's main thread.
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var buffered=Data()
            while true {
                let data=pipe.fileHandleForReading.availableData
                if data.isEmpty {break};buffered.append(data)
                while let range=buffered.range(of:Data([10])) {
                    let line=buffered.subdata(in:0..<range.lowerBound);buffered.removeSubrange(0..<range.upperBound)
                    if let event=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] {
                        DispatchQueue.main.async {self?.captureEvent(event)}
                    }
                }
            }
            task.waitUntilExit()
            DispatchQueue.main.async {self?.captureFinished(task.terminationStatus)}
        }
    }
    func captureEvent(_ event:[String:Any]){
        log(event)
        switch event["event"] as? String {
        case "progress":status.stringValue=event["message"] as? String ?? "Capturing…";progress.doubleValue=event["fraction"] as? Double ?? 0
        case "detached":detached=true;status.stringValue="FM24 detached · saving local cache"
        case "error":captureError=event["message"] as? String
        default:break
        }
    }
    func captureFinished(_ code:Int32){
        process=nil;busy=false;refresh.isEnabled=true;offline.isEnabled=true;progress.isHidden=true
        if quitting {NSApp.reply(toApplicationShouldTerminate:true);return}
        if code==0 && detached {load(latest)}
        else {status.stringValue=captureError ?? "Capture did not complete. The previous cache is retained; you can retry.";log(["event":"capture_failed","exit":Int(code)])}
    }
    func log(_ event:[String:Any]){
        // Diagnostic logs can contain local paths; never create them by default in a public build.
        guard ProcessInfo.processInfo.environment["TOUCHLINE_DEBUG_LOGS"] == "1" else {return}
        try? FileManager.default.createDirectory(at:dataFolder,withIntermediateDirectories:true)
        let url=dataFolder.appendingPathComponent("ui-metrics.jsonl")
        guard var bytes=try? JSONSerialization.data(withJSONObject:event,options:.sortedKeys) else{return};bytes.append(10)
        if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
        if let f=try? FileHandle(forWritingTo:url){defer{try? f.close()};_ = try? f.seekToEnd();try? f.write(contentsOf:bytes)}
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {NSApp.terminate(nil);return false}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if busy {
            if !quitting {quitting=true;status.stringValue="Cancelling capture and closing the read-only attachment…";process?.interrupt()}
            return .terminateLater
        }
        return .terminateNow
    }
    @objc func about(){
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Touchline Live",.applicationVersion:"0.4",.credits:NSAttributedString(string:"Read-only live capture. Local scouting.\nBuilt on the verified FM24 player collection.")])
    }
}
