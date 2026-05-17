import CoreMediaIO
import Foundation

/// `CMIOExtensionDeviceSource` 実装 ― virtual camera device の本体。
///
/// device は 1 つ以上の stream を持つ。Decoy では 1080p / 30 fps の単一
/// stream を公開し、`DecoyCameraExtensionStreamSource` が frame を送出する。
final class DecoyCameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private let streamSource: DecoyCameraExtensionStreamSource

    init(localizedName: String) {
        let deviceID = UUID()
        streamSource = DecoyCameraExtensionStreamSource()
        super.init()
        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: deviceID.uuidString,
            source: self
        )
        do {
            try device.addStream(streamSource.stream)
            streamSource.bind(to: device)
        } catch {
            fatalError("Failed to add stream to device: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) {
            result.model = "Decoy Virtual Camera"
        }
        return result
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}
}
