import AppKit

/// Keep empty-state presentation outside NSScrollView's internally tiled views.
final class PlayerTableContainer:NSView {
    let scrollView=NSScrollView()
    let emptyLabel=text("No players shortlisted",size:12,color:Palette.muted,wrap:true)
    override init(frame:NSRect) {
        super.init(frame:frame)
        scrollView.autoresizingMask=[.width,.height]
        addSubview(scrollView)
        emptyLabel.translatesAutoresizingMaskIntoConstraints=true
        emptyLabel.alignment = .center;emptyLabel.isHidden=true
        addSubview(emptyLabel,positioned:.above,relativeTo:scrollView)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout() {
        super.layout()
        scrollView.frame=bounds
        scrollView.tile()
        positionEmptyLabel()
    }
    func positionEmptyLabel() {
        // Convert the body viewport, not the document (which can have zero height).
        // It excludes headers/scrollers and remains valid after scrolling/resizing.
        let body=scrollView.contentView.convert(scrollView.contentView.bounds,to:self).intersection(bounds)
        guard !body.isNull,body.width>36,body.height>32 else {emptyLabel.frame = .zero;return}
        let width=min(CGFloat(360),body.width-36)
        let height=min(CGFloat(44),body.height-32)
        emptyLabel.frame=NSRect(x:body.midX-width/2,y:body.midY-height/2,width:width,height:height)
    }
}

enum AccentPreset:String,CaseIterable {
    case cyan,blue,green,purple,pink,red,orange,yellow
    var name:String {rawValue.capitalized}
    var color:NSColor {
        switch self {
        case .cyan:return NSColor(calibratedRed:0.0,green:0.76,blue:0.80,alpha:1)
        case .blue:return .systemBlue
        case .green:return .systemGreen
        case .purple:return .systemPurple
        case .pink:return .systemPink
        case .red:return .systemRed
        case .orange:return .systemOrange
        case .yellow:return .systemYellow
        }
    }
}

enum Palette {
    static let background=NSColor(srgbRed:0.115,green:0.115,blue:0.115,alpha:1)
    static let surface=NSColor(srgbRed:0.14,green:0.14,blue:0.14,alpha:1)
    static let elevated=NSColor(srgbRed:0.17,green:0.17,blue:0.17,alpha:1)
    static let border=NSColor(calibratedWhite:0.36,alpha:0.3)
    private static let accentPreference="TouchlineAccentPreset"
    private(set) static var accentPreset=AccentPreset(rawValue:UserDefaults.standard.string(forKey:accentPreference) ?? "") ?? .cyan
    static var accent:NSColor {accentPreset.color}
    // Only explicitly registered branding views follow the accent. Weak references
    // allow recycled cells and replaced profiles to disappear without observers.
    private static let accentViews=NSHashTable<NSView>.weakObjects()
    static func followAccent(_ view:NSView) {
        accentViews.add(view);applyAccent(to:view)
    }
    private static func applyAccent(to view:NSView) {
        if let toggle=view as? ProjectionToggleButton {toggle.refreshAccent()}
        else if let label=view as? NSTextField {label.textColor=accent}
        else if let image=view as? NSImageView {image.contentTintColor=accent}
        else if let button=view as? NSButton {button.contentTintColor=accent}
        else if view is SidebarPitchView {view.needsDisplay=true}
    }
    static func selectAccent(_ preset:AccentPreset) {
        accentPreset=preset;UserDefaults.standard.set(preset.rawValue,forKey:accentPreference)
        accentViews.allObjects.forEach {applyAccent(to:$0)}
    }
    static let muted=NSColor(calibratedWhite:0.59,alpha:1)
    static func attribute(_ n:Int?) -> NSColor {
        guard let n=n else{return muted}
        switch n { case 1...5:return .systemGray; case 6...10:return NSColor(calibratedWhite:0.94,alpha:1); case 11...15:return NSColor(calibratedRed:0.95,green:0.81,blue:0.31,alpha:1);case 16...20:return NSColor(calibratedRed:0.39,green:0.83,blue:0.48,alpha:1);default:return muted }
    }
}
// Decoration only: no intrinsic size, hit testing, focus, or accessibility item.
final class SidebarPitchView:NSView {
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {false}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override init(frame:NSRect) {
        super.init(frame:frame)
        translatesAutoresizingMaskIntoConstraints=false
        setAccessibilityElement(false)
        wantsLayer=true;layer?.masksToBounds=true
        layerContentsRedrawPolicy = .duringViewResize
        Palette.followAccent(self)
    }
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        // An angled pitch corner, with the rest of the pitch cropped offscreen.
        // The containing view occupies only the existing navigation/footer gap.
        let height=min(CGFloat(240),bounds.height)
        guard height>0,bounds.width>0 else {return}
        let band=NSRect(x:bounds.minX,y:bounds.minY+(bounds.height-height)*0.58,width:bounds.width,height:height)
        NSGraphicsContext.saveGraphicsState()
        defer {NSGraphicsContext.restoreGraphicsState()}
        NSBezierPath(rect:band).addClip()
        Palette.accent.withAlphaComponent(0.09).setStroke()
        let lines=NSBezierPath();lines.lineWidth=1.3
        // Local pitch coordinates: x along the goal line, y up the touchline.
        // Rotate 12 degrees so the boundary and box edges read asymmetrically.
        func point(_ x:CGFloat,_ y:CGFloat)->NSPoint {
            NSPoint(x:band.minX+54+x*0.978148-y*0.207912,
                    y:band.maxY-12-x*0.207912-y*0.978148)
        }
        lines.move(to:point(0,320))
        lines.line(to:point(0,0))
        lines.line(to:point(420,0))
        // Quarter-circle corner marking inside the two pitch boundaries.
        lines.move(to:point(28,0))
        lines.curve(to:point(0,28),controlPoint1:point(28,15.464),controlPoint2:point(15.464,28))
        // Only the near edge of the penalty area is visible; its far side and
        // the goal sit beyond the sidebar, avoiding a miniature full-pitch icon.
        lines.move(to:point(92,0))
        lines.line(to:point(92,132))
        lines.line(to:point(420,132))
        lines.stroke()
    }
}
func text(_ value:String,size:CGFloat=12,weight:NSFont.Weight = .regular,color:NSColor = .labelColor,wrap:Bool=false) -> NSTextField {
    let l=NSTextField(labelWithString:value); l.font = .systemFont(ofSize:size,weight:weight);l.textColor=color
    l.translatesAutoresizingMaskIntoConstraints=false
    l.lineBreakMode=wrap ? .byWordWrapping : .byTruncatingTail
    l.maximumNumberOfLines=wrap ? 0 : 1
    l.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
    return l
}
func accentText(_ value:String,size:CGFloat=12,weight:NSFont.Weight = .regular) -> NSTextField {
    let label=text(value,size:size,weight:weight,color:Palette.accent)
    Palette.followAccent(label);return label
}

final class AccentSwatchButton:NSButton {
    let preset:AccentPreset
    init(_ preset:AccentPreset,target:AnyObject,action:Selector) {
        self.preset=preset
        super.init(frame:.zero)
        self.target=target;self.action=action;title="";isBordered=false
        setButtonType(.toggle);focusRingType = .exterior
        toolTip=preset.name;setAccessibilityLabel(preset.name+" accent colour")
        translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant:26),heightAnchor.constraint(equalToConstant:26)])
        updateSelection()
    }
    required init?(coder:NSCoder){fatalError()}
    func updateSelection() {
        state=preset == Palette.accentPreset ? .on : .off
        setAccessibilityValue(state == .on ? "Selected" : "Not selected")
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        if state == .on {
            NSColor.labelColor.setStroke()
            let ring=NSBezierPath(ovalIn:bounds.insetBy(dx:2,dy:2));ring.lineWidth=1.5;ring.stroke()
        }
        preset.color.withAlphaComponent(cell?.isHighlighted == true ? 0.65 : 1).setFill()
        NSBezierPath(ovalIn:bounds.insetBy(dx:6,dy:6)).fill()
    }
}

class FlippedStackBase:NSStackView { override var isFlipped:Bool { true } }
final class FlippedStack:FlippedStackBase {}

func stack(_ views:[NSView],vertical:Bool=true,spacing:CGFloat=8) -> NSStackView {
    let s=FlippedStack(views:views);s.orientation=vertical ? .vertical : .horizontal;s.spacing=spacing
    s.alignment=vertical ? .leading : .centerY;s.translatesAutoresizingMaskIntoConstraints=false
    return s
}
func fillWidth(_ child:NSView,_ parent:NSView) {child.widthAnchor.constraint(equalTo:parent.widthAnchor).isActive=true}
class Surface:NSView {
    init(_ color:NSColor=Palette.surface,radius:CGFloat=6){super.init(frame:.zero);wantsLayer=true;layer?.backgroundColor=color.cgColor;layer?.cornerRadius=radius;layer?.borderColor=Palette.border.cgColor;layer?.borderWidth=0.5;translatesAutoresizingMaskIntoConstraints=false}
    required init?(coder:NSCoder){fatalError()}
}
func padded(_ child:NSView,inset:CGFloat=14,color:NSColor=Palette.surface) -> NSView {
    child.translatesAutoresizingMaskIntoConstraints=false
    let box=Surface(color);box.addSubview(child)
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:box.leadingAnchor,constant:inset),child.trailingAnchor.constraint(equalTo:box.trailingAnchor,constant:-inset),child.topAnchor.constraint(equalTo:box.topAnchor,constant:inset),child.bottomAnchor.constraint(equalTo:box.bottomAnchor,constant:-inset)])
    return box
}
func attributeName(_ key:String)->String {
    key == "off_the_ball" ? "Off the Ball" : title(key)
}
// Shared by the attribute rows and the fixed Physical → Traits anchor.
private enum AttributeGeometry {
    static let headingHeight:CGFloat=25
    static let rowHeight:CGFloat=20
    static let traitsGap:CGFloat=14
}
// Attribute rows use explicit anchors; label intrinsic widths never move values.
func attrColumn(_ heading:String,keys:[String],values:[String:Int?],register:((String,NSTextField)->Void)?=nil,registerRole:((String,RoleAttributeRow)->Void)?=nil) -> NSView {
    let headingView=text(heading,size:11.5,weight:.semibold,color:.labelColor)
    headingView.heightAnchor.constraint(equalToConstant:heading.isEmpty ? 0 : AttributeGeometry.headingHeight).isActive=true
    let column=stack([headingView],spacing:0)
    column.widthAnchor.constraint(greaterThanOrEqualToConstant:166).isActive=true
    fillWidth(headingView,column)
    for (index,key) in keys.enumerated() {
        let value=values[key] ?? nil
        let row=RoleAttributeRow();row.translatesAutoresizingMaskIntoConstraints=false
        registerRole?(key,row)
        let shade:CGFloat=index % 2 == 0 ? 0.16 : 0.14
        row.wantsLayer=true;row.layer?.backgroundColor=NSColor(srgbRed:shade,green:shade,blue:shade,alpha:1).cgColor
        let name=text(attributeName(key),size:11.5,color:NSColor(calibratedWhite:0.80,alpha:1))
        let number=text(value.map(String.init) ?? "—",size:11.5,weight:.medium,color:Palette.attribute(value))
        name.toolTip=attributeName(key);number.alignment = .right
        number.font = .monospacedDigitSystemFont(ofSize:11.5,weight:.medium)
        register?(key,number)
        row.addSubview(name);row.addSubview(number)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant:AttributeGeometry.rowHeight),
            name.leadingAnchor.constraint(equalTo:row.leadingAnchor,constant:3),
            name.widthAnchor.constraint(equalToConstant:130),
            name.centerYAnchor.constraint(equalTo:row.centerYAnchor),
            number.widthAnchor.constraint(equalToConstant:22),
            number.trailingAnchor.constraint(equalTo:row.trailingAnchor,constant:-3),
            number.leadingAnchor.constraint(greaterThanOrEqualTo:name.trailingAnchor,constant:8),
            number.firstBaselineAnchor.constraint(equalTo:name.firstBaselineAnchor)
        ])
        column.addArrangedSubview(row);fillWidth(row,column)
    }
    return column
}
func attributeGroup(_ columns:[NSView])->NSView {
    let group=NSView();group.translatesAutoresizingMaskIntoConstraints=false
    let grid=stack(columns,vertical:false,spacing:20)
    grid.alignment = .top;grid.distribution = .fillEqually
    group.addSubview(grid)
    NSLayoutConstraint.activate([
        grid.leadingAnchor.constraint(equalTo:group.leadingAnchor),
        grid.trailingAnchor.constraint(equalTo:group.trailingAnchor),
        grid.topAnchor.constraint(equalTo:group.topAnchor,constant:6),
        grid.bottomAnchor.constraint(equalTo:group.bottomAnchor,constant:-6)
    ])
    for column in columns.dropLast() {
        let divider=NSBox();divider.boxType = .separator;divider.translatesAutoresizingMaskIntoConstraints=false
        group.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo:column.trailingAnchor,constant:10),
            divider.widthAnchor.constraint(equalToConstant:1),
            divider.topAnchor.constraint(equalTo:grid.topAnchor),
            divider.bottomAnchor.constraint(equalTo:grid.bottomAnchor)
        ])
    }
    return group
}

func metadata(_ label:String,_ value:String)->NSView {
    let name=text(label,size:10,color:Palette.muted)
    let content=text(value,size:11.5,weight:.medium);content.toolTip=value
    let result=stack([name,content],spacing:4);fillWidth(name,result);fillWidth(content,result)
    return result
}
func metadataRow(_ fields:[(String,String)])->NSView {
    let row=stack(fields.map {metadata($0.0,$0.1)},vertical:false,spacing:14)
    row.alignment = .top;row.distribution = .fillEqually;return row
}
func statBadge(_ key:String,_ value:Int)->NSView {
    let line=stack([text(key,size:10,weight:.semibold,color:Palette.muted),accentText(String(value),size:25,weight:.bold)],vertical:false,spacing:6)
    let box=padded(line,inset:8,color:Palette.elevated);box.widthAnchor.constraint(equalToConstant:84).isActive=true
    return box
}
func profileHeader(_ p:Player,faces:PlayerFaceService?)->NSView {
    let result=NSView();result.translatesAutoresizingMaskIntoConstraints=false
    // FM portrait mappings use the external person UID, never the internal entity index.
    let face=PlayerFaceView(uid:p.uid,service:faces)
    let identity=stack([text("PLAYER PROFILE",size:10,weight:.semibold,color:Palette.muted),text(p.displayName,size:25,weight:.bold)],spacing:6)
    let age=p.knownAge.map {"\($0) years old"} ?? "DOB  \(p.birthDate)"
    let bio=stack([text(age,size:12,weight:.medium),text(p.position,size:11.5,color:Palette.muted)],spacing:5)
    let badges=stack([statBadge("CA",p.ca),statBadge("PA",p.pa)],vertical:false,spacing:8)
    let club=text("Nationality  \(p.nationalityDisplay)     Club  \(p.club)",size:11,color:Palette.muted)
    let metadata=NSMutableAttributedString(string:"")
    for (value,isLabel) in [("Nationality  ",true),(p.nationalityDisplay+"     ",false),("Club  ",true),(p.club,false)] {
        metadata.append(NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:11,weight:isLabel ? .semibold : .medium),.foregroundColor:isLabel ? Palette.muted : NSColor.labelColor]))
    }
    club.attributedStringValue=metadata
    club.toolTip="Primary nationality: \(p.nationalityDisplay). Club: \(p.club)"
    [face,identity,bio,badges,club].forEach {result.addSubview($0)}
    NSLayoutConstraint.activate([
        face.topAnchor.constraint(equalTo:result.topAnchor),face.leadingAnchor.constraint(equalTo:result.leadingAnchor),face.bottomAnchor.constraint(lessThanOrEqualTo:club.topAnchor,constant:-8),
        identity.topAnchor.constraint(equalTo:result.topAnchor),identity.leadingAnchor.constraint(equalTo:face.trailingAnchor,constant:12),identity.trailingAnchor.constraint(equalTo:result.trailingAnchor),
        bio.topAnchor.constraint(equalTo:identity.bottomAnchor,constant:14),bio.leadingAnchor.constraint(equalTo:face.trailingAnchor,constant:12),bio.trailingAnchor.constraint(lessThanOrEqualTo:badges.leadingAnchor,constant:-12),
        badges.trailingAnchor.constraint(equalTo:result.trailingAnchor),badges.centerYAnchor.constraint(equalTo:bio.centerYAnchor),
        club.topAnchor.constraint(equalTo:bio.bottomAnchor,constant:12),club.leadingAnchor.constraint(equalTo:result.leadingAnchor),club.trailingAnchor.constraint(equalTo:result.trailingAnchor),club.bottomAnchor.constraint(equalTo:result.bottomAnchor)
    ])
    return result
}
final class DisclosureSection:FlippedStackBase {
    let toggle=NSButton();let body:NSView;let heading:String
    init(_ heading:String,body:NSView,expanded:Bool=false){
        self.body=body;self.heading=heading;super.init(frame:.zero)
        orientation = .vertical;alignment = .leading;spacing=6;translatesAutoresizingMaskIntoConstraints=false
        toggle.title=(expanded ? "▾ " : "▸ ")+heading;toggle.font = .systemFont(ofSize:10,weight:.semibold);toggle.contentTintColor=Palette.muted;toggle.isBordered=false;toggle.alignment = .left;toggle.target=self;toggle.action=#selector(change)
        toggle.heightAnchor.constraint(equalToConstant:28).isActive=true
        addArrangedSubview(toggle);addArrangedSubview(body);fillWidth(toggle,self);fillWidth(body,self);body.isHidden = !expanded
    }
    required init?(coder:NSCoder){fatalError()}
    @objc func change(){body.isHidden.toggle();toggle.title=(body.isHidden ? "▸ " : "▾ ")+heading}
}

/// A single native toggle. Only its active state uses the branding accent.
final class ProjectionToggleButton:NSButton {
    func refreshAccent() {
        contentTintColor=state == .on ? Palette.accent : .labelColor
        bezelColor=state == .on ? Palette.accent.withAlphaComponent(0.15) : nil
    }
}

final class DetailView:NSScrollView {
    var playerFaces:PlayerFaceService?
    var currency:DisplayCurrency?
    var hasCurrencies=false
    var projectionDate:String?
    private var projectedMode=false // Session preference; selecting a player does not reset it.
    private var roleFocus=RoleFocusState()
    private var roleRows:[(String,RoleAttributeRow)]=[]
    private var currentPlayer:Player?
    private var projection:ProjectionProfile?
    private var attributeNumbers:[(String,NSTextField)]=[]
    private var projectedButton:ProjectionToggleButton?
    private var peakLabel:NSTextField?
    let content=FlippedStack()
    override init(frame:NSRect){
        super.init(frame:frame);drawsBackground=true;backgroundColor=Palette.background;hasVerticalScroller=true;autohidesScrollers=true
        content.orientation = .vertical;content.alignment = .leading;content.spacing=14;content.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:20,right:16)
        content.translatesAutoresizingMaskIntoConstraints=false;documentView=content
        content.widthAnchor.constraint(equalTo:contentView.widthAnchor).isActive=true;show(nil)
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func toggleProjected(_ sender:ProjectionToggleButton) {
        projectedMode=sender.state == .on
        updateProjectedValues()
    }
    private func updateRoleHighlights() {
        for (key,row) in roleRows {row.tier=roleFocus.tier(for:key)}
    }
    private func updateProjectedValues() {
        projectedButton?.state=projectedMode ? .on : .off
        projectedButton?.refreshAccent()
        peakLabel?.isHidden = !projectedMode
        peakLabel?.stringValue=projection.map {"Peak \($0.peak)"} ?? "Peak unavailable"
        for (key,label) in attributeNumbers {
            let current=currentPlayer?.visibleAttributes[key] ?? nil
            let value=projectedMode ? (current == nil ? nil : projection?.attributes.displayed[key]) : current
            label.stringValue=value.map(String.init) ?? "—"
            label.textColor=Palette.attribute(value)
        }
    }
    func show(_ p:Player?){
        currentPlayer=p
        projection=p.flatMap {PlayerProjection.profile(for:$0,gameDate:projectionDate)}
        attributeNumbers.removeAll();roleRows.removeAll();projectedButton=nil;peakLabel=nil
        content.arrangedSubviews.forEach {content.removeArrangedSubview($0);$0.removeFromSuperview()}
        func add(_ v:NSView){content.addArrangedSubview(v);v.widthAnchor.constraint(equalTo:content.widthAnchor,constant:-32).isActive=true}
        func label(_ value:String){add(text(value,size:10,weight:.semibold,color:Palette.muted))}
        guard let p=p else {label("PLAYER PROFILE");add(text("Select a player",size:23,weight:.semibold));add(text("Browse your saved scouting data locally.",color:Palette.muted));return}
        add(profileHeader(p,faces:playerFaces))
        let separator=NSBox();separator.boxType = .separator;add(separator)
        let feet="L \((p.footStrengths["left_foot"] ?? nil).map(String.init) ?? "—")/20 · R \((p.footStrengths["right_foot"] ?? nil).map(String.init) ?? "—")/20"
        add(metadataRow([("Foot strengths",feet),("Personality",PlayerPersonality.profile(for:p,gameDate:projectionDate).display),("Height",p.heightCM.map {"\($0) cm"} ?? "Unresolved"),("Weight",p.weightKG.map {"\($0) kg"} ?? "Unresolved")]))
        if let t=p.transfers {
            let price=p.cost.map {($0.0,displayMoney($0.1,currency:currency))} ?? ("Asking Price",t.askingPrice?.display ?? "Unresolved")
            let terms=metadataRow([("Weekly wage",t.weeklyWage.display(in:currency)),price,("Contract expiry",t.contractExpiry.display)])
            let note=text(currency.map {"Amounts in "+$0.name} ?? (hasCurrencies ? "Base units" : "Currency unresolved"),size:9,color:Palette.muted,wrap:true)
            let panel=stack([text("CONTRACT",size:10,weight:.semibold,color:Palette.muted),terms,note],spacing:10)
            [terms,note].forEach {fillWidth($0,panel)}
            add(padded(panel,inset:10))
        }

        let heading=NSView();heading.translatesAutoresizingMaskIntoConstraints=false
        let title=text("ATTRIBUTES",size:10,weight:.semibold,color:Palette.muted)
        let legend=stack(([("1–5",3),("6–10",8),("11–15",13),("16–20",18)]).map {text($0.0,size:9,weight:.medium,color:Palette.attribute($0.1))},vertical:false,spacing:10)
        let projected=ProjectionToggleButton(title:"Projected",target:self,action:#selector(toggleProjected(_:)))
        projected.setButtonType(.pushOnPushOff);projected.bezelStyle = .rounded;projected.controlSize = .small
        projected.font = .systemFont(ofSize:11,weight:.medium)
        projected.toolTip="Local scouting projection using cached raw attributes and elapsed age. Not a guarantee of future development. Missing inputs remain unresolved."
        projected.setAccessibilityLabel("Show projected attributes")
        projected.state=projectedMode ? .on : .off;Palette.followAccent(projected)
        let peak=text("",size:10,weight:.medium,color:Palette.muted)
        peak.toolTip="Modelled reachable peak, capped by stored PA. The model's elapsed-year age can differ from calendar age."
        let roleButton=RoleFocusButton(focus:roleFocus)
        roleButton.onSelect = { [weak self] id in
            self?.roleFocus.select(id);self?.updateRoleHighlights()
        }
        let controls=stack([legend,roleButton,peak,projected],vertical:false,spacing:6)
        projectedButton=projected;peakLabel=peak
        heading.addSubview(title);heading.addSubview(controls)
        NSLayoutConstraint.activate([heading.heightAnchor.constraint(equalToConstant:24),title.leadingAnchor.constraint(equalTo:heading.leadingAnchor),title.centerYAnchor.constraint(equalTo:heading.centerYAnchor),controls.trailingAnchor.constraint(equalTo:heading.trailingAnchor),controls.centerYAnchor.constraint(equalTo:heading.centerYAnchor),controls.leadingAnchor.constraint(greaterThanOrEqualTo:title.trailingAnchor,constant:8)])
        add(heading)
        let register:(String,NSTextField)->Void = { [weak self] key,label in self?.attributeNumbers.append((key,label)) }
        let registerRole:(String,RoleAttributeRow)->Void = { [weak self] key,row in self?.roleRows.append((key,row)) }
        var physicalColumn=attrColumn("Physical",keys:physical,values:p.visibleAttributes,register:register,registerRole:registerRole)
        if !p.traits.mapped.isEmpty || !p.traits.unresolvedBits.isEmpty {
            let traits=stack([text("PLAYER TRAITS",size:10,weight:.semibold,color:Palette.muted)],spacing:6)
            if !p.traits.mapped.isEmpty {
                traits.addArrangedSubview(text(p.traits.mapped.map(\.name).joined(separator:" · "),size:11.5,wrap:true))
            }
            if !p.traits.unresolvedBits.isEmpty {
                traits.addArrangedSubview(text("Unresolved trait bits: "+p.traits.unresolvedBits.map(String.init).joined(separator:", "),size:10,color:Palette.muted,wrap:true))
            }
            for view in traits.arrangedSubviews {
                fillWidth(view,traits)
                view.setContentCompressionResistancePriority(.required,for:.vertical)
            }
            // Explicit top anchors keep surplus card height below traits, never
            // between Physical and its heading. Match attrColumn's fixed rows.
            let column=NSView();column.translatesAutoresizingMaskIntoConstraints=false
            column.addSubview(physicalColumn);column.addSubview(traits)
            traits.setHuggingPriority(.required,for:.vertical)
            let naturalBottom=column.bottomAnchor.constraint(equalTo:traits.bottomAnchor)
            naturalBottom.priority=NSLayoutConstraint.Priority(249)
            NSLayoutConstraint.activate([
                physicalColumn.topAnchor.constraint(equalTo:column.topAnchor),
                physicalColumn.leadingAnchor.constraint(equalTo:column.leadingAnchor),
                physicalColumn.trailingAnchor.constraint(equalTo:column.trailingAnchor),
                physicalColumn.heightAnchor.constraint(equalToConstant:AttributeGeometry.headingHeight+AttributeGeometry.rowHeight*CGFloat(physical.count)),
                traits.topAnchor.constraint(equalTo:physicalColumn.bottomAnchor,constant:AttributeGeometry.traitsGap),
                traits.leadingAnchor.constraint(equalTo:column.leadingAnchor),
                traits.trailingAnchor.constraint(equalTo:column.trailingAnchor),
                column.bottomAnchor.constraint(greaterThanOrEqualTo:traits.bottomAnchor),
                naturalBottom
            ])
            physicalColumn=column
        }
        add(padded(attributeGroup([attrColumn("Technical",keys:technical,values:p.visibleAttributes,register:register,registerRole:registerRole),attrColumn("Mental",keys:mental,values:p.visibleAttributes,register:register,registerRole:registerRole),physicalColumn]),inset:10))
        if p.isKeeper {
            let keys=goalkeeper.filter {!technical.contains($0)}
            let body=attributeGroup([attrColumn("",keys:Array(keys.prefix(6)),values:p.visibleAttributes,register:register,registerRole:registerRole),attrColumn("",keys:Array(keys.dropFirst(6)),values:p.visibleAttributes,register:register,registerRole:registerRole)])
            add(padded(DisclosureSection("GOALKEEPING · \(keys.count) attributes",body:body,expanded:true),inset:8))
        }
        label("HIDDEN ATTRIBUTES")
        var scouting=p.hiddenAttributes;p.personalityComponents.forEach {scouting[$0.key]=$0.value}
        add(attributeGroup([attrColumn("",keys:["consistency","important_matches","injury_proneness","versatility","adaptability"],values:scouting),attrColumn("",keys:["ambition","loyalty","pressure","professionalism","sportsmanship"],values:scouting),attrColumn("",keys:["temperament","controversy","dirtiness"],values:scouting)]))
        if p.fieldStatus["reputation"] == "verified" {add(metadataRow([("Home Reputation",p.reputation.home.map(String.init) ?? "Unresolved"),("Current Reputation",p.reputation.current.map(String.init) ?? "Unresolved"),("World Reputation",p.reputation.world.map(String.init) ?? "Unresolved")]))}
        else {add(text("Reputation · raw  "+p.reputation.rawSlots.map(String.init).joined(separator:" / ")+"  · Values unresolved",size:10,color:Palette.muted,wrap:true))}
        updateProjectedValues();updateRoleHighlights()
        content.layoutSubtreeIfNeeded();contentView.scroll(to:.zero);reflectScrolledClipView(contentView)
    }
}

final class RuleView:NSStackView {
    let choice=NSPopUpButton();let minimum=NSTextField();let maximum=NSTextField();let remove=NSButton()
    let source:NumericRule.Source
    let keys:[String]
    init(source:NumericRule.Source,target:AnyObject,action:Selector,delete:Selector){
        self.source=source;keys=(source == .component ? personality : (source == .hidden ? hidden : Array(Set(technical+mental+physical+goalkeeper)))).sorted()
        super.init(frame:.zero);orientation = .horizontal;alignment = .centerY;spacing=8;translatesAutoresizingMaskIntoConstraints=false
        let label=text(source == .component ? "Personality" : (source == .hidden ? "Hidden" : "Attribute"),size:10,color:Palette.muted)
        label.widthAnchor.constraint(equalToConstant:68).isActive=true
        remove.image=NSImage(systemSymbolName:"xmark.circle",accessibilityDescription:"Remove condition");remove.isBordered=false;remove.target=target;remove.action=delete;remove.toolTip="Remove this condition"
        remove.widthAnchor.constraint(equalToConstant:22).isActive=true
        choice.addItems(withTitles:keys.map(title));choice.target=target;choice.action=action;choice.controlSize = .small;choice.font = .systemFont(ofSize:11);choice.setAccessibilityLabel("Attribute name")
        choice.setContentHuggingPriority(.defaultLow,for:.horizontal)
        for (input,edge) in [(minimum,"Min"),(maximum,"Max")] {
            input.placeholderString="Any";input.controlSize = .small;input.font = .systemFont(ofSize:11);input.target=target;input.action=action;input.widthAnchor.constraint(equalToConstant:74).isActive=true;input.setAccessibilityLabel(edge+" attribute rating")
        }
        [label,choice,text("Min",size:10,color:Palette.muted),minimum,text("Max",size:10,color:Palette.muted),maximum,remove].forEach {addArrangedSubview($0)}
    }
    required init?(coder:NSCoder){fatalError()}
}

final class PlayerNameCell:NSTableCellView {
    let club=text("",size:10,color:Palette.muted)
    override init(frame:NSRect){super.init(frame:frame)
        let name=text("",size:12,weight:.medium);textField=name;addSubview(name);addSubview(club)
        NSLayoutConstraint.activate([name.leadingAnchor.constraint(equalTo:leadingAnchor,constant:7),name.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-4),name.topAnchor.constraint(equalTo:topAnchor,constant:2),club.leadingAnchor.constraint(equalTo:name.leadingAnchor),club.trailingAnchor.constraint(equalTo:name.trailingAnchor),club.topAnchor.constraint(equalTo:name.bottomAnchor,constant:1)])
    }
    convenience init(){self.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError()}
}
