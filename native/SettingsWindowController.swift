import AppKit

// Owns preferences presentation; currency state stays with the existing app model.
// The supplied popup retains its original target/action and live cached options.
final class SettingsWindowController:NSWindowController,NSTextFieldDelegate {
    private var accentSwatches:[AccentSwatchButton]=[]
    private let playerFaces:PlayerFaceService
    private let graphicsPath=NSTextField()
    private let graphicsStatus=text("",size:11,color:Palette.muted,wrap:true)
    private var graphicsObserver:NSObjectProtocol?
    init(currencyPicker:NSPopUpButton,playerFaces:PlayerFaceService,relativeTo parent:NSWindow) {
        self.playerFaces=playerFaces
        let settings=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:210),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        settings.title="Settings";settings.isReleasedWhenClosed=false
        // Keep Settings in the active Space, including alongside Touchline's native full-screen window.
        settings.collectionBehavior.insert(.fullScreenAuxiliary)
        settings.collectionBehavior.insert(.moveToActiveSpace)
        settings.backgroundColor=Palette.background;settings.titlebarAppearsTransparent=true
        super.init(window:settings)
        // Separate section stacks keep additional preferences independent of Display.
        let sections=stack([],spacing:24)
        func addSection(_ title:String,views:[NSView]) {
            let section=stack([accentText(title,size:10,weight:.semibold)]+views,spacing:12)
            sections.addArrangedSubview(section);fillWidth(section,sections)
            views.forEach {fillWidth($0,section)}
        }
        addSection("DISPLAY",views:[text("Display currency",size:13,weight:.medium),currencyPicker,
            text("Monetary amounts use FM’s cached live currency table.",size:11,color:Palette.muted,wrap:true)])
        accentSwatches=AccentPreset.allCases.map {AccentSwatchButton($0,target:self,action:#selector(changeAccent(_:)))}
        let swatches=stack(accentSwatches,vertical:false,spacing:6)
        let appearance=stack([text("Accent Colour",size:13,weight:.medium),swatches],vertical:false,spacing:18)
        addSection("APPEARANCE",views:[appearance])
        graphicsPath.placeholderString="No graphics folder selected"
        graphicsPath.translatesAutoresizingMaskIntoConstraints=false
        graphicsPath.font = .systemFont(ofSize:11);graphicsPath.delegate=self
        graphicsPath.lineBreakMode = .byTruncatingMiddle
        graphicsPath.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let choose=NSButton(title:"Choose…",target:self,action:#selector(chooseGraphicsFolder))
        choose.bezelStyle = .rounded;choose.setContentCompressionResistancePriority(.required,for:.horizontal)
        let folderRow=stack([graphicsPath,choose],vertical:false,spacing:8)
        graphicsPath.widthAnchor.constraint(greaterThanOrEqualToConstant:260).isActive=true
        // Reserve room for asynchronous indexing/error messages without resizing Settings.
        graphicsStatus.heightAnchor.constraint(equalToConstant:40).isActive=true
        addSection("GRAPHICS",views:[text("Player faces",size:13,weight:.medium),folderRow,graphicsStatus])
        graphicsObserver=NotificationCenter.default.addObserver(forName:PlayerFaceService.didChange,object:playerFaces,queue:.main) { [weak self] _ in self?.updateGraphicsFolder() }
        updateGraphicsFolder()
        let content=NSView();settings.contentView=content;content.addSubview(sections)
        NSLayoutConstraint.activate([sections.topAnchor.constraint(equalTo:content.topAnchor,constant:24),sections.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),sections.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),sections.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-24)])
        content.layoutSubtreeIfNeeded()
        settings.setContentSize(NSSize(width:480,height:sections.fittingSize.height+48))
        settings.setFrameOrigin(NSPoint(x:parent.frame.midX-settings.frame.width/2,y:parent.frame.midY-settings.frame.height/2))
        // No main-window delegate: closing preferences must not terminate the app.
    }
    required init?(coder:NSCoder){fatalError()}
    deinit {if let graphicsObserver=graphicsObserver {NotificationCenter.default.removeObserver(graphicsObserver)}}
    private func updateGraphicsFolder() {
        // An indexing completion must not overwrite a new path the user is typing.
        if graphicsPath.currentEditor()==nil {graphicsPath.stringValue=playerFaces.folderPath}
        graphicsPath.toolTip=playerFaces.folderPath
        graphicsStatus.stringValue=playerFaces.status
    }
    func controlTextDidEndEditing(_ notification:Notification) {
        guard notification.object as? NSTextField === graphicsPath else {return}
        if graphicsPath.stringValue != playerFaces.folderPath {playerFaces.setFolder(graphicsPath.stringValue)}
    }
    @objc private func chooseGraphicsFolder() {
        guard let window=window else {return}
        let picker=NSOpenPanel();picker.title="Choose Football Manager graphics folder"
        picker.canChooseFiles=false;picker.canChooseDirectories=true;picker.allowsMultipleSelection=false
        picker.prompt="Choose"
        if !playerFaces.folderPath.isEmpty {picker.directoryURL=URL(fileURLWithPath:playerFaces.folderPath,isDirectory:true)}
        picker.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK,let url=picker.url else {return}
            self?.playerFaces.setFolder(url.path)
        }
    }
    @objc private func changeAccent(_ sender:AccentSwatchButton) {
        Palette.selectAccent(sender.preset)
        accentSwatches.forEach {$0.updateSelection()}
    }
}
