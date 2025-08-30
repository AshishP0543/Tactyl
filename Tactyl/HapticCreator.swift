//
//  HapticCreator.swift
//  Tactyl
//
//  Created by Ashish Patil on 31/08/25.
//

import Foundation
import SwiftUI
import CoreHaptics

// MARK: - Haptic Creator View
struct HapticCreatorView: View {
        @StateObject private var hapticManager = HapticManager()
        @State private var hapticEvents: [HapticEventItem] = []
        @State private var selectedEventId: UUID?
        @State private var isPlaying = false
        @State private var currentPlaybackTime: Double = 0
        @State private var totalDuration: Double = 10.0 // Default 10 seconds
    @State private var showVibrator = false
        // Event creation parameters
        @State private var eventType: String = "transient"
        @State private var intensity: Double = 0.5
        @State private var sharpness: Double = 0.5
        @State private var duration: Double = 0.5
        @State private var eventTime: Double = 0.0
        
        // Playback timer
        @State private var playbackTimer: Timer?
        @State private var scheduledWorkItems: [DispatchWorkItem] = []
        
        var body: some View {
        
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 124/255, green: 68/255, blue: 229/255), Color(red: 124/255, green: 68/255, blue: 229/255)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HeaderView()
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Timeline View
                            TimelineSection(
                                hapticEvents: $hapticEvents,
                                selectedEventId: $selectedEventId,
                                currentPlaybackTime: $currentPlaybackTime,
                                totalDuration: $totalDuration,
                                isPlaying: isPlaying,
                                onTimeSelect: { time in
                                    eventTime = time
                                }
                            )
                            
                            // Event Controls
                            EventControlsSection(
                                eventType: $eventType,
                                intensity: $intensity,
                                sharpness: $sharpness,
                                duration: $duration,
                                eventTime: $eventTime,
                                totalDuration: totalDuration,
                                onAddEvent: addHapticEvent,
                                onTestEvent: testCurrentSettings
                            )
                            
                            // Preset Patterns
                            PresetPatternsSection(onSelectPreset: applyPreset)
                            
                            // Event List
                            EventListSection(
                                hapticEvents: $hapticEvents,
                                selectedEventId: $selectedEventId,
                                onSelectEvent: selectEvent,
                                onDeleteEvent: deleteEvent
                            )
                            
                            // Playback Controls
                            PlaybackControlsSection(
                                isPlaying: $isPlaying,
                                onPlay: playSequence,
                                onStop: stopSequence,
                                onClear: clearAllEvents,
                                onExport: exportPattern
                            )
//                            Button{
//                                showVibrator = true
//                            }label:{
//                                Text("💦").font(.largeTitle)
//                                    .padding()
//                                    .background(Color.white.opacity(0.1))
//                                    .cornerRadius(15)
//                            }.padding()
//                                .background(Color.white.opacity(0.1))
//                                .cornerRadius(15)
                        }
                        .padding()
                    }.navigationBarBackButtonHidden(true).onDisappear {
                        stopSequence()
                    }
                } .navigationBarBackButtonHidden(true)
            
            }
    }
    
    // MARK: - Functions
    
    func addHapticEvent() {
        let newEvent = HapticEventItem(
            id: UUID(),
            time: eventTime,
            type: eventType,
            intensity: intensity,
            sharpness: sharpness,
            duration: eventType == "transient" ? 0 : duration
        )
        
        hapticEvents.append(newEvent)
        hapticEvents.sort { $0.time < $1.time }
        
        // Play the event immediately as feedback
        testCurrentSettings()
    }
    
    func testCurrentSettings() {
        let testEvent = HapticEvent(
            Time: 0,
            EventType: eventType == "transient" ? "HapticTransient" : "HapticContinuous",
            EventDuration: eventType == "transient" ? nil : duration,
            EventParameters: [
                EventParameter(ParameterID: "HapticIntensity", ParameterValue: intensity),
                EventParameter(ParameterID: "HapticSharpness", ParameterValue: sharpness)
            ]
        )
        
        hapticManager.playHapticEvent(testEvent)
    }
    
    func selectEvent(_ event: HapticEventItem) {
        selectedEventId = event.id
        eventType = event.type
        intensity = event.intensity
        sharpness = event.sharpness
        duration = event.duration
        eventTime = event.time
    }
    
    func deleteEvent(_ id: UUID) {
        hapticEvents.removeAll { $0.id == id }
        if selectedEventId == id {
            selectedEventId = nil
        }
    }
    
    func clearAllEvents() {
        hapticEvents.removeAll()
        selectedEventId = nil
        stopSequence()
    }
    
    func playSequence() {
        stopSequence() // Clear any existing playback
        
        isPlaying = true
        currentPlaybackTime = 0
        
        // Schedule all haptic events
        for event in hapticEvents {
            let workItem = DispatchWorkItem { [self] in
                let hapticEvent = HapticEvent(
                    Time: event.time,
                    EventType: event.type == "transient" ? "HapticTransient" : "HapticContinuous",
                    EventDuration: event.type == "transient" ? nil : event.duration,
                    EventParameters: [
                        EventParameter(ParameterID: "HapticIntensity", ParameterValue: event.intensity),
                        EventParameter(ParameterID: "HapticSharpness", ParameterValue: event.sharpness)
                    ]
                )
                self.hapticManager.playHapticEvent(hapticEvent)
            }
            
            scheduledWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + event.time, execute: workItem)
        }
        
        // Start playback timer for UI update
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            currentPlaybackTime += 0.05
            if currentPlaybackTime >= totalDuration {
                stopSequence()
            }
        }
    }
    
    func stopSequence() {
        isPlaying = false
        currentPlaybackTime = 0
        
        // Cancel all scheduled haptics
        scheduledWorkItems.forEach { $0.cancel() }
        scheduledWorkItems.removeAll()
        
        // Stop timer
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    func applyPreset(_ preset: HapticPreset) {
        clearAllEvents()
        
        for (index, event) in preset.events.enumerated() {
            let newEvent = HapticEventItem(
                id: UUID(),
                time: event.time,
                type: event.type,
                intensity: event.intensity,
                sharpness: event.sharpness,
                duration: event.duration
            )
            hapticEvents.append(newEvent)
        }
        
        hapticEvents.sort { $0.time < $1.time }
        
        // Adjust total duration if needed
        if let lastEvent = hapticEvents.last {
            totalDuration = max(10, lastEvent.time + 2)
        }
    }
    
    func exportPattern() {
        // Convert to AHAP format
        let pattern = HapticPattern(
            Version: 1.0,
            Pattern: hapticEvents.map { event in
                PatternElement(
                    Event: HapticEvent(
                        Time: event.time,
                        EventType: event.type == "transient" ? "HapticTransient" : "HapticContinuous",
                        EventDuration: event.type == "transient" ? nil : event.duration,
                        EventParameters: [
                            EventParameter(ParameterID: "HapticIntensity", ParameterValue: event.intensity),
                            EventParameter(ParameterID: "HapticSharpness", ParameterValue: event.sharpness)
                        ]
                    )
                )
            }
        )
        
        // Share or save pattern
        if let data = try? JSONEncoder().encode(pattern) {
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            UIPasteboard.general.string = jsonString
            // Show success message (could add an alert here)
            print("Pattern copied to clipboard!")
        }
    }
}

// MARK: - Supporting Views

struct HeaderView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack {
                Text("Haptic Creator")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Design Custom Patterns")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding()
    }
}

struct TimelineSection: View {
    @Binding var hapticEvents: [HapticEventItem]
    @Binding var selectedEventId: UUID?
    @Binding var currentPlaybackTime: Double
    @Binding var totalDuration: Double
    let isPlaying: Bool
    let onTimeSelect: (Double) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.headline)
                .foregroundColor(.white)
            
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 80)
                
                // Grid lines
                ForEach(0...10, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 80)
                        .offset(x: CGFloat(i) * (UIScreen.main.bounds.width - 40) / 10)
                }
                
                // Haptic events
                ForEach(hapticEvents) { event in
                    HapticEventMarker(
                        event: event,
                        totalDuration: totalDuration,
                        isSelected: selectedEventId == event.id
                    )
                }
                
                // Playback indicator
                if isPlaying {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: 80)
                        .offset(x: CGFloat(currentPlaybackTime / totalDuration) * (UIScreen.main.bounds.width - 40))
                        .animation(.linear(duration: 0.05), value: currentPlaybackTime)
                }
            }
            .frame(height: 80)
            .onTapGesture { location in
                let percentage = location.x / (UIScreen.main.bounds.width - 40)
                let time = Double(percentage) * totalDuration
                onTimeSelect(max(0, min(totalDuration, time)))
            }
            
            // Time labels
            HStack {
                Text("0:00")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text(formatTime(totalDuration))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
    
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct HapticEventMarker: View {
    let event: HapticEventItem
    let totalDuration: Double
    let isSelected: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(event.type == "transient" ? Color.blue : Color.green)
            .frame(
                width: event.type == "transient" ? 4 : CGFloat(event.duration / totalDuration) * (UIScreen.main.bounds.width - 40),
                height: 60
            )
            .overlay(
                isSelected ?
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 2) : nil
            )
            .offset(x: CGFloat(event.time / totalDuration) * (UIScreen.main.bounds.width - 40))
    }
}

struct EventControlsSection: View {
    @Binding var eventType: String
    @Binding var intensity: Double
    @Binding var sharpness: Double
    @Binding var duration: Double
    @Binding var eventTime: Double
    let totalDuration: Double
    let onAddEvent: () -> Void
    let onTestEvent: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Event Properties")
                .font(.headline)
                .foregroundColor(.white)
            
            // Event Type
            HStack {
                Text("Type")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 80, alignment: .leading)
                
                Picker("Type", selection: $eventType) {
                    Text("Tap").tag("transient")
                    Text("Continuous").tag("continuous")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Time
            HStack {
                Text("Time")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 80, alignment: .leading)
                
                Slider(value: $eventTime, in: 0...totalDuration)
                    .accentColor(.white)
                
                Text(String(format: "%.1fs", eventTime))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 50)
            }
            
            // Intensity
            HStack {
                Text("Intensity")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 80, alignment: .leading)
                
                Slider(value: $intensity, in: 0...1)
                    .accentColor(.white)
                
                Text(String(format: "%.2f", intensity))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 50)
            }
            
            // Sharpness
            HStack {
                Text("Sharpness")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 80, alignment: .leading)
                
                Slider(value: $sharpness, in: 0...1)
                    .accentColor(.white)
                
                Text(String(format: "%.2f", sharpness))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 50)
            }
            
            // Duration (for continuous events)
            if eventType == "continuous" {
                HStack {
                    Text("Duration")
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 80, alignment: .leading)
                    
                    Slider(value: $duration, in: 0.1...5)
                        .accentColor(.white)
                    
                    Text(String(format: "%.1fs", duration))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 50)
                }
            }
            
            // Action buttons
            HStack(spacing: 15) {
                Button(action: onTestEvent) {
                    Label("Test", systemImage: "hand.tap.fill")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(10)
                }
                
                Button(action: onAddEvent) {
                    Label("Add Event", systemImage: "plus.circle.fill")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.6))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

struct PresetPatternsSection: View {
    let onSelectPreset: (HapticPreset) -> Void
    
    let presets = [
        HapticPreset(name: "💓 Heartbeat", events: [
            HapticEventItem(id: UUID(), time: 0, type: "transient", intensity: 0.8, sharpness: 0.3, duration: 0),
            HapticEventItem(id: UUID(), time: 0.15, type: "transient", intensity: 1.0, sharpness: 0.5, duration: 0),
            HapticEventItem(id: UUID(), time: 0.6, type: "transient", intensity: 0.6, sharpness: 0.3, duration: 0),
            HapticEventItem(id: UUID(), time: 0.75, type: "transient", intensity: 0.8, sharpness: 0.4, duration: 0)
        ]),
        HapticPreset(name: "🔔 Notification", events: [
            HapticEventItem(id: UUID(), time: 0, type: "transient", intensity: 0.7, sharpness: 0.8, duration: 0),
            HapticEventItem(id: UUID(), time: 0.1, type: "transient", intensity: 0.5, sharpness: 0.6, duration: 0)
        ]),
        HapticPreset(name: "⚡ Impact", events: [
            HapticEventItem(id: UUID(), time: 0, type: "transient", intensity: 1.0, sharpness: 1.0, duration: 0),
            HapticEventItem(id: UUID(), time: 0.05, type: "continuous", intensity: 0.7, sharpness: 0.5, duration: 0.2)
        ]),
        HapticPreset(name: "🌊 Wave", events: [
            HapticEventItem(id: UUID(), time: 0, type: "continuous", intensity: 0.3, sharpness: 0.2, duration: 0.5),
            HapticEventItem(id: UUID(), time: 0.5, type: "continuous", intensity: 0.6, sharpness: 0.4, duration: 0.5),
            HapticEventItem(id: UUID(), time: 1.0, type: "continuous", intensity: 0.9, sharpness: 0.6, duration: 0.5),
            HapticEventItem(id: UUID(), time: 1.5, type: "continuous", intensity: 0.6, sharpness: 0.4, duration: 0.5),
            HapticEventItem(id: UUID(), time: 2.0, type: "continuous", intensity: 0.3, sharpness: 0.2, duration: 0.5)
        ])
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preset Patterns")
                .font(.headline)
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presets, id: \.name) { preset in
                        Button(action: { onSelectPreset(preset) }) {
                            Text(preset.name)
                                .foregroundColor(.white)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

struct EventListSection: View {
    @Binding var hapticEvents: [HapticEventItem]
    @Binding var selectedEventId: UUID?
    let onSelectEvent: (HapticEventItem) -> Void
    let onDeleteEvent: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events (\(hapticEvents.count))")
                .font(.headline)
                .foregroundColor(.white)
            
            if hapticEvents.isEmpty {
                Text("No events added yet")
                    .foregroundColor(.white.opacity(0.5))
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(hapticEvents) { event in
                    HStack {
                        Image(systemName: event.type == "transient" ? "bolt.fill" : "waveform")
                            .foregroundColor(event.type == "transient" ? .blue : .green)
                        
                        VStack(alignment: .leading) {
                            Text("\(String(format: "%.1fs", event.time)) - \(event.type)")
                                .foregroundColor(.white)
                            Text("I: \(String(format: "%.2f", event.intensity)) S: \(String(format: "%.2f", event.sharpness))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Button(action: { onDeleteEvent(event.id) }) {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding()
                    .background(selectedEventId == event.id ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .onTapGesture {
                        onSelectEvent(event)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

struct PlaybackControlsSection: View {
    @Binding var isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void
    let onClear: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 15) {
                Button(action: isPlaying ? onStop : onPlay) {
                    Label(isPlaying ? "Stop" : "Play All", systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isPlaying ? Color.red.opacity(0.6) : Color.green.opacity(0.6))
                        .cornerRadius(10)
                }
                
                Button(action: onClear) {
                    Label("Clear", systemImage: "trash.circle.fill")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.6))
                        .cornerRadius(10)
                }
            }
            
            Button(action: onExport) {
                Label("Copy Pattern to Clipboard", systemImage: "doc.on.doc.fill")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

// MARK: - Models

struct HapticEventItem: Identifiable {
    let id: UUID
    var time: Double
    var type: String
    var intensity: Double
    var sharpness: Double
    var duration: Double
}

struct HapticPreset {
    let name: String
    let events: [HapticEventItem]
}

// MARK: - Navigation Update
// Add this to your main ContentView to navigate to the creator:


