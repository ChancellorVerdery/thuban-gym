import SwiftUI
import UIKit

/// A number typed on the NATIVE iOS keypad (`.decimalPad` for weights, `.numberPad` for reps) with a keyboard
/// toolbar above it. UIKit-backed because SwiftUI's keyboard toolbar is unreliable in a full-screen cover (it can
/// miss the first focus and is left out of keyboard avoidance, covering the Log button); a real
/// `inputAccessoryView` is part of the keyboard frame, so the page's bottom bar always sits above it.
struct NumberField: UIViewRepresentable {
    struct Action {
        var title: String
        var bold = false
        var action: () -> Void
    }

    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType
    var font: UIFont
    var color: UIColor
    var placeholderColor: UIColor
    var tint: UIColor
    var alignment: NSTextAlignment
    var isFocused: Bool
    var accessibilityLabel: String
    var onFocus: (Bool) -> Void
    /// Toolbar buttons: leading ones, then a flexible space, then the trailing one (Done).
    var leading: [Action]
    var trailing: Action

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.adjustsFontForContentSizeCategory = false
        field.inputAccessoryView = context.coordinator.toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.keyboardType = keyboard
        field.font = font
        field.textColor = color
        field.tintColor = tint
        field.textAlignment = alignment
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font])
        field.accessibilityLabel = accessibilityLabel
        context.coordinator.updateToolbar()
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let sample = (uiView.text?.isEmpty ?? true) ? placeholder : (uiView.text ?? "")
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: ceil(width) + 6, height: ceil(font.lineHeight))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumberField
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))

        init(_ parent: NumberField) {
            self.parent = parent
            super.init()
            toolbar.sizeToFit()
            updateToolbar()
        }

        func updateToolbar() {
            var items: [UIBarButtonItem] = parent.leading.enumerated().map { index, action in
                let item = UIBarButtonItem(title: action.title, style: .plain, target: self, action: #selector(tapLeading(_:)))
                item.tag = index
                return item
            }
            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            items.append(UIBarButtonItem(title: parent.trailing.title, style: parent.trailing.bold ? .done : .plain, target: self, action: #selector(tapTrailing)))
            if toolbar.items?.map(\.title) != items.map(\.title) { toolbar.setItems(items, animated: false) }
            toolbar.tintColor = parent.tint
        }

        @objc func tapLeading(_ item: UIBarButtonItem) {
            guard item.tag < parent.leading.count else { return }
            parent.leading[item.tag].action()
        }

        @objc func tapTrailing() { parent.trailing.action() }

        @objc func changed(_ field: UITextField) {
            let filtered = Self.filter(field.text ?? "", decimal: parent.keyboard == .decimalPad)
            if filtered != field.text { field.text = filtered }
            parent.text = filtered
            field.invalidateIntrinsicContentSize()
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            DispatchQueue.main.async {
                field.selectAll(nil)
                self.parent.onFocus(true)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            DispatchQueue.main.async { self.parent.onFocus(false) }
        }

        /// Digits and at most one decimal separator (either "." or the locale's ","), four digits before it.
        static func filter(_ text: String, decimal: Bool) -> String {
            var result = ""
            var seenSeparator = false
            var whole = 0
            for character in text {
                if character.isASCII, character.isNumber {
                    if !seenSeparator {
                        guard whole < 4 else { continue }
                        whole += 1
                    }
                    result.append(character)
                } else if decimal, !seenSeparator, character == "." || character == "," {
                    seenSeparator = true
                    result.append(".")
                }
            }
            return result
        }
    }
}
