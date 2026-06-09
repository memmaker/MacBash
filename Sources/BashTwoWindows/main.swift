import Cocoa

final class CommandTextView: NSTextView {
    var executeHandler: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasControl = flags.contains(.control)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()

        let isControlE = hasControl && !hasCommand && !hasOption && (key == "e" || event.keyCode == 14)

        if isControlE {
            executeHandler?(string)
            return
        }

        super.keyDown(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inputWindow: NSWindow!
    private var outputWindow: NSWindow!

    private let inputTextView = CommandTextView(frame: .zero)
    private let outputTextView = NSTextView(frame: .zero)

    private var activeProcesses: [Process] = []
    private var workingDirectoryURL = AppDelegate.initialWorkingDirectoryURL()

    private let terminalFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private func setTerminalString(_ text: String, in textView: NSTextView) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: terminalAttributes
        )

        textView.textStorage?.setAttributedString(attributedText)
        textView.font = terminalFont
        textView.typingAttributes = terminalAttributes
    }

    @objc private func clearOutput(_ sender: Any?) {
        setTerminalString("", in: outputTextView)
    }

    private static func initialWorkingDirectoryURL() -> URL {
        let fileManager = FileManager.default

        if let pwd = ProcessInfo.processInfo.environment["PWD"],
           pwd.hasPrefix("/"),
           directoryExists(atPath: pwd, fileManager: fileManager) {
            return URL(fileURLWithPath: pwd, isDirectory: true)
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    private static func directoryExists(atPath path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    @objc private func chooseWorkingDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Choose Working Directory"
        panel.message = "Select the directory Bash commands should run from."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = workingDirectoryURL

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.setWorkingDirectory(selectedURL)
        }

        if let inputWindow {
            panel.beginSheetModal(for: inputWindow, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func setWorkingDirectory(_ url: URL) {
        workingDirectoryURL = url
        appendOutput("\n[Working directory: \(url.path)]\n")
    }

    private func configureTerminalTextView(_ textView: NSTextView, editable: Bool) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false

        textView.font = terminalFont
        textView.defaultParagraphStyle = terminalParagraphStyle
        textView.typingAttributes = terminalAttributes

        textView.isEditable = editable
        textView.isSelectable = true
        textView.allowsUndo = editable
        textView.usesFindPanel = true

        // Helpful for shell input: prevents quotes, dashes, spelling, etc. from being “helpfully” changed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.setAttributes(terminalAttributes, range: fullRange)
    }

    private lazy var terminalParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()

        // Makes tab output behave more like shell/code text.
        // Use 8 if you want classic terminal tab stops; use 4 if you prefer code-editor style.
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: terminalFont]).width
        style.tabStops = []
        style.defaultTabInterval = spaceWidth * 8

        return style
    }()

    private lazy var terminalAttributes: [NSAttributedString.Key: Any] = [
        .font: terminalFont,
        .foregroundColor: NSColor.textColor,
        .paragraphStyle: terminalParagraphStyle
    ]
    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        setUpWindows()
        NSApp.activate(ignoringOtherApps: true)
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for process in activeProcesses where process.isRunning {
            process.terminate()
        }
    }

    private func setUpWindows() {
        setTerminalString("""
        # Bash commands go here.
        # Press Ctrl+E to execute the whole text.

        pwd
        ls -la
        """, in: inputTextView)

        inputTextView.executeHandler = { [weak self] script in
            self?.executeInBash(script)
        }

        setTerminalString("Output will appear here.\n", in: outputTextView)
        outputTextView.isEditable = false
        outputTextView.isSelectable = true

        inputWindow = makeWindow(
            title: "Input - Ctrl+E executes Bash",
            frame: NSRect(x: 120, y: 460, width: 800, height: 360),
            contentView: makeScrollView(textView: inputTextView, editable: true)
        )

        outputWindow = makeWindow(
            title: "Output",
            frame: NSRect(x: 120, y: 80, width: 800, height: 360),
            contentView: makeScrollView(textView: outputTextView, editable: false)
        )

        inputWindow.makeKeyAndOrderFront(nil)
        outputWindow.orderFront(nil)
        inputWindow.makeFirstResponder(inputTextView)
    }

    private func makeWindow(title: String, frame: NSRect, contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.contentView = contentView
        return window
    }

    private func makeScrollView(textView: NSTextView, editable: Bool) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 360))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .bezelBorder

        textView.frame = scrollView.bounds
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]

        configureTerminalTextView(textView, editable: editable)

        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        return scrollView
    }

    private func executeInBash(_ script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            appendOutput("\n[Nothing to execute]\n")
            return
        }

        appendOutput("\n--- Bash execution ---\n")

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-s"]
        process.currentDirectoryURL = workingDirectoryURL

        var environment = ProcessInfo.processInfo.environment
        environment["PWD"] = workingDirectoryURL.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:~/homebrew/bin"

        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        activeProcesses.append(process)

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                self?.appendOutput("\n[Exit code \(finishedProcess.terminationStatus)]\n")
                self?.activeProcesses.removeAll { $0 === finishedProcess }
            }
        }

        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(script.utf8))
            stdin.fileHandleForWriting.closeFile()
        } catch {
            appendOutput("\nCould not start /bin/bash:\n\(error)\n")
            activeProcesses.removeAll { $0 === process }
        }
    }

    private func appendOutput(_ text: String) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: terminalAttributes
        )

        outputTextView.textStorage?.append(attributedText)
        outputTextView.scrollToEndOfDocument(nil)
    }

    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "BashTwoWindows")
        appMenu.addItem(
            withTitle: "Quit BashTwoWindows",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        let chooseWorkingDirectoryItem = NSMenuItem(
            title: "Choose Working Directory...",
            action: #selector(chooseWorkingDirectory(_:)),
            keyEquivalent: "o"
        )
        chooseWorkingDirectoryItem.keyEquivalentModifierMask = [.command]
        chooseWorkingDirectoryItem.target = self
        fileMenu.addItem(chooseWorkingDirectoryItem)
        fileMenuItem.submenu = fileMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())

        let clearOutputItem = NSMenuItem(
            title: "Clear Output",
            action: #selector(clearOutput(_:)),
            keyEquivalent: "c"
        )
        clearOutputItem.keyEquivalentModifierMask = [.control]
        clearOutputItem.target = self
        editMenu.addItem(clearOutputItem)

        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
