import Cocoa

/// Full-window error screen shown when required backend files are missing.
/// Replaces the loading view so the user gets a clear, in-app explanation
/// instead of a silent hang.
class MissingFilesViewController: NSObject {

    private let containerView: NSView
    private let projectRoot: String

    init(parentView: NSView, missing: [MissingRequiredFile], projectRoot: String) {
        self.projectRoot = projectRoot

        containerView = NSView(frame: parentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0).cgColor

        super.init()

        parentView.addSubview(containerView, positioned: .above, relativeTo: nil)
        buildContent(missing: missing)
    }

    private func buildContent(missing: [MissingRequiredFile]) {
        // Brand
        let brand = label("SPOTIFY DASHBOARD",
                          font: NSFont(name: "Menlo-Bold", size: 16) ?? NSFont.boldSystemFont(ofSize: 16),
                          color: NSColor(red: 0.52, green: 1.0, blue: 0.0, alpha: 1.0))
        brand.alignment = .center

        // Heading
        let heading = label("Files Missing from Folder root",
                            font: NSFont.systemFont(ofSize: 32, weight: .bold),
                            color: .white)
        heading.alignment = .center

        // Intro
        let isOne = missing.count == 1
        let intro = wrappingLabel(
            "Spotify Dashboard can't start because the following file\(isOne ? " is" : "s are") missing. " +
            "Add \(isOne ? "it" : "them") to the project folder and relaunch the app.",
            font: NSFont.systemFont(ofSize: 15),
            color: NSColor(white: 0.8, alpha: 1.0)
        )
        intro.alignment = .center

        // Missing files list — one prominent row per file
        let filesStack = NSStackView()
        filesStack.orientation = .vertical
        filesStack.alignment = .centerX
        filesStack.spacing = 14
        filesStack.translatesAutoresizingMaskIntoConstraints = false
        for entry in missing {
            filesStack.addArrangedSubview(makeFileRow(entry))
        }

        // "Looking in" footer
        let lookingLabel = label("Place Files in",
                                 font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                 color: NSColor(white: 0.5, alpha: 1.0))
        lookingLabel.alignment = .center

        let pathValue = wrappingLabel(projectRoot,
                                      font: NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                      color: NSColor(white: 0.7, alpha: 1.0))
        pathValue.alignment = .center
        pathValue.isSelectable = true

        // Buttons
        let revealButton = NSButton(title: "Reveal Folder in Finder", target: self, action: #selector(revealInFinder))
        revealButton.bezelStyle = .rounded

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [revealButton, quitButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        // Outer vertical stack — centered in the window
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .centerX
        outer.spacing = 16
        outer.translatesAutoresizingMaskIntoConstraints = false

        outer.addArrangedSubview(brand)
        outer.setCustomSpacing(12, after: brand)
        outer.addArrangedSubview(heading)
        outer.setCustomSpacing(10, after: heading)
        outer.addArrangedSubview(intro)
        outer.setCustomSpacing(28, after: intro)
        outer.addArrangedSubview(filesStack)
        outer.setCustomSpacing(28, after: filesStack)
        outer.addArrangedSubview(lookingLabel)
        outer.setCustomSpacing(4, after: lookingLabel)
        outer.addArrangedSubview(pathValue)
        outer.setCustomSpacing(28, after: pathValue)
        outer.addArrangedSubview(buttonRow)

        containerView.addSubview(outer)

        let contentWidth: CGFloat = 560

        NSLayoutConstraint.activate([
            outer.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            outer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            outer.widthAnchor.constraint(equalToConstant: contentWidth),

            filesStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
            intro.widthAnchor.constraint(equalTo: outer.widthAnchor),
            pathValue.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
    }

    /// One full-width card listing the file name and how to create it.
    private func makeFileRow(_ entry: MissingRequiredFile) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1.0).cgColor
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(red: 0.52, green: 1.0, blue: 0.0, alpha: 0.25).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let nameField = label(entry.name,
                              font: NSFont(name: "Menlo-Bold", size: 16) ?? NSFont.boldSystemFont(ofSize: 16),
                              color: NSColor(red: 0.52, green: 1.0, blue: 0.0, alpha: 1.0))
        nameField.isSelectable = true
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let purposeField = wrappingLabel(entry.purpose,
                                         font: NSFont.systemFont(ofSize: 13),
                                         color: NSColor(white: 0.85, alpha: 1.0))
        purposeField.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(nameField)
        card.addSubview(purposeField)

        var bottomAnchorView: NSView = purposeField

        if let example = entry.exampleName {
            let hint = wrappingLabel("Copy \(example) → \(entry.name) and fill in the values.",
                                     font: NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                     color: NSColor(white: 0.6, alpha: 1.0))
            hint.isSelectable = true
            hint.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(hint)

            NSLayoutConstraint.activate([
                hint.topAnchor.constraint(equalTo: purposeField.bottomAnchor, constant: 6),
                hint.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
                hint.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            ])
            bottomAnchorView = hint
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 560),

            nameField.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            nameField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            purposeField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 4),
            purposeField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            purposeField.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            bottomAnchorView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        return card
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = font
        f.textColor = color
        f.isBezeled = false
        f.isEditable = false
        f.drawsBackground = false
        return f
    }

    private func wrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = font
        f.textColor = color
        f.isBezeled = false
        f.isEditable = false
        f.drawsBackground = false
        return f
    }

    @objc private func revealInFinder() {
        let url = URL(fileURLWithPath: projectRoot)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
