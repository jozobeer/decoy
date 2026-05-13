import AppKit
import Domain
import SwiftUI

/// Menu bar root view. Reads everything from `MenuBarViewModel` and
/// dispatches user intents back through it; holds no logic of its own
/// so the view-model is the single audit point for behaviour.
public struct MenuView: View {
    @ObservedObject private var viewModel: MenuBarViewModel

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusRow(viewModel: viewModel)
            Divider()
            RecordingSection(viewModel: viewModel)
            Divider()
            DecoySection(viewModel: viewModel)
            if let message = viewModel.lastErrorMessage {
                Divider()
                ErrorRow(message: message) { viewModel.lastErrorMessage = nil }
            }
            Divider()
            Button("Quit Decoy") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
        .task { await viewModel.start() }
    }
}

// MARK: - Status row

private struct StatusRow: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                Text(viewModel.isRecording ? "REC" : "IDLE")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(outputModeLabel)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.isInDecoy ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                )
        }
    }

    private var outputModeLabel: String {
        switch viewModel.outputMode {
        case .live: return "LIVE"
        case .playback(let mode): return "DECOY · \(label(for: mode))"
        }
    }

    private func label(for mode: PlaybackMode) -> String {
        switch mode {
        case .once: return "Once"
        case .loop: return "Loop"
        case .pingPong: return "PingPong"
        }
    }
}

// MARK: - Recording section

private struct RecordingSection: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("Start recording", systemImage: "record.circle")
            }
            .disabled(viewModel.isRecording)

            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("Stop recording", systemImage: "stop.circle")
            }
            .disabled(!viewModel.isRecording)
        }
    }
}

// MARK: - Decoy section

private struct DecoySection: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await viewModel.startDecoy() }
            } label: {
                Label("Start decoy", systemImage: "play.circle")
            }
            .disabled(viewModel.isInDecoy)

            Picker("Mode", selection: pickerBinding) {
                Text("Once").tag(PlaybackMode.once)
                Text("Loop").tag(PlaybackMode.loop)
                Text("PingPong").tag(PlaybackMode.pingPong)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                Task { await viewModel.returnToLive() }
            } label: {
                Label("Return to live", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(!viewModel.isInDecoy)
        }
    }

    /// Binds the Picker to `pendingPlaybackMode` for display, and routes
    /// every change through the view-model so a Picker tap while in
    /// decoy hot-switches the mode (instead of waiting for the Start
    /// button).
    private var pickerBinding: Binding<PlaybackMode> {
        Binding(
            get: { viewModel.activePlaybackMode ?? viewModel.pendingPlaybackMode },
            set: { newValue in Task { await viewModel.selectPlaybackMode(newValue) } }
        )
    }
}

// MARK: - Error row

private struct ErrorRow: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
