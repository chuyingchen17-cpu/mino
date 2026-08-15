import Foundation
import MinoRuntime

@MainActor
final class DemoSequenceController {
    private var task: Task<Void, Never>?

    func play(in world: PetWorld) {
        stop()
        task = Task { @MainActor [weak world] in
            guard let world else { return }

            world.resetForDemo()
            guard await pause(for: .milliseconds(750)) else { return }

            world.triggerKiss()
            guard await pause(for: .milliseconds(2_750)) else { return }

            world.walkApartForDemo()
            guard await pause(for: .milliseconds(1_900)) else { return }

            world.triggerFlowerGift()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func pause(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
