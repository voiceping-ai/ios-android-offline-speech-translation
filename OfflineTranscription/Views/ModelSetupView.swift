import SwiftUI

struct ModelSetupView: View {
    @Environment(WhisperService.self) private var whisperService
    @State private var viewModel: ModelManagementViewModel?

    var body: some View {
        let isBusy = whisperService.modelState == .downloading
            || whisperService.modelState == .loading

        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)
                    Text("Offline Transcription")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("setup_title")
                    Text(
                        "Download a speech recognition model to get started. Models are stored on-device for fully offline use."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
                .padding(.top, 40)

                // Model Picker grouped by family
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ModelInfo.modelsByFamily, id: \.family) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.family.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                ForEach(group.models) { model in
                                    let isSelectedModel = whisperService.selectedModel.id == model.id
                                    let isDownloadingSelectedModel =
                                        whisperService.modelState == .downloading
                                        && isSelectedModel

                                    ModelPickerRow(
                                        model: model,
                                        isSelected: isSelectedModel,
                                        isDownloaded: viewModel?.isModelDownloaded(model) ?? false,
                                        isDownloading: isDownloadingSelectedModel,
                                        downloadProgress: whisperService.downloadProgress
                                    ) {
                                        whisperService.selectedModel = model
                                        Task {
                                            await viewModel?.downloadAndSetup()
                                        }
                                    }
                                    .disabled(isBusy)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Progress / Status
                VStack(spacing: 16) {
                    if whisperService.modelState == .loading {
                        ProgressView("Loading model...")
                    } else if whisperService.modelState != .downloading {
                        Text("Tap a model to download and get started.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .accessibilityIdentifier("setup_prompt")
                    }

                    if let error = whisperService.lastError {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
            }
            .accessibilityIdentifier("model_setup_view")
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel = ModelManagementViewModel(whisperService: whisperService)
        }
    }
}
