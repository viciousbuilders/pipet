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

        require(gesture.flagsChanged(keyCode: leftCode, flags: left) == nil, "Left Command must not trigger")
        require(gesture.flagsChanged(keyCode: leftCode, flags: []) == nil, "Left Command release must not trigger")
        for _ in 0..<3 {
            require(gesture.flagsChanged(keyCode: rightCode, flags: right) == nil, "Wait for release to distinguish chords")
            require(gesture.flagsChanged(keyCode: rightCode, flags: right) == nil, "Repeated down must not toggle")
            require(gesture.flagsChanged(keyCode: rightCode, flags: []) == .toggle, "Each standalone tap toggles once, with no hold threshold")
            require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Duplicate release is ignored")
        }
        print("PASS: left/right distinction, repeated taps, duplicate events")

        for key in [kVK_ANSI_C, kVK_ANSI_V, kVK_Tab] {
            _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
            require(gesture.keyDown(keyCode: UInt16(key)) == nil, "Ordinary chords do not cancel recording")
            require(gesture.flagsChanged(keyCode: rightCode, flags: right) == nil, "Chord cannot rearm while held")
            require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Chord release must not toggle")
        }
        require(gesture.keyDown(keyCode: UInt16(kVK_ANSI_A)) == nil, "Typing must not stop recording")
        require(gesture.keyDown(keyCode: UInt16(kVK_Escape)) == .cancel, "Esc cancels without Command held")
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.keyDown(keyCode: UInt16(kVK_Escape)) == .cancel, "Esc also cancels while Command held")
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Esc invalidates pending tap")
        print("PASS: Command chords, typing, Escape cancellation")

        for modifier in [NSEvent.ModifierFlags.shift, .control, .option, .function, left] {
            _ = gesture.flagsChanged(keyCode: rightCode, flags: right.union(modifier))
            require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Modified press does not toggle")
            _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
            _ = gesture.flagsChanged(keyCode: leftCode, flags: right.union(modifier))
            _ = gesture.flagsChanged(keyCode: leftCode, flags: right)
            require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Releasing modifier cannot rearm tap")
        }
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        _ = gesture.flagsChanged(keyCode: leftCode, flags: right.union(left))
        require(gesture.flagsChanged(keyCode: rightCode, flags: left) == nil, "Right release while left held must not toggle")
        _ = gesture.flagsChanged(keyCode: leftCode, flags: [])
        print("PASS: modifier chords and both Command release orders")

        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        gesture.reset()
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == nil, "Reset discards pending tap")
        _ = gesture.flagsChanged(keyCode: rightCode, flags: right)
        require(gesture.flagsChanged(keyCode: rightCode, flags: []) == .toggle, "Fresh tap works after reset")
        print("PASS: sleep/session/app switch reset and recovery")
    }
}
