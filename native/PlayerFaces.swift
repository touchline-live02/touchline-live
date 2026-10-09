import AppKit
import ImageIO

/// Owns folder preferences, one asynchronous config index, and a small recent-face cache.
/// All public state/callbacks are used on the main thread; filesystem work stays on the worker.
final class PlayerFaceService:NSObject {
    static let preferenceKey="TouchlineGraphicsFolder"
    static let didChange=Notification.Name("TouchlinePlayerFacesChanged")
    private let defaults:UserDefaults
    private let worker=DispatchQueue(label:"Touchline.player-faces",qos:.utility)
    private var generation=0
    private var index:FacepackIndex?
    private final class CachedFace:NSObject {
        let image:NSImage?
        init(_ image:NSImage?) {self.image=image}
    }
    private let images=NSCache<NSNumber,CachedFace>()
    private(set) var folderPath=""
    private(set) var status="Choose a Football Manager graphics or facepack folder."
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults;super.init();images.countLimit=32
        if let path=defaults.string(forKey:Self.preferenceKey),!path.isEmpty {setFolder(path)}
    }
    func setFolder(_ path:String) {
        folderPath=path.trimmingCharacters(in:.whitespacesAndNewlines)
        if folderPath.isEmpty {defaults.removeObject(forKey:Self.preferenceKey)}
        else {defaults.set(folderPath,forKey:Self.preferenceKey)}
        generation+=1;let token=generation;index=nil;images.removeAllObjects()
        guard !folderPath.isEmpty else {
            status="Choose a Football Manager graphics or facepack folder.";publish();return
        }
        let root=URL(fileURLWithPath:folderPath,isDirectory:true)
        status="Indexing player faces…";publish()
        worker.async { [weak self] in
            guard let self=self else {return}
            let next=FacepackCache.load(root:root)?.index
            DispatchQueue.main.async { [weak self] in
                guard let self=self,self.generation==token else {return}
                self.index=next
                if let next=next {
                    self.status=next.count==0 ? "No player-face mappings found." : "\(next.count.formatted()) player-face mappings · Files stay in their original folder."
                    if next.malformedConfigurationCount>0 {self.status += " \(next.malformedConfigurationCount) unreadable or malformed configs skipped."}
                } else {self.status="Folder unavailable. Player faces are disabled."}
                self.publish()
            }
        }
    }
    private func publish() {NotificationCenter.default.post(name:Self.didChange,object:self)}
    func requestPlayerFace(id:Int,completion:@escaping (NSImage?)->Void) {
        let key=NSNumber(value:id)
        if let cached=images.object(forKey:key) {completion(cached.image);return}
        guard let index=index else {completion(nil);return}
        let token=generation
        worker.async { [weak self] in
            guard let self=self else {return}
            let image=index.resolvePlayerFace(id:id).flatMap {Self.thumbnail($0)}
            DispatchQueue.main.async { [weak self] in
                guard let self=self,self.generation==token else {return}
                self.images.setObject(CachedFace(image),forKey:key);completion(image)
            }
        }
    }
    private static func thumbnail(_ url:URL)->NSImage? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceThumbnailMaxPixelSize:156,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {return nil}
        return NSImage(cgImage:image,size:NSSize(width:CGFloat(image.width)/2,height:CGFloat(image.height)/2))
    }
}

/// A fixed profile-only slot. Async completion cannot replace a different player's image.
final class PlayerFaceView:NSImageView {
    private weak var service:PlayerFaceService?
    private let uid:Int
    private var observer:NSObjectProtocol?
    init(uid:Int,service:PlayerFaceService?) {
        self.uid=uid;self.service=service;super.init(frame:.zero)
        translatesAutoresizingMaskIntoConstraints=false;imageAlignment = .alignCenter;isEditable=false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant:78),heightAnchor.constraint(equalToConstant:78)])
        if let service=service {
            observer=NotificationCenter.default.addObserver(forName:PlayerFaceService.didChange,object:service,queue:.main) { [weak self] _ in self?.reload() }
        }
        reload()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit {if let observer=observer {NotificationCenter.default.removeObserver(observer)}}
    private func reload() {
        image=NSImage(systemSymbolName:"person.fill",accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:32,weight:.regular))
        imageScaling = .scaleProportionallyDown;contentTintColor=Palette.muted
        setAccessibilityLabel("Player face unavailable")
        service?.requestPlayerFace(id:uid) { [weak self] image in
            guard let self=self,let image=image else {return}
            self.image=image;self.contentTintColor=nil;self.imageScaling = .scaleProportionallyUpOrDown
            self.setAccessibilityLabel("Player face")
        }
    }
}
