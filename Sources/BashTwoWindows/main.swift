import Cocoa

final class CommandTextView: NSTextView {
    var executeHandler: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasControl = flags.contains(.control)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()

        let isCommandE = hasCommand && !hasControl && !hasOption && (key == "e" || event.keyCode == 14)

        if isCommandE {
            executeHandler?(commandTextAtCursor())
            return
        }

        super.keyDown(with: event)
    }

    private func commandTextAtCursor() -> String {
        let buffer = string as NSString
        let bufferLength = buffer.length

        guard bufferLength > 0 else {
            return ""
        }

        let cursorLocation = min(selectedRange().location, bufferLength)
        let lookupLocation = cursorLocation == bufferLength ? bufferLength - 1 : cursorLocation

        var currentLineStart = 0
        var currentLineEnd = 0
        var currentContentsEnd = 0
        buffer.getLineStart(
            &currentLineStart,
            end: &currentLineEnd,
            contentsEnd: &currentContentsEnd,
            for: NSRange(location: lookupLocation, length: 0)
        )

        guard !Self.isCommandDelimiterLine(
            in: buffer,
            lineStart: currentLineStart,
            contentsEnd: currentContentsEnd
        ) else {
            return ""
        }

        let commandStart = Self.commandStart(
            in: buffer,
            beforeLineStartingAt: currentLineStart
        )
        let commandEnd = Self.commandEnd(
            in: buffer,
            afterLineEndingAt: currentLineEnd
        )
        let commandRange = NSRange(
            location: commandStart,
            length: max(0, commandEnd - commandStart)
        )

        let command = buffer.substring(with: commandRange)
        return Self.cleanedCommand(command)
    }

    private static func commandStart(in buffer: NSString, beforeLineStartingAt lineStart: Int) -> Int {
        var scanLineStart = lineStart

        while scanLineStart > 0 {
            var previousLineStart = 0
            var previousLineEnd = 0
            var previousContentsEnd = 0
            buffer.getLineStart(
                &previousLineStart,
                end: &previousLineEnd,
                contentsEnd: &previousContentsEnd,
                for: NSRange(location: scanLineStart - 1, length: 0)
            )

            if isCommandDelimiterLine(
                in: buffer,
                lineStart: previousLineStart,
                contentsEnd: previousContentsEnd
            ) {
                return previousLineEnd
            }

            guard previousLineStart < scanLineStart else {
                break
            }

            scanLineStart = previousLineStart
        }

        return 0
    }

    private static func commandEnd(in buffer: NSString, afterLineEndingAt lineEnd: Int) -> Int {
        var scanLocation = lineEnd

        while scanLocation < buffer.length {
            var nextLineStart = 0
            var nextLineEnd = 0
            var nextContentsEnd = 0
            buffer.getLineStart(
                &nextLineStart,
                end: &nextLineEnd,
                contentsEnd: &nextContentsEnd,
                for: NSRange(location: scanLocation, length: 0)
            )

            if isCommandDelimiterLine(
                in: buffer,
                lineStart: nextLineStart,
                contentsEnd: nextContentsEnd
            ) {
                return nextLineStart
            }

            guard nextLineEnd > scanLocation else {
                break
            }

            scanLocation = nextLineEnd
        }

        return buffer.length
    }

    private static func isCommandDelimiterLine(
        in buffer: NSString,
        lineStart: Int,
        contentsEnd: Int
    ) -> Bool {
        let lineLength = contentsEnd - lineStart

        guard lineLength >= 3 else {
            return false
        }

        return buffer.substring(with: NSRange(location: lineStart, length: 3)) == "###"
    }

    private static func cleanedCommand(_ command: String) -> String {
        var lines: [String] = []

        command.enumerateLines { line, _ in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                return
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    private static let worksheetFileName = ".worksheet.shw"
    private static let worksheetVersionLine = "worksheet-version=1"
    private static let worksheetFrameFormatLine = "frame-format=x,y,width,height"
    private static let inputWindowFrameLinePrefix = "input-window="
    private static let outputWindowFrameLinePrefix = "output-window="

    private var inputWindow: NSWindow!
    private var outputWindow: NSWindow!

    private let inputTextView = CommandTextView(frame: .zero)
    private let outputTextView = NSTextView(frame: .zero)

    private var activeProcesses: [Process] = []
    private var workingDirectoryURL = AppDelegate.initialWorkingDirectoryURL()
    private var inputTextWasChanged = false
    private var isLoadingInputText = false

    private let terminalFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let defaultInputWindowFrame = NSRect(x: 120, y: 460, width: 800, height: 360)
    private let defaultOutputWindowFrame = NSRect(x: 120, y: 80, width: 800, height: 360)
    private let defaultInputText = """
    # Bash commands go here.
    # Press Command+E to execute the command section at the cursor.
    # Use lines starting with ### to separate command sections.

    pwd
    ls -la
    """
    private lazy var linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private struct WorksheetState {
        let inputWindowFrame: NSRect
        let outputWindowFrame: NSRect
        let inputText: String
        let restoresWindowFrames: Bool
    }

    private enum WorksheetError: LocalizedError {
        case invalidHeader(String)

        var errorDescription: String? {
            switch self {
            case .invalidHeader(let detail):
                return "Invalid worksheet header: \(detail)"
            }
        }
    }

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
        guard saveInputWorksheetIfNeeded(for: workingDirectoryURL) else {
            return
        }

        workingDirectoryURL = url
        let worksheet = loadWorksheet(for: workingDirectoryURL)
        setInputText(worksheet.inputText)
        if worksheet.restoresWindowFrames {
            restoreWindowFrames(from: worksheet)
        }
        appendOutput("\n[Working directory: \(url.path)]\n")
    }

    private func worksheetURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.worksheetFileName, isDirectory: false)
    }

    private var defaultWorksheetState: WorksheetState {
        WorksheetState(
            inputWindowFrame: defaultInputWindowFrame,
            outputWindowFrame: defaultOutputWindowFrame,
            inputText: defaultInputText,
            restoresWindowFrames: false
        )
    }

    private func loadWorksheet(for directoryURL: URL) -> WorksheetState {
        let worksheetURL = worksheetURL(for: directoryURL)

        guard FileManager.default.fileExists(atPath: worksheetURL.path) else {
            return defaultWorksheetState
        }

        do {
            let worksheetText = try String(contentsOf: worksheetURL, encoding: .utf8)
            return try parseWorksheet(worksheetText)
        } catch {
            reportWorksheetError("Could not load \(worksheetURL.path)", error: error)
            return defaultWorksheetState
        }
    }

    private func setInputText(_ inputText: String) {
        isLoadingInputText = true
        setTerminalString(inputText, in: inputTextView)
        inputTextView.undoManager?.removeAllActions()
        inputTextWasChanged = false
        isLoadingInputText = false

        let inputEnd = (inputTextView.string as NSString).length
        inputTextView.setSelectedRange(NSRange(location: inputEnd, length: 0))
    }

    private func restoreWindowFrames(from worksheet: WorksheetState) {
        inputWindow.setFrame(worksheet.inputWindowFrame, display: true)
        outputWindow.setFrame(worksheet.outputWindowFrame, display: true)
    }

    @discardableResult
    private func saveInputWorksheetIfNeeded(for directoryURL: URL, reportErrors: Bool = true) -> Bool {
        guard inputTextWasChanged else {
            return true
        }

        let worksheetURL = worksheetURL(for: directoryURL)

        do {
            try serializedWorksheet().write(to: worksheetURL, atomically: true, encoding: .utf8)
            inputTextWasChanged = false
            return true
        } catch {
            if reportErrors {
                reportWorksheetError("Could not save \(worksheetURL.path)", error: error)
            } else {
                NSLog("Could not save %@: %@", worksheetURL.path, String(describing: error))
            }

            return false
        }
    }

    private func serializedWorksheet() -> String {
        [
            Self.worksheetVersionLine,
            Self.worksheetFrameFormatLine,
            "\(Self.inputWindowFrameLinePrefix)\(serializedFrame(inputWindow.frame))",
            "\(Self.outputWindowFrameLinePrefix)\(serializedFrame(outputWindow.frame))",
            "",
            inputTextView.string
        ].joined(separator: "\n")
    }

    private func serializedFrame(_ frame: NSRect) -> String {
        "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
    }

    private func parseWorksheet(_ worksheetText: String) throws -> WorksheetState {
        guard let separatorRange = worksheetText.range(of: "\n\n") else {
            throw WorksheetError.invalidHeader("missing blank line after header")
        }

        let headerText = String(worksheetText[..<separatorRange.lowerBound])
        let inputText = String(worksheetText[separatorRange.upperBound...])
        let headerLines = headerText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard headerLines.count == 4 else {
            throw WorksheetError.invalidHeader("expected 4 header lines")
        }

        guard headerLines[0] == Self.worksheetVersionLine else {
            throw WorksheetError.invalidHeader("expected \(Self.worksheetVersionLine)")
        }

        guard headerLines[1] == Self.worksheetFrameFormatLine else {
            throw WorksheetError.invalidHeader("expected \(Self.worksheetFrameFormatLine)")
        }

        return WorksheetState(
            inputWindowFrame: try parseFrameLine(
                headerLines[2],
                prefix: Self.inputWindowFrameLinePrefix
            ),
            outputWindowFrame: try parseFrameLine(
                headerLines[3],
                prefix: Self.outputWindowFrameLinePrefix
            ),
            inputText: inputText,
            restoresWindowFrames: true
        )
    }

    private func parseFrameLine(_ line: String, prefix: String) throws -> NSRect {
        guard line.hasPrefix(prefix) else {
            throw WorksheetError.invalidHeader("expected \(prefix)")
        }

        let valueText = String(line.dropFirst(prefix.count))
        let values = valueText
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        guard values.count == 4,
              let x = Double(values[0]),
              let y = Double(values[1]),
              let width = Double(values[2]),
              let height = Double(values[3]),
              width > 0,
              height > 0 else {
            throw WorksheetError.invalidHeader("invalid frame values for \(prefix)")
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func reportWorksheetError(_ message: String, error: Error) {
        let output = "\n[\(message): \(error)]\n"

        if outputWindow != nil {
            appendOutput(output)
        } else {
            NSLog("%@", output)
        }
    }

    private func configureTerminalTextView(_ textView: NSTextView, editable: Bool) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false

        textView.font = terminalFont
        textView.defaultParagraphStyle = terminalParagraphStyle
        textView.typingAttributes = terminalAttributes
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

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

        DispatchQueue.main.async { [weak self] in
            self?.bringWindowsToFrontAndFocusInput()
        }
    }


    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveInputWorksheetIfNeeded(for: workingDirectoryURL, reportErrors: false)

        for process in activeProcesses where process.isRunning {
            process.terminate()
        }
    }

    private func setUpWindows() {
        let worksheet = loadWorksheet(for: workingDirectoryURL)

        inputTextView.delegate = self
        setInputText(worksheet.inputText)

        inputTextView.executeHandler = { [weak self] script in
            self?.executeInBash(script)
        }

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.delegate = self

        inputWindow = makeWindow(
            title: "Input - Command+E executes Bash",
            frame: worksheet.inputWindowFrame,
            contentView: makeScrollView(textView: inputTextView, editable: true)
        )

        outputWindow = makeWindow(
            title: "Output",
            frame: worksheet.outputWindowFrame,
            contentView: makeScrollView(textView: outputTextView, editable: false)
        )

        bringWindowsToFrontAndFocusInput()
    }

    private func bringWindowsToFrontAndFocusInput() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        outputWindow.orderFrontRegardless()
        inputWindow.orderFrontRegardless()
        inputWindow.makeKeyAndOrderFront(nil)

        let inputEnd = (inputTextView.string as NSString).length
        inputTextView.setSelectedRange(NSRange(location: inputEnd, length: 0))
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
        let command = script.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else {
            appendOutput("\n[Nothing to execute]\n")
            return
        }

        appendOutput(commandOutputHeader(for: command))

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-s"]
        process.currentDirectoryURL = workingDirectoryURL

        var environment = ProcessInfo.processInfo.environment
        environment["PWD"] = workingDirectoryURL.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:~/bin:~/homebrew/bin"

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
            stdin.fileHandleForWriting.write(Data(command.utf8))
            stdin.fileHandleForWriting.closeFile()
        } catch {
            appendOutput("\nCould not start /bin/bash:\n\(error)\n")
            activeProcesses.removeAll { $0 === process }
        }
    }

    private func commandOutputHeader(for command: String) -> String {
        if command.contains("\n") {
            return "\n--- Command begin ---\n\(command)\n--- Command end ---\n"
        }

        return "\n--- Cmd: \(command) ---\n"
    }

    private func appendOutput(_ text: String) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: terminalAttributes
        )

        outputTextView.textStorage?.append(attributedText)
        refreshOutputLinks()
        outputTextView.scrollToEndOfDocument(nil)
    }

    private func refreshOutputLinks() {
        guard let linkDetector, let textStorage = outputTextView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else {
            return
        }

        textStorage.removeAttribute(.link, range: fullRange)

        let output = textStorage.string
        linkDetector.enumerateMatches(in: output, options: [], range: fullRange) { result, _, _ in
            guard let result, let url = result.url else {
                return
            }

            textStorage.addAttribute(.link, value: url, range: result.range)
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard textView === outputTextView else {
            return false
        }

        if let url = link as? URL {
            NSWorkspace.shared.open(url)
            return true
        }

        if let linkText = link as? String, let url = URL(string: linkText) {
            NSWorkspace.shared.open(url)
            return true
        }

        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView === inputTextView,
              !isLoadingInputText else {
            return
        }

        inputTextWasChanged = true
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

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
