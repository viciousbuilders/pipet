import Foundation

@MainActor
private final class FakeMedia: MediaPlaybackBackend {
    var current: MediaPlaybackState? = .init(pid: 123, playing: true)
    var commands: [Bool] = []
    var accepts = true
    var delay = false
    func state() async -> MediaPlaybackState? {
        if delay { try? await Task.sleep(for: .milliseconds(30)) }
        return current
    }
    func send(play: Bool) -> Bool {
        commands.append(play)
        if accepts, let current { self.current = .init(pid: current.pid, playing: play) }
        return accepts
    }
}

@main
struct MediaPlaybackTests {
    @MainActor static func main() async {
        let backend = FakeMedia()
        let controller = RecordingMediaController(backend: backend)
        await controller.pause()
        precondition(backend.commands == [false])
        controller.resume()
        controller.resume()
        await controller.waitForRestoration()
        precondition(backend.commands == [false, true], "Resume exactly once")
        backend.commands = []
        backend.current = .init(pid: 123, playing: false)
        await controller.pause()
        controller.resume()
        await controller.waitForRestoration()
        precondition(backend.commands.isEmpty, "Leave already paused media alone")
        backend.current = .init(pid: 123, playing: true)
        await controller.pause()
        backend.current = .init(pid: 456, playing: false)
        controller.resume()
        await controller.waitForRestoration()
        precondition(backend.commands == [false], "Never start a different player")
        backend.commands = []
        backend.current = nil
        await controller.pause()
        controller.resume()
        precondition(backend.commands.isEmpty, "Unavailable state must be a no-op")
        backend.current = .init(pid: 0, playing: true)
        await controller.pause()
        precondition(backend.commands.isEmpty, "Unknown player must be a no-op")
        backend.current = .init(pid: 123, playing: true)
        backend.accepts = false
        await controller.pause()
        controller.resume()
        await controller.waitForRestoration()
        precondition(backend.commands == [false], "Failed pause must not trigger play")
        backend.commands = []
        backend.accepts = true
        backend.delay = true
        let pending = Task { await controller.pause() }
        try? await Task.sleep(for: .milliseconds(5))
        controller.resume()
        await pending.value
        precondition(backend.commands.isEmpty, "Cancellation must invalidate pending pause")
        backend.delay = false
        await controller.pause()
        controller.resume()
        await controller.pause()
        precondition(backend.commands == [false, true, false], "New recording waits for previous restoration")
        controller.resume()
        await controller.waitForRestoration()
        precondition(backend.commands == [false, true, false, true])
        let system = SystemMediaPlaybackBackend()
        _ = await system.state() // Read-only smoke check: never controls real playback.
        print("Media playback regression checks passed")
    }
}
