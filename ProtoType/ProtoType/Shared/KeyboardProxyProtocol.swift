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
    var returnKeyType: UIReturnKeyType { get }
}
