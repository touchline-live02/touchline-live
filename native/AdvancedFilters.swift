import AppKit

// Both interfaces bind to AppDelegate.filterEditor. Keep one owner and one query
// pipeline; this extension only groups the editor construction and event handling.
extension AppDelegate {
    // Every bound control reads/writes the same draft, including quick-filter mirrors.
    func bind(_ control:NSControl,_ field:FilterField) {
        control.identifier=NSUserInterfaceItemIdentifier(field.rawValue)
        filterControls[field,default:[]].append(control)
        control.target=self;control.action=#selector(filterControlChanged(_:))
        if let input=control as? NSTextField {input.delegate=self;input.placeholderString="Any";input.font = .systemFont(ofSize:12)}
        if let popup=control as? NSPopUpButton {popup.font = .systemFont(ofSize:12)}
        control.setAccessibilityLabel(field.rawValue)
    }
    func syncFilterControls(except source:NSControl?=nil) {
        for (field,controls) in filterControls {
            for control in controls where control !== source {
                if let popup=control as? NSPopUpButton {popup.selectItem(withTitle:filterEditor[field])}
                else if let stepper=control as? NSStepper {
                    guard let bounds=field.stepperBounds else {continue}
                    let value=filterEditor.stepperValue(for:field)
                    stepper.isEnabled=value != nil
                    stepper.integerValue=value ?? bounds.lowerBound
                }
                else {control.stringValue=filterEditor[field]}
            }
        }
    }
    func buildFilters(){
        let positions=["Any position","GK","DC","DL","DR","WBL","WBR","DM","MC","ML","MR","AMC","AML","AMR","ST","SW"]
        position.addItems(withTitles:positions)
        employment.addItems(withTitles:["Any employment","Free agent","Contracted","Unknown state"])
        nationality.addItem(withTitle:"Any nationality")
        clubSearch.sendsSearchStringImmediately=true
        for (c,f) in [(search,FilterField.name),(clubSearch,.club),(caMin,.caMin),(caMax,.caMax),(paMin,.paMin),(paMax,.paMax),(ageMin,.ageMin),(ageMax,.ageMax),(wageMin,.wageMin),(wageMax,.wageMax),(expiryAfter,.expiryAfter),(expiryBefore,.expiryBefore)] {bind(c,f)}
        for (c,f) in [(position,FilterField.position),(nationality,.nationality),(employment,.employment)] {bind(c,f)}
        func input(_ field:FilterField)->NSTextField {let c=NSTextField();bind(c,field);return c}
        func labeled(_ label:String,_ control:NSView)->NSView {
            let l=text(label,size:11,color:Palette.muted);l.widthAnchor.constraint(equalToConstant:76).isActive=true
            let row=stack([l,control],vertical:false,spacing:8)
            control.setContentHuggingPriority(.defaultLow,for:.horizontal)
            return row
        }
        func range(_ label:String,_ low:NSTextField,_ high:NSTextField,stepped:Bool=false)->NSView {
            let l=text(label,size:11,weight:.medium);l.widthAnchor.constraint(equalToConstant:stepped ? 44 : 76).isActive=true
            func edgeLabel(_ value:String)->NSTextField {
                let label=text(value,size:10,color:Palette.muted)
                if stepped {
                    label.widthAnchor.constraint(equalToConstant:24).isActive=true
                    label.setContentCompressionResistancePriority(.required,for:.horizontal)
                }
                return label
            }
            func entry(_ input:NSTextField,_ edge:String)->NSView {
                input.setAccessibilityLabel(label+" "+edge)
                input.widthAnchor.constraint(equalToConstant:stepped ? 64 : 80).isActive=true
                guard stepped,let id=input.identifier,let field=FilterField(rawValue:id.rawValue),let bounds=field.stepperBounds else {return input}
                let stepper=NSStepper();stepper.controlSize = .small
                stepper.minValue=Double(bounds.lowerBound);stepper.maxValue=Double(bounds.upperBound)
                stepper.increment=1;stepper.valueWraps=false;stepper.autorepeat=true
                stepper.setContentHuggingPriority(.required,for:.horizontal)
                stepper.setContentCompressionResistancePriority(.required,for:.horizontal)
                bind(stepper,field);stepper.setAccessibilityLabel(label+" "+edge+" adjustment")
                stepper.toolTip="Adjust by 1 (\(bounds.lowerBound)–\(bounds.upperBound)). Clear the text field for Any."
                return stack([input,stepper],vertical:false,spacing:3)
            }
            return stack([l,edgeLabel("Min"),entry(low,"minimum"),edgeLabel("Max"),entry(high,"maximum")],vertical:false,spacing:6)
        }
        func section(_ title:String,_ views:[NSView])->NSView {
            let body=stack([accentText(title,size:10,weight:.semibold)]+views,spacing:10)
            views.forEach {fillWidth($0,body)}
            return padded(body,inset:12)
        }
        func pair(_ a:NSView,_ b:NSView)->NSView {let row=stack([a,b],vertical:false,spacing:12);row.alignment = .top;row.distribution = .fillEqually;return row}
        let advancedName=input(.name),advancedPosition=NSPopUpButton()
        advancedPosition.addItems(withTitles:positions);bind(advancedPosition,.position)
        advancedPosition.toolTip="Matches position ratings of 15–20."
        let player=section("PLAYER",[labeled("Name",advancedName),labeled("Club",clubSearch),labeled("Nationality",nationality),labeled("Position",advancedPosition),labeled("Employment",employment)])
        let ability=section("ABILITY & AGE",[range("CA",input(.caMin),caMax,stepped:true),range("PA",input(.paMin),paMax,stepped:true),range("Age",input(.ageMin),input(.ageMax),stepped:true)])
        let askingLow=input(.askingMin),askingHigh=input(.askingMax)
        let money=stack([range("Asking Price",askingLow,askingHigh),range("Weekly wage",wageMin,wageMax)],spacing:12)
        for f in [askingLow,askingHigh,wageMin,wageMax] {f.toolTip="Base units, independent of display currency. Unresolved values do not match a range."}
        expiryAfter.placeholderString="YYYY-MM-DD";expiryBefore.placeholderString="YYYY-MM-DD"
        let dates=stack([text("Contract expiry",size:11,weight:.medium),labeled("From",expiryAfter),labeled("Through",expiryBefore)],spacing:8)
        let contract=section("CONTRACT",[pair(money,dates),text("Money ranges use base units · Unresolved values are excluded from active ranges",size:10,color:Palette.muted)])
        ruleStack.orientation = .vertical;ruleStack.alignment = .leading;ruleStack.spacing=8
        let addAttribute=NSButton(title:"+ Attribute",target:self,action:#selector(addAttributeRule))
        let addHidden=NSButton(title:"+ Hidden",target:self,action:#selector(addHiddenRule))
        let addComponent=NSButton(title:"+ Personality component",target:self,action:#selector(addComponentRule))
        for b in [addAttribute,addHidden,addComponent] {b.bezelStyle = .rounded;b.controlSize = .small}
        let attributes=section("ATTRIBUTES",[stack([addAttribute,addHidden,addComponent],vertical:false,spacing:8),ruleStack])
        filterPane.translatesAutoresizingMaskIntoConstraints=false;filterPane.drawsBackground=false;filterPane.hasVerticalScroller=true;filterPane.autohidesScrollers=true
        let body=stack([pair(player,ability),contract,attributes],spacing:12)
        body.edgeInsets=NSEdgeInsets(top:4,left:16,bottom:16,right:16)
        body.arrangedSubviews.forEach {$0.widthAnchor.constraint(equalTo:body.widthAnchor,constant:-32).isActive=true}
        filterPane.documentView=body;body.widthAnchor.constraint(equalTo:filterPane.contentView.widthAnchor).isActive=true
        let close=NSButton(image:NSImage(systemSymbolName:"xmark",accessibilityDescription:"Close filters")!,target:self,action:#selector(dismissFilters));close.isBordered=false;close.keyEquivalent="\u{1b}"
        let heading=stack([text("Advanced scouting",size:18,weight:.semibold),NSView(),close],vertical:false)
        let header=stack([heading,text("All conditions must match · Results update instantly",size:11,color:Palette.muted)],spacing:5);fillWidth(heading,header)
        let clear=NSButton(title:"Clear all filters",target:self,action:#selector(resetFilters));clear.bezelStyle = .rounded
        showResults.title="Show 0 players";showResults.bezelStyle = .rounded;showResults.target=self;showResults.action=#selector(dismissFilters);showResults.keyEquivalent="\r";Palette.followAccent(showResults)
        let actions=stack([clear,NSView(),showResults],vertical:false)
        let footer=stack([filterMessage,actions],spacing:8);fillWidth(filterMessage,footer);fillWidth(actions,footer)
        filterContent.wantsLayer=true;filterContent.layer?.backgroundColor=Palette.background.cgColor
        [header,filterPane,footer].forEach {filterContent.addSubview($0)}
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo:filterContent.topAnchor,constant:16),header.leadingAnchor.constraint(equalTo:filterContent.leadingAnchor,constant:20),header.trailingAnchor.constraint(equalTo:filterContent.trailingAnchor,constant:-20),
            filterPane.topAnchor.constraint(equalTo:header.bottomAnchor,constant:14),filterPane.leadingAnchor.constraint(equalTo:filterContent.leadingAnchor),filterPane.trailingAnchor.constraint(equalTo:filterContent.trailingAnchor),filterPane.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-10),
            footer.leadingAnchor.constraint(equalTo:header.leadingAnchor),footer.trailingAnchor.constraint(equalTo:header.trailingAnchor),footer.bottomAnchor.constraint(equalTo:filterContent.bottomAnchor,constant:-16)])
        syncFilterControls()
    }
    @objc func dismissFilters(){filterPopover.performClose(nil)}
    @objc func addAttributeRule(){addRule(.attribute)}
    @objc func addHiddenRule(){addRule(.hidden)}
    @objc func addComponentRule(){addRule(.component)}
    func addRule(_ source:NumericRule.Source){
        let rule=RuleView(source:source,target:self,action:#selector(filterChanged),delete:#selector(removeRule(_:)))
        rule.minimum.delegate=self;rule.maximum.delegate=self;ruleStack.addArrangedSubview(rule);fillWidth(rule,ruleStack);ruleViews.append(rule)
        filterChanged()
    }
    @objc func removeRule(_ sender:NSButton){guard let i=ruleViews.firstIndex(where:{$0.remove === sender}) else{return};let r=ruleViews.remove(at:i);ruleStack.removeArrangedSubview(r);r.removeFromSuperview();filterChanged()}
    @objc func resetFilters(){
        filterEditor.reset();syncFilterControls()
        ruleViews.forEach {ruleStack.removeArrangedSubview($0);$0.removeFromSuperview()};ruleViews=[]
        commitFilters(debounce:false)
    }
    func controlTextDidChange(_ obj:Notification){
        if let control=obj.object as? NSControl {filterControlChanged(control)}
    }
    @objc func filterControlChanged(_ control:NSControl){
        if let id=control.identifier,let field=FilterField(rawValue:id.rawValue) {
            if let stepper=control as? NSStepper {
                guard stepper.isEnabled,filterEditor.setSteppedValue(stepper.integerValue,for:field) else {return}
            } else {filterEditor[field]=(control as? NSPopUpButton)?.titleOfSelectedItem ?? control.stringValue}
            syncFilterControls(except:control)
        }
        filterChanged()
    }
    @objc func filterChanged(){commitFilters(debounce:true)}
    private func commitFilters(debounce:Bool){
        filterEditor.rules=ruleViews.map {RuleDraft(source:$0.source,key:$0.keys[$0.choice.indexOfSelectedItem],minimum:$0.minimum.stringValue,maximum:$0.maximum.stringValue)}
        do {
            let next=try filterEditor.makeQuery()
            filterMessage.stringValue=""
            guard next != query else {updateResultAction();return}
            query=next;applyQuery(debounce:debounce)
        }
        catch {filterMessage.stringValue=(error as? FilterInputError)?.message ?? "Check the filter values.";updateResultAction()}
    }
    func updateResultAction(){
        let invalid = !filterMessage.stringValue.isEmpty
        showResults.title=invalid ? "Check filter values" : (queryPending ? "Updating results…" : "Show \(visible.count.formatted()) players")
        showResults.isEnabled = !invalid && !queryPending
        filterToggle.toolTip=invalid ? filterMessage.stringValue : "Edit all scouting filters"
    }
    @objc func toggleFilters(){if filterPopover.isShown {filterPopover.performClose(nil)} else {filterPopover.show(relativeTo:filterToggle.bounds,of:filterToggle,preferredEdge:.maxY)}}
    func configureNationalities(_ names:[String]) {
        let selected=query.nationality
        nationality.removeAllItems();nationality.addItem(withTitle:"Any nationality");nationality.addItems(withTitles:names)
        if let selected=selected,let index=names.firstIndex(of:selected) {nationality.selectItem(at:index+1)}
        else {nationality.selectItem(at:0);query.nationality=nil;filterEditor[.nationality]="Any nationality"}
    }
}
