import Foundation

protocol KeyboardProxy: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func advanceToNextInputMode()
    func dismissKeyboard()
    var needsInputModeSwitchKey: Bool { get }
    var documentContextBeforeInput: String? { get }
}
