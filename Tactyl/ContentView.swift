import SwiftUI
import AVKit
import CoreHaptics
import CodeScanner // You'll need to add this package: https://github.com/twostraws/CodeScanner

// MARK: - Models
struct HapticPattern: Codable {
    let Version: Double
    let Pattern: [PatternElement]
}

struct PatternElement: Codable {
    let Event: HapticEvent
}

struct HapticEvent: Codable {
    let Time: Double
    let EventType: String
    let EventDuration: Double?
    let EventParameters: [EventParameter]
}

struct EventParameter: Codable {
    let ParameterID: String
    let ParameterValue: Double
}

// Server response structure
struct HapticSessionData: Codable {
    let ahap: HapticPattern
    let mediaUrl: String
    let created: String?
    let expires: String?
}

// Legacy QR format (for backward compatibility)
struct QRPayload: Codable {
    let ahap: HapticPattern
    let mediaUrl: String
}

// MARK: - Haptic Engine Manager
class HapticManager: ObservableObject {
    private var engine: CHHapticEngine?
    private var isEngineRunning = false
    private var hapticBoundaryObservers: Any?
    
    init() {
        prepareHaptics()
    }
    
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Device does not support haptics")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            engine?.playsHapticsOnly=false
            // Set up engine callbacks
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason)")
                self?.isEngineRunning = false
            }
            
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                self?.isEngineRunning = false
                do {
                    try self?.engine?.start()
                    self?.isEngineRunning = true
                } catch {
                    print("Failed to restart engine: \(error)")
                }
            }
            
            try engine?.start()
            isEngineRunning = true
            print("Haptic engine started successfully")
        } catch {
            print("Haptic engine error: \(error)")
        }
    }
    
    func playHapticEvent(_ event: HapticEvent) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Device does not support haptics")
            return
        }
        
        // Ensure engine is running
        if !isEngineRunning {
            do {
                try engine?.start()
                isEngineRunning = true
            } catch {
                print("Failed to start engine: \(error)")
                return
            }
        }
        
        var intensity: Float = 1.0
        var sharpness: Float = 0.5
        
        for param in event.EventParameters {
            switch param.ParameterID {
            case "HapticIntensity":
                intensity = Float(param.ParameterValue)
            case "HapticSharpness":
                sharpness = Float(param.ParameterValue)
            default:
                break
            }
        }
        
        print("Playing haptic: \(event.EventType) at intensity: \(intensity)")
        
        do {
            if event.EventType == "HapticTransient" {
                // Use CHHapticEngine for transient
                let hapticEvent = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                    ],
                    relativeTime: 0
                )
                
                let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate)
                
            } else if event.EventType == "HapticContinuous" {
                // Use CHHapticEngine for continuous
                let hapticEvent = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                    ],
                    relativeTime: 0,
                    duration: event.EventDuration ?? 0.5
                )
                
                let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate)
            }
        } catch {
            print("Failed to play haptic: \(error)")
            // Fallback to UIKit haptics
            if event.EventType == "HapticTransient" {
                let impact = UIImpactFeedbackGenerator(style: intensity > 0.66 ? .heavy : intensity > 0.33 ? .medium : .light)
                impact.prepare()
                impact.impactOccurred()
            } else {
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                notification.notificationOccurred(.warning)
            }
        }
    }
    
    deinit {
        engine?.stop()
    }
}


// MARK: - Video Player View Model
class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    
    @Published var isReadyToPlay = false
    {
            didSet { checkAndAutoPlay() }   // 👈 check whenever video becomes ready
        }
    
     @Published var isLandscape=true
    @Published var duration: Double = 0
    private var playerItemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var hapticManager = HapticManager()
    private var hapticPattern: HapticPattern? {
        didSet { checkAndAutoPlay() }   // 👈 check whenever haptics are set
    }
    private var scheduledHaptics: [Timer] = []
    private var hapticWorkItems: [DispatchWorkItem] = []
    private var hapticBoundaryObservers: Any?

    // MARK: - Auto play logic
    private func checkAndAutoPlay() {
        guard let player = player else { return }
        if isReadyToPlay, hapticPattern != nil, !isPlaying {
            print("🎬 Auto-playing video + haptics")

            // Ensure the audio session is active for playback
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("⚠️ Failed to activate audio session: \(error)")
            }

            // Make sure we’re at the beginning
            player.seek(to: .zero) { [weak self] _ in
                player.play()
                self?.isPlaying = true
                self?.scheduleHaptics()
            }
        }
    }

    
    func cleanup() {
        // Stop current playback
        player?.pause()
        isPlaying = false
        
        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Cancel haptics
        cancelScheduledHaptics()
        isReadyToPlay = false
        playerItemObservation=nil
        // Reset player
        player = nil
        currentTime = 0
        duration = 0
        hapticPattern = nil
    }
    
    func loadVideo(from url: String) {
            cleanup()
            guard let videoURL = URL(string: url) else { return }
            
            let asset = AVAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            
            // 👀 Observe status changes
            playerItemObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        self?.isReadyToPlay = true
                        print("✅ Video is ready to play")
                    case .failed:
                        self?.isReadyToPlay = false
                        print("❌ Failed to load video: \(String(describing: item.error))")
                    default:
                        self?.isReadyToPlay = false
                    }
                }
            }
        
            
            player = AVPlayer(playerItem: playerItem)
            player?.volume = 1.0
        
        timeObserver = player?.addPeriodicTimeObserver(
               forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
               queue: .main
           ) { [weak self] time in
               self?.currentTime = time.seconds
           }
            // Load duration asynchronously
            Task {
                do {
                    let duration = try await asset.load(.duration)
                    await MainActor.run {
                        self.duration = duration.seconds
                    }
                } catch {
                    print("Failed to load duration: \(error)")
                }
            }
        }

    
    
    func setHapticPattern(_ pattern: HapticPattern) {
        self.hapticPattern = pattern
        print("Set haptic pattern with \(pattern.Pattern.count) events")
    }
    
    func play() {
        player?.play()
        isPlaying = true
        scheduleHaptics()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        cancelScheduledHaptics()
    }
    
    func seek(to time: Double) {
        let seekTime = CMTime(seconds: time, preferredTimescale: 600)
        currentTime = time // Update immediately for UI responsiveness
        
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            if completed {
                // Reschedule haptics after seeking completes
                if self?.isPlaying == true {
                    self?.scheduleHaptics()
                }
            }
        }
    }
    
    private func scheduleHaptics() {
        cancelScheduledHaptics()
        guard let player = player, let pattern = hapticPattern else { return }

        // Build CMTime array for all haptic events
        let times = pattern.Pattern.map { element in
            NSValue(time: CMTime(seconds: element.Event.Time, preferredTimescale: 600))
        }

        // Register boundary observer
        hapticBoundaryObservers = player.addBoundaryTimeObserver(
            forTimes: times,
            queue: .main
        ) { [weak self] in
            guard let self = self else { return }
            let current = player.currentTime().seconds

            // Find closest haptic event to current time
            if let event = pattern.Pattern.min(by: { abs($0.Event.Time - current) < abs($1.Event.Time - current) }) {
                self.hapticManager.playHapticEvent(event.Event)
                print("🎯 Fired haptic at video time \(current), event time \(event.Event.Time)")
            }
        }
    }

    
    private func cancelScheduledHaptics() {
        if let observer = hapticBoundaryObservers {
            player?.removeTimeObserver(observer)
            hapticBoundaryObservers = nil
        }
        hapticWorkItems.forEach { $0.cancel() }
        hapticWorkItems.removeAll()
        scheduledHaptics.forEach { $0.invalidate() }
        scheduledHaptics.removeAll()
    }

    
    deinit {
        cleanup()
    }
}

// MARK: - Main App View
struct ContentView: View {
    @StateObject private var viewModel = VideoPlayerViewModel()
    @State private var showingScanner = true
    @State private var scannedData: QRPayload?
    @State private var errorMessage: String?
    @State private var isLandscape: Bool = false
    @State var tapCount: Int = 0
    @State private var navigateToVibrator = false
    func debugAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        print("🎛 Category: \(session.category.rawValue)")
        print("🎚 Mode: \(session.mode.rawValue)")
        print("🔊 Volume: \(AVAudioSession.sharedInstance().outputVolume)")
        
        let route = session.currentRoute
        for output in route.outputs {
            print("📡 Output: \(output.portType.rawValue) - \(output.portName)")
        }
        
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("✅ Audio session is active")
        } catch {
            print("❌ Failed to activate session: \(error)")
        }
    }

    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 124/255, green: 68/255, blue: 229/255),Color(red: 124/255, green: 68/255, blue: 229/255)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                NavigationLink(
                    destination: VibratorView(),
                    isActive: $navigateToVibrator,
                    label: {
                        EmptyView() // hide the visible link
                    }
                )

                
                if showingScanner {
                    VStack{
                      EmptyView()
                            .onTapGesture {
                                tapCount += 1
                                if tapCount >= 5 {
                                    navigateToVibrator = true
                                    tapCount = 0
                                }
                            }

                  
                    ScannerView(
                        scannedData: $scannedData,
                        errorMessage: $errorMessage,
                        showingScanner: $showingScanner,
                        viewModel: viewModel
                    )
                        NavigationLink(destination: HapticCreatorView()) {
                                              Label("Create Haptics", systemImage: "wand.and.stars")
                                                  .foregroundColor(.white)
                                                  .padding()
                                                  .background(Color.white.opacity(0.2))
                                                  .cornerRadius(15)
                                          }
                                          .padding(.bottom, 30)
                }
                } else if let _ = viewModel.player {
                    PlayerView(viewModel: viewModel, showingScanner: $showingScanner)
                }
            }
            .navigationBarHidden(true)
        }.onAppear{
            debugAudioSession()
        }
    }
}

// MARK: - Scanner View
struct ScannerView: View {
    @Binding var scannedData: QRPayload?
    @Binding var errorMessage: String?
    @Binding var showingScanner: Bool
    let viewModel: VideoPlayerViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            HStack{
                Image("logo").resizable().scaledToFit().frame(width:50,height:50)
            Text("Tactyl")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
            
            Text("Scan QR Code from Editor")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            
            CodeScannerView(
                codeTypes: [.qr],
                simulatedData: "haptic://test",
                completion: handleScan
            )
            .frame(height: 300)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
            )
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(10)
            }
            
            // Demo button for testing
            Button(action: loadDemoContent) {
                Label("Load Demo", systemImage: "play.circle.fill")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(15)
            }
        }
        .padding()
    }
    
    func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            decodeQRData(result.string)
        case .failure(let error):
            errorMessage = "Scanning failed: \(error.localizedDescription)"
        }
    }
    
    func decodeQRData(_ string: String) {
        // Parse the haptic:// URL for session ID
        // Format: haptic://load/sessionId or haptic://load?id=sessionId&h=eventCount
        
        if string.starts(with: "haptic://load/") {
            // Simple format: haptic://load/sessionId
            let sessionId = String(string.dropFirst("haptic://load/".count))
            fetchHapticData(sessionId: sessionId)
        } else if let url = URL(string: string),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Query parameter format: haptic://load?id=sessionId&h=eventCount
            if let sessionId = components.queryItems?.first(where: { $0.name == "id" })?.value {
                fetchHapticData(sessionId: sessionId)
            } else {
                errorMessage = "Invalid QR code format"
            }
        } else {
            errorMessage = "Invalid QR code format"
        }
    }
    
    func fetchHapticData(sessionId: String) {
        // Server is running on your Mac - use your Mac's IP address
        // To find your Mac's IP: System Settings > Network > Wi-Fi > Details
        // Replace with your actual IP (e.g., "http://192.168.1.5:3000")
        let serverURL = "https://tactyl-server.onrender.com/api/haptic/\(sessionId)"
      // let serverURL = "http://192.168.162.199:3000/api/haptic/\(sessionId)"
       //http://tactyl-server.onrender.com
        // If testing on physical iPhone, use your Mac's network IP instead:
        // let serverURL = "http://YOUR_MAC_IP:3000/api/haptic/\(sessionId)"
        // Example: "http://192.168.1.5:3000/api/haptic/\(sessionId)"
        
        guard let url = URL(string: serverURL) else {
            print("Invalid server URL")
            loadDemoContent()
            return
        }
        
        print("Fetching haptic data from: \(serverURL)")
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let hapticData = try JSONDecoder().decode(HapticSessionData.self, from: data)
                
                print("Successfully fetched haptic data with \(hapticData.ahap.Pattern.count) events")
                
                await MainActor.run {
                    // Load video and haptic pattern
                    viewModel.loadVideo(from: hapticData.mediaUrl)
                    viewModel.setHapticPattern(hapticData.ahap)
                    showingScanner = false
                }
            } catch {
                print("Failed to fetch from server: \(error)")
                await MainActor.run {
                    errorMessage = "Server connection failed. Using demo content."
                    // Try demo content as fallback
                    loadDemoContent()
                }
            }
        }
    }
    
    func loadDemoContentWithId(_ sessionId: String) {
        // For demo/testing: use predefined content when server is not available
        print("Loading demo content for session: \(sessionId)")
        loadDemoContent()
    }
    
    func loadDemoContent() {
        // Load AHAP file from bundle
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "ahap") else {
            print("❌ AHAP file not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            
            // Decode JSON into your Swift HapticPattern model
            let decoder = JSONDecoder()
            let loadedPattern = try decoder.decode(HapticPattern.self, from: data)
            
            // Load video (replace with your actual video)
            viewModel.loadVideo(from: "https://shiny-chimera-7266ce.netlify.app/cars.mp4")
            
            // Apply haptic pattern from file
            viewModel.setHapticPattern(loadedPattern)
            
            print("✅ Loaded haptic pattern from demo.ahap")
            
        } catch {
            print("❌ Failed to load haptic pattern: \(error)")
        }
        
        showingScanner = false
    }

}

// MARK: - Player View
//
//struct PlayerView: View {
//    @ObservedObject var viewModel: VideoPlayerViewModel
//    @Binding var showingScanner: Bool
//    @State private var isLandscape = false
//    private func listenForOrientation() {
//           NotificationCenter.default.addObserver(
//               forName: UIDevice.orientationDidChangeNotification,
//               object: nil,
//               queue: .main
//           ) { _ in
//               let orientation = UIDevice.current.orientation
//               withAnimation {
//                   isLandscape = orientation.isValidInterfaceOrientation ? orientation.isLandscape : false
//               }
//           }
//       }
//    
//    var body: some View {
//        VStack(spacing: 0) {
//            // Header
//            if (!isLandscape)
//            {
//                HStack {
//                    Button(action: { showingScanner = true }) {
//                        Image(systemName: "qrcode.viewfinder")
//                            .font(.title2)
//                            .foregroundColor(.white)
//                            .padding()
//                            .background(Color.white.opacity(0.2))
//                            .clipShape(Circle())
//                    }
//                    
//                    Spacer()
//                    HStack{
//                        Image("logo").resizable().scaledToFit().frame(width:50,height:50)
//                        Text("Tactyl")
//                            .font(.title2)
//                            .fontWeight(.bold)
//                            .foregroundColor(.white)
//                    }
//                    
//                    
//                    Spacer()
//                    
//                    Spacer()
////                    Button(action: {
////                        UIDevice.setOrientation(.landscapeRight)
////                        
////                        viewModel.isLandscape.toggle()
////                    }) {
////                        Image(systemName: "arrow.up.left.and.arrow.down.right")
////                            .font(.title2)
////                            .foregroundColor(.white)
////                            .padding()
////                            .background(Color.white.opacity(0.2))
////                            .clipShape(Circle())
////                    }
//                }
//                .padding()
//            }
//            // Video Player
//            if let player = viewModel.player {
//                
//                // Inline in portrait
//                AVPlayerContainer(player: player)
//                    .cornerRadius(20)
//                    .padding()
//                
//            }
//            
//            if(!isLandscape){
//            // Controls
//            VStack(spacing: 20) {
//                // Progress bar
//                ProgressBar(
//                    value: viewModel.currentTime,
//                    total: viewModel.duration,
//                    onSeek: { viewModel.seek(to: $0) }
//                )
//                
//                // Playback controls
//                HStack(spacing: 40) {
//                    Button(action: { viewModel.seek(to: max(0, viewModel.currentTime - 10)) }) {
//                        Image(systemName: "gobackward.10")
//                            .font(.title)
//                            .foregroundColor(.white)
//                    }
//                    
//                    Button(action: {
//                        if viewModel.isPlaying {
//                            viewModel.pause()
//                        } else {
//                            viewModel.play()
//                        }
//                    }) {
//                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
//                            .font(.system(size: 60))
//                            .foregroundColor(viewModel.isReadyToPlay ? .white : .gray)
//                    }.disabled(!viewModel.isReadyToPlay)
//                    
//                    Button(action: { viewModel.seek(to: min(viewModel.duration, viewModel.currentTime + 10)) }) {
//                        Image(systemName: "goforward.10")
//                            .font(.title)
//                            .foregroundColor(.white)
//                    }
//                }
//                .onAppear {
//                    listenForOrientation()
//                }
//                
//                // Time display
//                HStack {
//                    Text(formatTime(viewModel.currentTime))
//                        .font(.caption)
//                        .foregroundColor(.white.opacity(0.8))
//                    
//                    Spacer()
//                    
//                    Text(formatTime(viewModel.duration))
//                        .font(.caption)
//                        .foregroundColor(.white.opacity(0.8))
//                }
//                .padding(.horizontal)
//                // HERE
//                
//            }
//            .padding()
//        }
//        }
//    }
//    
//    func formatTime(_ seconds: Double) -> String {
//        let mins = Int(seconds) / 60
//        let secs = Int(seconds) % 60
//        return String(format: "%02d:%02d", mins, secs)
//    }
//}

import SwiftUI
import AVKit

struct PlayerView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @Binding var showingScanner: Bool
    @State private var isFullScreen = false
    
    var body: some View {
        ZStack {
            if let player = viewModel.player {
                
                // Fullscreen Player
                if isFullScreen {
                    AVPlayerContainer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            UIDevice.setOrientation(.landscapeRight)
                        }
                        .overlay(
                            VStack {
                                HStack {
                                    Spacer()
                                    Button {
                                        // Exit full screen
                                        UIDevice.setOrientation(.portrait)
                                        isFullScreen = false
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white)
                                            .padding()
                                    }
                                }
                                Spacer()
                            }
                        )
                    
                } else {
                    // Normal portrait layout
                    VStack(spacing: 0) {
                        
                        // Header
                        HStack {
                            Button(action: { showingScanner = true }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            HStack {
                                Image("logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                Text("Tactyl")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Button {
                                isFullScreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                        .padding()
                        
                        // Inline video
                        AVPlayerContainer(player: player)
                            .cornerRadius(20)
                            .padding()
                        
                        // Controls
                        VStack(spacing: 20) {
                            ProgressBar(
                                value: viewModel.currentTime,
                                total: viewModel.duration,
                                onSeek: { viewModel.seek(to: $0) }
                            )
                            
                            HStack(spacing: 40) {
                                Button(action: { viewModel.seek(to: max(0, viewModel.currentTime - 10)) }) {
                                    Image(systemName: "gobackward.10")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: {
                                    if viewModel.isPlaying {
                                        viewModel.pause()
                                    } else {
                                        viewModel.play()
                                    }
                                }) {
                                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(viewModel.isReadyToPlay ? .white : .gray)
                                }
                                .disabled(!viewModel.isReadyToPlay)
                                
                                Button(action: { viewModel.seek(to: min(viewModel.duration, viewModel.currentTime + 10)) }) {
                                    Image(systemName: "goforward.10")
                                        .font(.title)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            HStack {
                                Text(formatTime(viewModel.currentTime))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Spacer()
                                
                                Text(formatTime(viewModel.duration))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal)
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Orientation Helper
extension UIDevice {
    static func setOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }
}


// MARK: - Progress Bar
struct ProgressBar: View {
    let value: Double
    let total: Double
    let onSeek: (Double) -> Void
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    var displayValue: Double {
        isDragging ? dragValue : value
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                
                // Progress fill
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, min(geometry.size.width, CGFloat(displayValue / max(total, 1)) * geometry.size.width)), height: 4)
                
                // Scrubber handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: max(-6, min(geometry.size.width - 6, CGFloat(displayValue / max(total, 1)) * geometry.size.width - 6)))
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragValue = value // Start from current position
                        }
                        let newValue = Double(gesture.location.x / geometry.size.width) * total
                        dragValue = max(0, min(total, newValue))
                    }
                    .onEnded { gesture in
                        let newValue = Double(gesture.location.x / geometry.size.width) * total
                        let finalValue = max(0, min(total, newValue))
                        isDragging = false
                        dragValue = 0
                        onSeek(finalValue) // Only seek once at the end
                    }
            )
            .onTapGesture { location in
                // Handle direct taps for quick seeking
                let newValue = Double(location.x / geometry.size.width) * total
                let finalValue = max(0, min(total, newValue))
                onSeek(finalValue)
            }
        }
        .frame(height: 12)
    }
}

extension ContentView {
 
    private func listenForOrientation() {
           NotificationCenter.default.addObserver(
               forName: UIDevice.orientationDidChangeNotification,
               object: nil,
               queue: .main
           ) { _ in
               let orientation = UIDevice.current.orientation
               withAnimation {
                   isLandscape = orientation.isValidInterfaceOrientation ? orientation.isLandscape : false
               }
           }
       }
    var bodyWithCreator: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 124/255, green: 68/255, blue: 229/255),Color(red: 124/255, green: 68/255, blue: 229/255)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if showingScanner {
                    VStack {
                        ScannerView(
                            scannedData: $scannedData,
                            errorMessage: $errorMessage,
                            showingScanner: $showingScanner,
                            viewModel: viewModel
                        )
                        
                        // Add navigation button to creator
                        NavigationLink(destination: HapticCreatorView()) {
                            Label("Create Haptics", systemImage: "wand.and.stars")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(15)
                        }
                        .padding(.bottom, 30)
                    }
                } else if let _ = viewModel.player {
                    PlayerView(viewModel: viewModel, showingScanner: $showingScanner)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
    
// MARK: - App Entry Point
@main
struct HapticPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

