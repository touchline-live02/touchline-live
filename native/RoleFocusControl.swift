import AppKit

/// One anchored native menu, with no dependency on player data or projection.
final class RoleFocusButton:NSButton {
    private var focus:RoleFocusState
    var onSelect:((String?)->Void)?
    init(focus:RoleFocusState) {
        self.focus=focus
        super.init(frame:.zero)
        bezelStyle = .rounded;controlSize = .small
        font = .systemFont(ofSize:11,weight:.medium)
        cell?.lineBreakMode = .byTruncatingTail
        target=self;action=#selector(openMenu)
        translatesAutoresizingMaskIntoConstraints=false
        // Long role names retain their full text in the tooltip and menu.
        widthAnchor.constraint(equalToConstant:155).isActive=true
        updateLabel()
    }
    required init?(coder:NSCoder){fatalError()}
    private func updateLabel() {
        title=focus.label
        // Pin the rendered title too, including after a role/menu selection.
        // Match Projected's 11-point medium text with the native button baseline.
        let titleFont=NSFont.systemFont(ofSize:11,weight:.medium)
        font=titleFont
        let paragraph=NSMutableParagraphStyle()
        paragraph.alignment = .center;paragraph.lineBreakMode = .byTruncatingTail
        attributedTitle=NSAttributedString(string:focus.label,attributes:[
            .font:titleFont,.foregroundColor:NSColor.labelColor,
            .paragraphStyle:paragraph,.baselineOffset:0
        ])
        toolTip=focus.label+" · Green: key attributes · Blue: preferable attributes"
        setAccessibilityLabel("Role focus: "+(focus.profile?.label ?? "None"))
    }
    @objc private func openMenu() {
        let menu=NSMenu();menu.autoenablesItems=false
        let clear=NSMenuItem(title:"Clear Role Focus",action:#selector(selectRole(_:)),keyEquivalent:"")
        clear.target=self;clear.state=focus.profileID == nil ? .on : .off
        menu.addItem(clear);menu.addItem(.separator())
        for group in RoleFocusCatalog.groups {
            let parent=NSMenuItem(title:group.name,action:nil,keyEquivalent:"")
            let roles=NSMenu();roles.autoenablesItems=false
            for role in group.roles {
                guard let profiles=RoleFocusCatalog.byRole[role],let first=profiles.first else {continue}
                if profiles.count == 1 {
                    roles.addItem(item(for:first,title:first.label))
                } else {
                    let roleItem=NSMenuItem(title:first.name,action:nil,keyEquivalent:"")
                    let duties=NSMenu();duties.autoenablesItems=false
                    for profile in profiles {duties.addItem(item(for:profile,title:profile.duty.name))}
                    roleItem.submenu=duties
                    roleItem.state=focus.profile?.role == role ? .on : .off
                    roles.addItem(roleItem)
                }
            }
            parent.submenu=roles;menu.addItem(parent)
        }
        menu.popUp(positioning:nil,at:NSPoint(x:bounds.minX,y:bounds.maxY+3),in:self)
    }
    private func item(for profile:RoleFocusProfile,title:String)->NSMenuItem {
        let item=NSMenuItem(title:title,action:#selector(selectRole(_:)),keyEquivalent:"")
        item.target=self;item.representedObject=profile.id
        item.state=focus.profileID == profile.id ? .on : .off
        return item
    }
    @objc private func selectRole(_ sender:NSMenuItem) {
        focus.select(sender.representedObject as? String)
        updateLabel();onSelect?(focus.profileID)
    }
}

/// Meaning-bearing role colours are independent of the branding accent and
/// attribute-number rating bands. Draw behind labels; never alter their colour.
final class RoleAttributeRow:NSView {
    var tier:RoleAttributeTier? {didSet {needsDisplay=true}}
    private static let keyColor=NSColor(calibratedRed:0.52,green:0.78,blue:0.49,alpha:1)
    private static let preferableColor=NSColor(calibratedRed:0.37,green:0.69,blue:0.88,alpha:1)
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        guard let tier=tier else {return}
        let color=tier == .key ? Self.keyColor : Self.preferableColor
        color.withAlphaComponent(tier == .key ? 0.19 : 0.17).setFill()
        bounds.fill()
        color.withAlphaComponent(0.85).setFill()
        NSRect(x:bounds.minX,y:bounds.minY,width:2,height:bounds.height).fill()
    }
}
