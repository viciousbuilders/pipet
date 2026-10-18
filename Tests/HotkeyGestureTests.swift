import AppKit
import Carbon
import Foundation

@main
struct HotkeyGestureTests {
    static func main() {
        let right = NSEvent.ModifierFlags.command.union(NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK)))
        let left = NSEvent.ModifierFlags.command.union(NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK)))
        let rightCode = UInt16(kVK_RightCommand)
        let leftCode = UInt16(kVK_Command)
        var gesture = DictationHotkeyGesture()

        func require(_ condition: Bool, _ message: String) {
            if !condition { fatalError(message) }
        }

        require(gesture.flagsChanged(keyCode: leftCode, flags: left) == nil, "Left Command must not arm dictation")
        require(!gesture.activate(), "Left Command must not start dictation")
        _ = gesture.flagsChanged(keyCode: leftCode, flags: [])
        require(gesture.flagsChanged(keyCode: rightCode, flags: right) == .arm, "Right Command arms dictation")
        require(gesture.activate(), "A standalone hold starts dictation")
        require(!gesture.activate(), "A held modifier starts only once")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == .release, "Right Command release finishes dictation")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Duplicate release is ignored")
        print("PASS: left/right distinction, standalone hold, one release")

        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Quick taps do not submit")
        require(!gesture.activate(), "Released taps cannot start later")
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.keyDown() == nil, "Command chords before activation do not record")
        require(!gesture.activate(), "Command-C/V and Escape disarm the pending hold")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Command chord release does not submit")
        print("PASS: quick taps and ordinary Command chords")

        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.activate(), "New standalone hold starts normally")
        require(gesture.keyDown() == .cancel, "Escape or another key cancels active recording")
        require(gesture.keyDown() == nil, "Key repeats do not cancel twice")
        require(!gesture.activate(), "Cancelled recording cannot restart while still held")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Cancelled recording never submits on release")
        print("PASS: Escape cancellation and latch until release")

        for modifier in [NSEvent.ModifierFlags.shift, .control, .option, .function, left] {
            _ = gesture.flagsChanged(keyCode: rightCode, flags: right.union(modifier))
            require(!gesture.activate(), "Modified Right Command must not start recording")
            _ = gesture.flagsChanged(keyCode: rightCode, flags: [])
            _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
            require(gesture.activate(), "Fresh standalone hold must recover")
            require(gesture.flagsChanged(keyCode: leftCode, flags: right.union(modifier)) == .cancel, "Additional modifier cancels active recording")
            _ = gesture.flagsChanged(keyCode: leftCode, flags: right)
            require(!gesture.activate(), "Releasing another modifier cannot rearm while Right Command is held")
            _ = gesture.flagsChanged(keyCode: rightCode, flags: [])
        }
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.activate(), "Hold before left Command test")
        require(gesture.flagsChanged(keyCode: leftCode, flags: right.union(left)) == .cancel, "Left Command interrupts a right hold")
        require(gesture.flagsChanged(keyCode: rightCode, flags: left) == nil, "Releasing right while left remains held must not submit")
        _ = gesture.flagsChanged(keyCode: leftCode, flags: [])
        print("PASS: modifier chords, both Command keys and release order")

        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.reset() == nil, "Sleep cancels a pending hold without submitting")
        require(!gesture.activate(), "Pending hold cannot start after reset")
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.activate(), "Fresh hold after wake")
        require(gesture.reset() == .cancel, "Sleep, session lock or stop cancels recording")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Reset recording cannot submit later")
        print("PASS: sleep/session reset and recovery")
    }
}
