import SwiftUI
import CoreHaptics

struct VibratorView: View {
    @State private var engine: CHHapticEngine?
    @State private var intensity: Float =  1.0
    @State private var isOn = false
    @State private var player: CHHapticAdvancedPatternPlayer?
    @State private var loopTimer: Timer?
    
    var body: some View {
        ZStack{
            Color(.sRGB,
                                                               red: 0xFF/255,
                                                               green: 0xE5/255,
                                                               blue: 0xB4/255,
                                                               opacity: 1.0)
        VStack(spacing: 40) {
            Spacer()
            Text("🍑").font(.system(size:200)).onAppear{
                prepareHaptics()
                startInfiniteLoop()
            }.onDisappear{
                stopHaptics()
                loopTimer?.invalidate()
                
            }
            // Slider for controlling "strength"
            //            VStack {
            //                Text("Intensity: \(String(format: "%.2f", intensity))")
            //                    .font(.headline)
            //                Slider(value: Binding(
            //                    get: { Double(intensity) },
            //                    set: { newVal in
            //                        intensity = Float(newVal)
            //                        if isOn {
            //                            updateIntensity()
            //                        }
            //                    }
            //                ), in: 0...1)
            //            }
            //            .padding(.horizontal, 40)
            Text("Feisty Bwoiiii ⚡️") .foregroundColor(.black)
                .cornerRadius(16)
                .padding(.horizontal, 40)
            // On/Off button
                        Button(action: {
                            isOn.toggle()
                            if isOn {
                                prepareHaptics()
                                startInfiniteLoop()
                                
                            } else {
                                stopHaptics()
                            }
                        }) {
                            Text("")
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .padding(.horizontal, 40)
                        }
            
            Spacer()
        }
        }
        .onAppear {
            prepareHaptics()
        }.navigationBarBackButtonHidden().background(Color(.sRGB,
                                                           red: 0xFF/255,
                                                           green: 0xE5/255,
                                                           blue: 0xB4/255,
                                                           opacity: 1.0))
    }
    
    // MARK: - Haptic Setup
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptic engine error: \(error.localizedDescription)")
        }
    }
    
    private func startInfiniteLoop() {
          loopTimer?.invalidate()
         playInfiniteVibe()
          
          // Schedule repeat before the current one ends
          loopTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
            playInfiniteVibe()
          }
      }
    
    
    private func playInfiniteVibe() {
        guard let engine else { return }
        
        do {
            try engine.start()
            
            // Super long duration "continuous" event (acts like infinite until you stop)
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            
            let continuousEvent = CHHapticEvent(eventType: .hapticContinuous,
                                               parameters: [intensityParam, sharpnessParam],
                                               relativeTime: 0,
                                               duration: 100) // 100s long
            
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            player = try engine.makeAdvancedPlayer(with: pattern)
            
            try player?.start(atTime: 0)
            
        } catch {
            print("Failed to play haptics: \(error.localizedDescription)")
        }
    }
    
    private func updateIntensity() {
        guard let player else { return }
        do {
            let param = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                 value: intensity,
                                                 relativeTime: 0)
            try player.sendParameters([param], atTime: 0)
        } catch {
            print("Failed to update intensity: \(error.localizedDescription)")
        }
    }
    
    private func stopHaptics() {
        do{
        try  player?.stop(atTime: 0)
    }
        catch{
            print("error:\(error)")
        }
        engine?.stop(completionHandler: nil)
    }
}

#Preview {
    VibratorView()
}
