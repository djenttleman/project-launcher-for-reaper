// ReaSet Selector — selector de proyectos para REAPER
// AppKit + WKWebView. La UI vive en Resources/selector.html (kit ReaSet).
// Todo el estado del launcher vive en ~/Library/Application Support/ReaSet Selector/

import Cocoa
import WebKit
import UniformTypeIdentifiers
import ApplicationServices

// MARK: - Modelo

struct Project: Codable {
    var id: String
    var path: String
    var name: String
    var folder: String
    var tags: [String]
    var pinned: Bool = false
    var hidden: Bool = false
    var archived: Bool = false
    var lastOpened: Double
    var addedAt: Double = Date().timeIntervalSince1970
    var type: String = "studio"      // show | studio | template | lab | archive
    // caché del escaneo del .rpp (se invalida por mtime + tamaño)
    var regions: Int? = nil
    var tracks: Int? = nil
    var tempo: Double? = nil
    var scanMtime: Double? = nil
    var scanSize: Int64? = nil
    var backups: [Backup]? = nil
    /// false cuando el .rpp ya no está en `path` (se movió o lo borraron).
    var exists: Bool? = nil
}

struct Backup: Codable {
    var name: String
    var path: String
    var date: Double
    var size: Int64
}

struct FolderMeta: Codable {
    var color: String?
    var icon: String?
}

struct Library: Codable {
    var projects: [Project] = []
    var folders: [String] = ["Shows", "Estudio", "Laboratorio", "Plantillas"]
    var folderMeta: [String: FolderMeta]? = [:]
    /// Rutas quitadas a mano del launcher: no vuelven a entrar solas.
    var ignored: [String]? = []
    var version: Int = 2
}

struct Prefs: Codable {
    var theme = "dark"
    var accent = "reapertips"
    var lang = "es"
    var slim: Bool? = nil        // opcional: los prefs viejos no lo traen
}

struct Usage: Codable {
    var secondsOpen: Double = 0
    var secondsRec: Double = 0
    var updatedAt: Double = 0
}

// MARK: - Almacén

final class Store {
    let root: URL
    let libraryURL: URL
    let usageURL: URL
    let prefsURL: URL
    var library: Library
    var usage: Usage
    var prefs: Prefs
    var hasPrefsFile = false
    private var scanCache: [String: (mtime: Double, size: Int64, regions: Int, tracks: Int, tempo: Double?)] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Project Launcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        libraryURL = root.appendingPathComponent("library.json")
        usageURL = root.appendingPathComponent("usage.json")
        prefsURL = root.appendingPathComponent("prefs.json")

        // migración desde nombres anteriores del launcher (el más nuevo primero)
        for prev in ["ReaLauncher", "ReaSet Selector"] {
            let old = base.appendingPathComponent(prev, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: libraryURL.path),
                  FileManager.default.fileExists(atPath: old.path) else { continue }
            for f in ["library.json", "usage.json", "prefs.json"] {
                try? FileManager.default.copyItem(at: old.appendingPathComponent(f),
                                                  to: root.appendingPathComponent(f))
            }
        }

        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: libraryURL),
           let lib = try? dec.decode(Library.self, from: data) {
            library = lib
        } else {
            library = Library()
        }
        if let data = try? Data(contentsOf: usageURL),
           let u = try? dec.decode(Usage.self, from: data) {
            usage = u
        } else {
            usage = Usage()
        }
        if let data = try? Data(contentsOf: prefsURL),
           let pr = try? dec.decode(Prefs.self, from: data) {
            prefs = pr
            hasPrefsFile = true
        } else {
            prefs = Prefs()
            hasPrefsFile = false
        }
        if library.projects.isEmpty { seedFromReaperRecents() }
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(library) { try? d.write(to: libraryURL) }
    }

    func savePrefs() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(prefs) { try? d.write(to: prefsURL) }
    }

    /// Primera ejecución: toma la lista de recientes de REAPER.ini y arma la biblioteca.
    func seedFromReaperRecents() {
        let ini = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/REAPER/REAPER.ini")
        guard let text = try? String(contentsOf: ini, encoding: .utf8) else { return }
        var seen = Set<String>()
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("recent"), let eq = line.firstIndex(of: "=") else { continue }
            let path = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard path.lowercased().hasSuffix(".rpp"), !seen.contains(path) else { continue }
            guard !(library.ignored ?? []).contains(path) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            seen.insert(path)
            var p = makeProject(path: path)
            p.lastOpened = modDate(path)
            library.projects.append(p)
        }
        library.projects.sort { $0.lastOpened > $1.lastOpened }
        save()
    }

    func makeProject(path: String) -> Project {
        let url = URL(fileURLWithPath: path)
        var p = Project(id: UUID().uuidString, path: path,
                        name: url.deletingPathExtension().lastPathComponent,
                        folder: defaultFolder(for: path), tags: [],
                        lastOpened: Date().timeIntervalSince1970)
        p.type = guessType(path)
        return p
    }

    func defaultFolder(for path: String) -> String {
        if path.contains("RetroDivergentes") { return "Shows" }
        if path.contains("Yoin") { return "Estudio" }
        if path.contains("ReaSet-Pro") || path.contains("/tmp/") { return "Laboratorio" }
        if path.contains("ProjectTemplates") { return "Plantillas" }
        return "Estudio"
    }

    func guessType(_ path: String) -> String {
        let l = path.lowercased()
        if l.contains("projecttemplates") { return "template" }
        if l.contains("reaset-pro") || l.contains("/tmp/") { return "lab" }
        if l.contains("setlist") || l.contains("rdv") || l.contains("live") { return "show" }
        return "studio"
    }

    func modDate(_ path: String) -> Double {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
    }

    /// Lectura liviana del .rpp: regiones, pistas, tempo.
    /// Lee como máximo 4 MB (FileHandle) y cachea por ruta+mtime+tamaño: sin esto
    /// un .rpp de cientos de MB bloquea la app en cada refresco.
    func scan(_ path: String) -> (regions: Int, tracks: Int, tempo: Double?, size: Int64) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        if let c = scanCache[path], c.mtime == mtime, c.size == size {
            return (c.regions, c.tracks, c.tempo, size)
        }

        guard let fh = FileHandle(forReadingAtPath: path) else { return (0, 0, nil, size) }
        var data = fh.readData(ofLength: 4_000_000)
        try? fh.close()
        if data.isEmpty { return (0, 0, nil, size) }

        // REAPER puede guardar .rpp comprimido con zlib (cabecera 0x78)
        if data[0] == 0x78, let inflated = try? (data as NSData).decompressed(using: .zlib) {
            data = inflated as Data
        }
        guard let text = String(data: data, encoding: .isoLatin1) else {
            return (0, 0, nil, size)
        }
        var regions = 0, tracks = 0
        var tempo: Double? = nil
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("<REGION") { regions += 1 }
            else if l.hasPrefix("<TRACK") { tracks += 1 }
            else if tempo == nil, l.hasPrefix("TEMPO ") {
                let parts = l.split(separator: " ")
                if parts.count > 1, let v = Double(parts[1]) { tempo = v }
            }
        }
        scanCache[path] = (mtime, size, regions, tracks, tempo)
        return (regions, tracks, tempo, size)
    }

    /// Copias de seguridad que REAPER dejó junto al proyecto.
    func backups(for path: String) -> [[String: Any]] {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        return items
            .filter { $0.lastPathComponent.hasPrefix(base + "-bak") || $0.lastPathComponent.hasPrefix(base + ".bak") }
            .compactMap { u -> [String: Any]? in
                let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
                let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return ["name": u.lastPathComponent, "path": u.path, "date": date, "size": size]
            }
            .sorted { ($0["date"] as? Double ?? 0) > ($1["date"] as? Double ?? 0) }
    }

    func projectJSON(_ p: Project) -> [String: Any] {
        // Cero I/O en el hilo principal: el tamaño sale de la caché del escaneo.
        // Un solo stat sobre un volumen lento bloqueaba el arranque varios segundos.
        let size = p.scanSize ?? 0
        return [
            "id": p.id, "path": p.path, "name": p.name, "folder": p.folder,
            "tags": p.tags, "pinned": p.pinned, "hidden": p.hidden, "archived": p.archived,
            "lastOpened": p.lastOpened, "type": p.type,
            "mtime": p.scanMtime ?? 0, "exists": p.exists ?? true,
            "regions": p.regions ?? 0, "tracks": p.tracks ?? 0,
            "tempo": p.tempo ?? NSNull(), "size": size,
            "backups": (p.backups ?? []).map {
                ["name": $0.name, "path": $0.path, "date": $0.date, "size": $0.size]
            }
        ]
    }

    /// Escanea en segundo plano los .rpp que cambiaron y aplica el resultado en
    /// el hilo principal. Antes esto corría dentro de snapshot() y costaba ~1,2 s.
    func refreshScans(completion: @escaping (Bool) -> Void) {
        let snapshotProjects = library.projects
        DispatchQueue.global(qos: .utility).async {
            var results: [(String, Int, Int, Double?, Double, Int64, [Backup], Bool)] = []
            for p in snapshotProjects {
                let attrs = try? FileManager.default.attributesOfItem(atPath: p.path)
                let existe = (attrs != nil)
                if p.exists != existe {
                    // cambió la existencia: se refleja aunque no haya que re-escanear
                    results.append((p.id, p.regions ?? 0, p.tracks ?? 0, p.tempo,
                                    p.scanMtime ?? 0, p.scanSize ?? 0, p.backups ?? [], existe))
                }
                let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let needsScan = (p.scanMtime != mtime || p.scanSize != size)
                let needsBk = (p.backups == nil)
                if !needsScan && !needsBk { continue }
                let t0 = Date()
                let s = needsScan ? self.scan(p.path) : (p.regions ?? 0, p.tracks ?? 0, p.tempo, size)
                let dt = Date().timeIntervalSince(t0)
                if dt > 1.0 { NSLog("escaneo lento: %@ %.1f s", p.name, dt) }
                let bk: [Backup] = needsBk ? self.backups(for: p.path).compactMap { d in
                    guard let name = d["name"] as? String, let path = d["path"] as? String else { return nil }
                    return Backup(name: name, path: path,
                                  date: d["date"] as? Double ?? 0, size: d["size"] as? Int64 ?? 0)
                } : (p.backups ?? [])
                results.append((p.id, s.0, s.1, s.2, mtime, size, bk, existe))
            }
            guard !results.isEmpty else { DispatchQueue.main.async { completion(false) }; return }
            DispatchQueue.main.async {
                for r in results {
                    if let i = self.library.projects.firstIndex(where: { $0.id == r.0 }) {
                        self.library.projects[i].regions = r.1
                        self.library.projects[i].tracks = r.2
                        self.library.projects[i].tempo = r.3
                        self.library.projects[i].scanMtime = r.4
                        self.library.projects[i].scanSize = r.5
                        self.library.projects[i].backups = r.6
                        self.library.projects[i].exists = r.7
                    }
                }
                self.save()
                completion(true)
            }
        }
    }

    func snapshot() -> [String: Any] {
        var tags = Set<String>()
        library.projects.forEach { $0.tags.forEach { tags.insert($0) } }
        // JSONSerialization no acepta structs Swift: se aplana a [String: String]
        var metaPlain: [String: [String: String]] = [:]
        for (k, v) in (library.folderMeta ?? [:]) {
            var d: [String: String] = [:]
            if let c = v.color { d["color"] = c }
            if let ic = v.icon { d["icon"] = ic }
            metaPlain[k] = d
        }
        return [
            "home": NSHomeDirectory(),
            "projects": library.projects.map { projectJSON($0) },
            "folders": library.folders,
            "folderMeta": metaPlain,
            "tags": Array(tags).sorted(),
            "usage": ["hoursOpen": usage.secondsOpen / 3600.0,
                      "hoursRec": usage.secondsRec / 3600.0],
            "reaperRunning": NSRunningApplication.runningApplications(withBundleIdentifier: "com.cockos.reaper").count > 0
        ]
    }
}

// MARK: - App

@main
enum SelectorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let store = Store()
    let launchAt = Date()
    var currentMsgId: Int?
    var windowShown = false
    var fullFrame: NSRect?
    var quitReaperRequested = false
    var cover: NSView?

    @objc func quitAll(_ sender: Any?) {
        quitReaperRequested = true
        NSApp.terminate(nil)
    }

    /// Cmd+Q cierra el launcher y además pide a REAPER que salga (cierre ordenado:
    /// REAPER puede mostrar su diálogo de guardado si hay cambios).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitReaperRequested,
           let reaper = NSRunningApplication.runningApplications(withBundleIdentifier: "com.cockos.reaper").first,
           !reaper.isTerminated {
            _ = reaper.terminate()
        }
        return .terminateNow
    }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de Project Launcher",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Project Launcher",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir y cerrar REAPER", action: #selector(quitAll(_:)), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Edición: sin esto Cmd+C/V/X no funcionan en el buscador ni en los campos
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // REAPER arrancó con un proyecto ya cargado (doble clic en Finder, ReaSet…):
        // no se abre ninguna ventana, sólo se descarta el aviso de licencia.
        soloAyudante = CommandLine.arguments.contains("--solo-ayudante")

        buildMenu()

        if soloAyudante {
            NSApp.setActivationPolicy(.accessory)
            guard startQuietWatcher() else { NSApp.terminate(nil); return }
            // Red de seguridad: si el aviso no aparece, la app no se queda colgada.
            soloTimeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { _ in
                NSApp.terminate(nil)
            }
            return
        }

        // Sin icono en el Dock: la app corre como agente (LSUIElement). Al no haber
        // barra de menú, los atajos se resuelven con un monitor local.
        NSApp.setActivationPolicy(.accessory)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": self.quitAll(nil); return nil
            case "w": self.window?.performClose(nil); return nil
            case "c": NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self); return nil
            case "v": NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self); return nil
            case "x": NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self); return nil
            case "a": NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self); return nil
            case "z": NSApp.sendAction(Selector(("undo:")), to: nil, from: self); return nil
            default: return event
            }
        }
        // Color del cromo = --rk-bg-1 del tema guardado, para que el primer frame
        // ya salga con el color correcto (sin flash blanco ni salto de tema).
        let bgHex = store.prefs.theme == "light" ? "#FAFAFB" : "#121212"
        let bg = Self.color(fromHex: bgHex) ?? NSColor(srgbRed: 18/255, green: 18/255, blue: 18/255, alpha: 1)

        let rect = NSRect(x: 0, y: 0, width: 1512, height: 944)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Project Launcher"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = bg
        if #available(macOS 11.0, *) { window.titlebarSeparatorStyle = .none }
        window.minSize = NSSize(width: 900, height: 600)
        window.isRestorable = false

        // Marco guardado (se migra la clave anterior una sola vez)
        if window.setFrameUsingName("ProjectLauncherWindow") == false {
            if window.setFrameUsingName("ReaSetSelectorWindow") {
                window.setFrameAutosaveName("ProjectLauncherWindow")
            } else {
                window.center()
            }
        }
        // El modo slim no debe quedar como tamaño guardado: si el marco restaurado
        // es menor que el mínimo del modo completo, se vuelve al tamaño por defecto.
        if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            var f = window.frame
            f.size = NSSize(width: 1256, height: 783)
            window.setFrame(f, display: false)
            window.center()
        }
        window.setFrameAutosaveName("ProjectLauncherWindow")
        if store.prefs.slim == true {
            // Arranca ya angosto: el marco completo queda guardado para volver con FULL.
            setSlimWindow(true, animate: false, persist: false)
        }

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "sel")
        // El tema y el acento se aplican ANTES del primer pintado: cero parpadeo.
        if store.hasPrefsFile {
            let boot = "document.documentElement.dataset.theme='\(store.prefs.theme)';"
                     + "document.documentElement.dataset.accent='\(store.prefs.accent)';"
                     + "document.documentElement.dataset.lang='\(store.prefs.lang)';"
                     + (store.prefs.slim == true ? "document.documentElement.dataset.slim='1';" : "")
                     + "document.documentElement.lang='\(store.prefs.lang)';"
                     + "document.documentElement.style.backgroundColor='\(bgHex)';"
            cfg.userContentController.addUserScript(
                WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        web = WKWebView(frame: window.contentView?.bounds ?? rect, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.uiDelegate = self
        web.navigationDelegate = self
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = bg }

        if let url = Bundle.main.url(forResource: "selector", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("selector.html no encontrado en el bundle")
        }

        // Contenedor con el color del tema + una capa encima del WebView: aunque
        // WebKit pinte su blanco inicial, nunca queda expuesto en pantalla.
        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = bg.cgColor
        web.frame = container.bounds
        container.addSubview(web)
        let cover = NSView(frame: container.bounds)
        cover.wantsLayer = true
        cover.layer?.backgroundColor = bg.cgColor
        cover.autoresizingMask = [.width, .height]
        container.addSubview(cover)
        self.cover = cover
        window.contentView = container
        // Ahora que la ventana existe (y su marco es el definitivo) se lanza el
        // vigilante del aviso de licencia: REAPER lo muestra ~1 s después.
        startQuietWatcher()

        // La ventana se muestra recién cuando la UI está pintada (ver revealWindow()).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.revealWindow(reason: "timeout")
        }
    }

    func revealWindow(reason: String) {
        guard !windowShown else { return }
        windowShown = true
        // Modo invisible (--solo-ayudante): no hay ventana que mostrar.
        guard let window = window else { return }
        cover?.removeFromSuperview()
        cover = nil
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()     // también cuando lo lanza REAPER al arrancar
        // REAPER sigue arrancando cuando aparecemos y recupera el foco un par de
        // segundos después. Se reclama el teclado hasta quedar al frente.
        claimAttempts = 0
        claimFocus()
        claimTimer?.invalidate()
        claimTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.claimFocus()
        }
        NSApp.activate(ignoringOtherApps: true)
        // Como agente (sin Dock) macOS a veces no activa la app sola: se pide dos veces.
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if #available(macOS 14.0, *) { NSApp.activate() }   // API cooperativa de Sonoma
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSLog("foco tras mostrar: %@", NSApp.isActive ? "sí" : "no")
        }
        NSLog("ventana visible (%@) a los %.2f s", reason, Date().timeIntervalSince(launchAt))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("selector.html listo a los %.2f s", Date().timeIntervalSince(launchAt))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("fallo al cargar: %@", error.localizedDescription)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: puente JS

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }
        // WKWebView entrega los números como NSNumber: `as? Int` puede fallar y
        // entonces la respuesta sale sin _id y la promesa del JS nunca resuelve.
        currentMsgId = (body["id"] as? NSNumber)?.intValue
            ?? (body["id"] as? Int)
            ?? Int(body["id"] as? String ?? "")

        switch cmd {
        case "list":
            let t0 = Date()
            let snap = store.snapshot()
            NSLog("snapshot en %.0f ms", Date().timeIntervalSince(t0) * 1000)
            reply(snap)
            // el escaneo de los .rpp ya no bloquea: se hace después y se empuja en silencio
            self.store.refreshScans { [weak self] changed in
                guard let self = self, changed, self.windowShown else { return }
                self.push(self.store.snapshot())
            }

        case "open", "openWith":
            guard let path = body["path"] as? String else { return }
            let mode = (body["mode"] as? String) ?? "normal"
            if let i = store.library.projects.firstIndex(where: { $0.path == path }) {
                store.library.projects[i].lastOpened = Date().timeIntervalSince1970
                store.save()
            }
            openInReaper(path, mode: mode)

        case "fxonline":
            sendCommand("fxonline")

        case "slim":
            setSlimWindow((body["on"] as? Bool) ?? false)

        case "reveal":
            if let path = body["path"] as? String {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }

        case "pickFolder":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Elegir"
            reply(["path": panel.runModal() == .OK ? (panel.url?.path ?? "") : ""])

        case "pickProject":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [UTType(filenameExtension: "rpp") ?? .data]
            panel.prompt = "Abrir"
            guard panel.runModal() == .OK, let url = panel.url else { reply(["path": ""]); return }
            let quitado = (store.library.ignored ?? []).contains(url.path)
            if !quitado && !store.library.projects.contains(where: { $0.path == url.path }) {
                store.library.projects.append(store.makeProject(path: url.path))
                store.save()
            }
            openInReaper(url.path)

        case "relocate":
            // El .rpp se movió de sitio: se vuelve a apuntar el mismo proyecto,
            // conservando id, carpetas del launcher, etiquetas y fecha de apertura.
            guard let id = body["id"] as? String,
                  let i = store.library.projects.firstIndex(where: { $0.id == id }) else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [UTType(filenameExtension: "rpp") ?? .data]
            panel.prompt = "Ubicar"
            panel.message = NSLocalizedString("Elige el .rpp en su nueva ubicación", comment: "")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            store.library.projects[i].path = url.path
            store.library.projects[i].name = url.deletingPathExtension().lastPathComponent
            store.library.projects[i].exists = true
            store.library.projects[i].scanMtime = nil      // fuerza re-escaneo
            store.library.projects[i].scanSize = nil
            store.library.projects[i].type = store.guessType(url.path)
            store.save()
            reply(store.projectJSON(store.library.projects[i]))

        case "create":
            guard let name = body["name"] as? String, let dir = body["dir"] as? String else { return }
            let type = body["type"] as? String ?? "studio"
            let tags = body["tags"] as? [String] ?? []
            let folder = body["folder"] as? String ?? "Estudio"
            let template = body["template"] as? String ?? ""

            let fm = FileManager.default
            let target = URL(fileURLWithPath: dir).appendingPathComponent(name + ".rpp")
            try? fm.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)

            var created = false
            let tplRoot = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/REAPER/ProjectTemplates")
            if !template.isEmpty {
                let tpl = tplRoot.appendingPathComponent(template)
                if fm.fileExists(atPath: tpl.path) {
                    try? fm.copyItem(at: tpl, to: target); created = true
                }
            }
            if !created {
                let skeleton = "<REAPER_PROJECT 0.1 \"7.82/macOS-arm64\" 1750000000\n  TEMPO 120 4 4\n  <TRACK\n  >\n>\n"
                try? skeleton.write(to: target, atomically: true, encoding: .utf8)
            }
            var p = store.makeProject(path: target.path)
            p.type = type; p.tags = tags; p.folder = folder
            p.lastOpened = Date().timeIntervalSince1970
            store.library.projects.append(p)
            if !store.library.folders.contains(folder) { store.library.folders.append(folder) }
            store.save()
            reply(["path": target.path])
            openInReaper(target.path)

        case "update":
            guard let id = body["id"] as? String,
                  let i = store.library.projects.firstIndex(where: { $0.id == id }) else { return }
            if let v = body["pinned"] as? Bool { store.library.projects[i].pinned = v }
            if let v = body["hidden"] as? Bool { store.library.projects[i].hidden = v }
            if let v = body["archived"] as? Bool { store.library.projects[i].archived = v }
            if let v = body["folder"] as? String { store.library.projects[i].folder = v }
            if let v = body["tags"] as? [String] { store.library.projects[i].tags = v }
            store.save()
            reply(["ok": true])

        case "delete":
            guard let id = body["id"] as? String,
                  let i = store.library.projects.firstIndex(where: { $0.id == id }) else {
                reply(["ok": false, "error": "no encontrado"]); return
            }
            let victim = store.library.projects[i]
            var trashed = false
            var errMsg = ""
            var resulting: NSURL?
            if FileManager.default.fileExists(atPath: victim.path) {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: victim.path),
                                                      resultingItemURL: &resulting)
                    trashed = true
                } catch {
                    errMsg = error.localizedDescription
                }
            }
            let gone = !FileManager.default.fileExists(atPath: victim.path)
            if gone {
                store.library.projects.removeAll { $0.id == id }
                store.save()
            }
            reply(["ok": gone, "trashed": trashed, "trashPath": resulting?.path ?? "", "error": errMsg])

        case "restoreProject":
            // Deshacer de "Quitar del launcher": vuelve la entrada y se borra el tombstone.
            guard let p = decodeProject(body["project"]) else { reply(["ok": false, "error": "proyecto inválido"]); return }
            if !store.library.projects.contains(where: { $0.path == p.path }) {
                store.library.projects.append(p)
            }
            store.library.ignored = (store.library.ignored ?? []).filter { $0 != p.path }
            store.save()
            reply(["ok": true])

        case "undelete":
            // Deshacer de "Eliminar proyecto": saca el .rpp de la Papelera y lo devuelve a su ruta.
            guard let path = body["path"] as? String else { reply(["ok": false, "error": "sin ruta"]); return }
            let trash = body["trashPath"] as? String ?? ""
            var moved = false
            let fm = FileManager.default
            if !trash.isEmpty, fm.fileExists(atPath: trash), !fm.fileExists(atPath: path) {
                do {
                    try fm.moveItem(at: URL(fileURLWithPath: trash), to: URL(fileURLWithPath: path))
                    moved = true
                } catch {
                    reply(["ok": false, "error": error.localizedDescription]); return
                }
            } else if fm.fileExists(atPath: path) {
                moved = true                       // el archivo ya estaba en su sitio
            }
            if !moved { reply(["ok": false, "error": "no está en la Papelera"]); return }
            if let p = decodeProject(body["project"]),
               !store.library.projects.contains(where: { $0.path == p.path }) {
                store.library.projects.append(p)
            }
            store.save()
            reply(["ok": true])

        case "forget":
            guard let id = body["id"] as? String else { return }
            if let victim = store.library.projects.first(where: { $0.id == id }) {
                var ign = store.library.ignored ?? []
                if !ign.contains(victim.path) { ign.append(victim.path) }
                store.library.ignored = ign
            }
            store.library.projects.removeAll { $0.id == id }
            store.save()
            reply(["ok": true])

        case "renameFolder":
            guard let from = body["from"] as? String, let to = body["to"] as? String, !to.isEmpty else {
                reply(["ok": false, "error": "nombre vacío"]); return
            }
            if let i = store.library.folders.firstIndex(of: from) {
                store.library.folders[i] = to
                if let meta = store.library.folderMeta?[from] {
                    store.library.folderMeta?[from] = nil
                    store.library.folderMeta?[to] = meta
                }
                for j in store.library.projects.indices where store.library.projects[j].folder == from {
                    store.library.projects[j].folder = to
                }
            }
            store.save()
            reply(["ok": true])

        case "setFolderMeta":
            guard let name = body["name"] as? String else { reply(["ok": false]); return }
            var meta = store.library.folderMeta?[name] ?? FolderMeta(color: nil, icon: nil)
            if let c = body["color"] as? String { meta.color = c.isEmpty ? nil : c }
            if let ic = body["icon"] as? String { meta.icon = ic.isEmpty ? nil : ic }
            var map = store.library.folderMeta ?? [:]
            map[name] = meta
            store.library.folderMeta = map
            store.save()
            reply(["ok": true])

        case "deleteFolder":
            guard let name = body["name"] as? String else { reply(["ok": false]); return }
            store.library.folders.removeAll { $0 == name }
            store.library.folderMeta?[name] = nil
            for j in store.library.projects.indices where store.library.projects[j].folder == name {
                store.library.projects[j].folder = "Sin carpeta"
            }
            if !store.library.folders.contains("Sin carpeta") {
                store.library.folders.append("Sin carpeta")
            }
            store.save()
            reply(["ok": true])

        case "ready":
            revealWindow(reason: "js")
            reply(["ok": true])

        case "prefs":
            if let t = body["theme"] as? String { self.store.prefs.theme = t }
            if let a = body["accent"] as? String { self.store.prefs.accent = a }
            if let l = body["lang"] as? String, l == "es" || l == "en" { self.store.prefs.lang = l }
            if let s = body["slim"] as? Bool { self.store.prefs.slim = s }
            store.savePrefs()
            reply(["ok": true])

        case "chrome":
            if let hex = body["color"] as? String, let c = Self.color(fromHex: hex) {
                window.backgroundColor = c
            }
            reply(["ok": true])

        case "addFolder":
            if let name = body["name"] as? String, !store.library.folders.contains(name) {
                store.library.folders.append(name); store.save()
            }
            reply(["ok": true])

        case "quit":
            NSApp.terminate(nil)

        default:
            reply(["error": "cmd desconocido: \(cmd)"])
        }
    }

    /// Reconstruye un Project desde el JSON que manda el JS (para deshacer).
    func decodeProject(_ raw: Any?) -> Project? {
        guard let raw = raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    static func color(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Envío sin solicitud previa (actualizaciones silenciosas).
    func push(_ payload: [String: Any]) {
        var p = payload
        p["_update"] = true
        guard JSONSerialization.isValidJSONObject(p),
              let data = try? JSONSerialization.data(withJSONObject: p),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__native(\(json));")
    }

    func reply(_ payload: [String: Any]) {
        var payload = payload
        if let cid = currentMsgId { payload["_id"] = cid }
        // Nunca dejar que un payload inválido aborte la app
        guard JSONSerialization.isValidJSONObject(payload) else {
            NSLog("payload no serializable: %@", payload.keys.sorted().joined(separator: ","))
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__native(\(json));")
    }

    /// Modo slim: la ventana se angosta a una lista y al volver recupera su marco.
    func setSlimWindow(_ on: Bool, animate: Bool = true, persist: Bool = true) {
        guard let w = window else { return }
        if on {
            guard fullFrame == nil else { return }
            fullFrame = w.frame
            w.setFrameAutosaveName("")                 // el tamaño slim no se guarda
            w.minSize = NSSize(width: 340, height: 420)
            let size = NSSize(width: 380, height: 620)
            var f = w.frame
            f.origin.x += (f.width - size.width) / 2
            f.origin.y += f.height - size.height       // conserva el borde superior
            f.size = size
            w.setFrame(f, display: true, animate: animate)
        } else if let f = fullFrame {
            fullFrame = nil
            w.minSize = NSSize(width: 900, height: 600)
            w.setFrame(f, display: true, animate: animate)
            w.setFrameAutosaveName("ProjectLauncherWindow")
        }
        if persist { store.prefs.slim = on; store.savePrefs() }
    }

    /// Insiste con la activación: al arrancar, REAPER se pone al frente después
    /// de nosotros y el buscador se queda sin teclado. Se rinde a los 4 s, y no
    /// pelea mientras el vigilante del nag necesita a REAPER al frente.
    func claimFocus() {
        claimAttempts += 1
        if quietPoll != nil || claimAttempts > 8 || NSApp.isActive {
            claimTimer?.invalidate(); claimTimer = nil
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
    }

    /// REAPER en evaluación abre su ventana de licencia alrededor de un segundo
    /// después de arrancar. Un vigilante (AppleScript) la manda fuera de pantalla
    /// antes de que se vea, espera a que el botón se habilite y la descarta, y al
    /// final devuelve el foco aquí. Con licencia instalada no se ejecuta nada.
    @discardableResult
    func startQuietWatcher() -> Bool {
        let license = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/REAPER/reaper-license.txt")
        if FileManager.default.fileExists(atPath: license.path) { return false }

        // El vigilante es LOCAL, no se distribuye: si el script no está (una
        // instalación de terceros) no se hace nada y nunca se pide permiso.
        let script = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Project Launcher/quiet-reaper.applescript")
        guard FileManager.default.fileExists(atPath: script.path) else { return false }

        guard AXIsProcessTrusted() else {
            NSLog("quiet-watcher: falta Accesibilidad, se pide el permiso")
            requestAccessibility()
            return false
        }
        quietWatcher?.terminate()
        // Con ventana se espera a que esté en pantalla (el aviso se esconde dentro
        // de ella y hace falta su marco). Sin ventana se arranca de inmediato.
        let espera = 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
            self?.launchQuietWatcher(script)
        }
        return true
    }

    private func launchQuietWatcher(_ script: URL) {
        // En modo invisible no hay ventana: se pasa un marco vacío y el script
        // usa su plan B (rincón fuera de cuadro).
        let w = window
        let f = w?.frame ?? .zero
        let pantalla = (w?.screen ?? NSScreen.main)?.frame.height ?? 0
        let arriba = Int(pantalla - (f.origin.y + f.height))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // 1: script, 2: presupuesto, 3-6: marco del launcher (x, y, ancho, alto)
        p.arguments = [script.path, "14", "\(Int(f.origin.x))", "\(arriba)",
                       "\(Int(f.width))", "\(Int(f.height))"]
        do { try p.run(); quietWatcher = p }
        catch { NSLog("no pude lanzar el vigilante del nag: \(error)"); return }

        // El vigilante deja una marca al terminar: en ese momento recuperamos
        // el foco (una app de agente no se puede activar por AppleScript).
        // La ventana aparece ya (con el color del tema) y por encima: así el aviso
        // de licencia queda tapado aunque todavía no se lo haya movido.
        if !soloAyudante, let w = w {
            if !windowShown { revealWindow(reason: "arranque") }
            w.level = .floating
            w.orderFrontRegardless()
        }

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Project Launcher")
        let flag = base.appendingPathComponent("quiet-done")
        let visto = base.appendingPathComponent("quiet-seen")

        quietPoll?.invalidate()
        quietPoll = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if FileManager.default.fileExists(atPath: flag.path) {
                try? FileManager.default.removeItem(at: flag)
                try? FileManager.default.removeItem(at: visto)
                timer.invalidate()
                self.quietPoll = nil
                self.soloTimeout?.invalidate()
                if self.soloAyudante {
                    NSApp.terminate(nil)
                    return
                }
                self.window?.level = .normal
                self.window?.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            if FileManager.default.fileExists(atPath: visto.path) {
                // El aviso ya está colocado detrás: recién ahora se sube de nivel.
                // En modo invisible no hay ventana que mostrar.
                if !self.soloAyudante {
                    if !self.windowShown { self.revealWindow(reason: "aviso de licencia") }
                    if self.window?.level != .floating { self.window?.level = .floating }
                    self.window?.orderFrontRegardless()
                }
            } else if self.quietWatcher?.isRunning == false {
                // El vigilante terminó sin dejar marca (aviso ausente o fallo):
                // no dejar la ventana flotando para siempre.
                try? FileManager.default.removeItem(at: visto)
                timer.invalidate()
                self.quietPoll = nil
                self.window?.level = .normal
            }
        }
    }

    /// Abre la petición de Accesibilidad del sistema para esta app.
    /// macOS muestra su propio aviso y lleva a Privacidad → Accesibilidad.
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        NSLog("accesibilidad: %@", trusted ? "concedida" : "pendiente")
    }

    /// REAPER está abierto en esta máquina.
    private var quietWatcher: Process?
    private var quietPoll: Timer?
    private var soloAyudante = false
    private var soloTimeout: Timer?
    private var claimTimer: Timer?
    private var claimAttempts = 0

    var reaperIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.cockos.reaper").isEmpty
    }

    /// Deja una orden en inbox.txt; el script de arranque la ejecuta dentro de REAPER.
    func sendCommand(_ line: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Project Launcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("inbox.txt")
        try? line.appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func openInReaper(_ path: String, mode: String = "normal") {
        // Con REAPER abierto, el flag -fxoffline no llega: se pide por el canal Lua.
        if reaperIsRunning {
            let cmd = (mode == "fxoffline" || mode == "fxoffline-online")
                ? "open \(mode) \(path)"
                : "open normal \(path)"
            sendCommand(cmd)
            NSApp.terminate(nil)
            return
        }
        startQuietWatcher()                 // REAPER arranca en frío: habrá nag
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        let url = URL(fileURLWithPath: path)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cockos.reaper") else {
            NSWorkspace.shared.open(url); NSApp.terminate(nil); return
        }
        if mode == "fxoffline" || mode == "fxoffline-online" {
            // -fxoffline es el flag documentado de REAPER para recovery mode.
            let exe = app.appendingPathComponent("Contents/MacOS/REAPER")
            let p = Process()
            p.executableURL = exe
            p.arguments = ["-fxoffline", path]
            try? p.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: cfg) { _, error in
            if let error = error { NSLog("open error: \(error)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }
}
