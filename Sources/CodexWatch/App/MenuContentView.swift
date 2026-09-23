import AppKit

/// Shared margins and content-driven sizing for the custom portions of the menu.
class MenuContentView: NSView {
    static let width: CGFloat = 300
    static let horizontalInset: CGFloat = 14
    static let verticalInset: CGFloat = 10

    let stack = NSStackView()
    private var contentHeight: NSLayoutConstraint!

    init(spacing: CGFloat, alignment: NSLayoutConstraint.Attribute) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        contentHeight = heightAnchor.constraint(equalToConstant: frame.height)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            contentHeight,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resizeToFitContent() {
        let height = ceil(stack.fittingSize.height) + 2 * Self.verticalInset
        contentHeight.constant = height
        setFrameSize(NSSize(width: Self.width, height: height))
        layoutSubtreeIfNeeded()
    }
}
