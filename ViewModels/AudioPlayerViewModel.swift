import Foundation
import AVFoundation
import MediaPlayer
import Combine

class AudioPlayerViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentTrackIndex: Int = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var isLoaded: Bool = false
    @Published var currentBookId: UUID?
    @Published var sleepTimerRemaining: TimeInterval?
    @Published var chapters: [AudioChapterMapping] = []
    @Published var currentChapterTitle: String = ""
    @Published var error: String?
    @Published var currentBook: Book?

    var sleepTimerActive: Bool { sleepTimerRemaining != nil }

    private var audioPlayer: AVAudioPlayer?
    private var audioFiles: [String] = []
    private var timer: Timer?
    private var sleepTimer: Timer?

    // MARK: - Setup

    func loadAudio(for book: Book) {
        guard let audioInfo = book.audiobook else {
            error = "No audiobook linked to this book"
            return
        }

        currentBook = book
        audioFiles = audioInfo.audioFilePaths
        currentBookId = book.id
        currentTrackIndex = audioInfo.currentTrack
        playbackSpeed = audioInfo.playbackSpeed
        chapters = audioInfo.chapterMapping ?? []

        if !audioFiles.isEmpty {
            loadTrack(at: currentTrackIndex)

            // Resume from saved position
            if audioInfo.currentTime > 0 {
                seek(to: audioInfo.currentTime)
            }
        }

        setupAudioSession()
        setupRemoteTransportControls()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            self.error = "Failed to set up audio session: \(error.localizedDescription)"
        }
    }

    private func loadTrack(at index: Int) {
        guard index >= 0 && index < audioFiles.count else {
            error = "Track index out of range"
            return
        }

        let filePath = audioFiles[index]
        let url = URL(fileURLWithPath: filePath)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.enableRate = true
            audioPlayer?.rate = Float(playbackSpeed)
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTrackIndex = index
            isLoaded = true
            updateNowPlayingInfo()
            updateCurrentChapter()
        } catch {
            self.error = "Failed to load audio: \(error.localizedDescription)"
            isLoaded = false
        }
    }

    // MARK: - Playback Controls

    func play() {
        audioPlayer?.rate = Float(playbackSpeed)
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = max(0, min(time, duration))
        currentTime = audioPlayer?.currentTime ?? 0
        updateNowPlayingInfo()
        updateCurrentChapter()
    }

    func skipForward(seconds: Int = 30) {
        let newTime = currentTime + Double(seconds)
        if newTime >= duration {
            nextTrack()
        } else {
            seek(to: newTime)
        }
    }

    func skipBackward(seconds: Int = 15) {
        let newTime = currentTime - Double(seconds)
        seek(to: max(0, newTime))
    }

    func nextTrack() {
        if currentTrackIndex < audioFiles.count - 1 {
            let wasPlaying = isPlaying
            loadTrack(at: currentTrackIndex + 1)
            if wasPlaying { play() }
        }
    }

    func previousTrack() {
        if currentTime > 3 {
            // If more than 3 seconds in, restart current track
            seek(to: 0)
        } else if currentTrackIndex > 0 {
            let wasPlaying = isPlaying
            loadTrack(at: currentTrackIndex - 1)
            if wasPlaying { play() }
        }
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        audioPlayer?.rate = Float(speed)
    }

    func jumpToChapter(_ chapter: AudioChapterMapping) {
        seek(to: chapter.startTime)
    }

    func nextChapter() {
        nextTrack()
    }

    func previousChapter() {
        previousTrack()
    }

    func setSleepTimer(minutes: TimeInterval) {
        startSleepTimer(minutes: max(1, Int(minutes)))
    }

    // MARK: - Sleep Timer

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTimerRemaining = Double(minutes * 60)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let remaining = self.sleepTimerRemaining {
                if remaining <= 0 {
                    self.pause()
                    self.cancelSleepTimer()
                } else {
                    self.sleepTimerRemaining = remaining - 1
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0

            // Check if track ended
            if self.currentTime >= self.duration - 0.5 {
                self.nextTrack()
            }

            self.updateCurrentChapter()
        }
    }

    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Now Playing / Lock Screen Controls

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentChapterTitle.isEmpty ? "Audiobook" : currentChapterTitle
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateCurrentChapter() {
        if let chapter = chapters.last(where: { currentTime >= $0.startTime }) {
            currentChapterTitle = chapter.chapterTitle
        }
    }

    // MARK: - Save State

    func getCurrentAudioState() -> AudiobookInfo {
        AudiobookInfo(
            audioFilePaths: audioFiles,
            totalDuration: duration,
            currentTime: currentTime,
            currentTrack: currentTrackIndex,
            playbackSpeed: playbackSpeed,
            chapterMapping: chapters.isEmpty ? nil : chapters
        )
    }

    // MARK: - Formatting

    static func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Cleanup

    func cleanup() {
        pause()
        stopProgressTimer()
        cancelSleepTimer()
        audioPlayer = nil
        isLoaded = false
    }

    deinit {
        cleanup()
    }
}
