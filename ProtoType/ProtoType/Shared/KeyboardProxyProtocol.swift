import Foundation
import UIKit

protocol KeyboardProxy: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func advanceToNextInputMode()
    func dismissKeyboard()
    func playInputClick()
    func textReplacement(for input: String) -> String?
    var needsInputModeSwitchKey: Bool { get }
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    var returnKeyType: UIReturnKeyType { get }
    var keyboardType: UIKeyboardType { get }
    var autocapitalizationType: UITextAutocapitalizationType { get }
    var autocorrectionType: UITextAutocorrectionType { get }
    var spellCheckingType: UITextSpellCheckingType { get }
    var isSecureTextEntry: Bool { get }
    var textContentType: UITextContentType? { get }
}
