import Foundation

struct ProcessingRecording: Identifiable {
    let id: UUID
    let filename: String
    let stoppedAt: Date
    var startedAt: Date?
    var progress: Double = 0

    func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(startedAt ?? stoppedAt)))
        return Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }
}
