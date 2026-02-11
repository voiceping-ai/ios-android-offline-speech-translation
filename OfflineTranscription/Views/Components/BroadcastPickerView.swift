import SwiftUI
import ReplayKit

/// UIViewRepresentable wrapper for RPSystemBroadcastPickerView.
/// Shows the system broadcast picker button that lets users start
/// screen recording with the Broadcast Upload Extension.
struct BroadcastPickerView: UIViewRepresentable {
    /// The bundle identifier of the Broadcast Upload Extension.
    static let extensionBundleID = "com.voiceping.translate.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        picker.preferredExtension = Self.extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        // No updates needed
    }
}
