import CoreMediaIO
import Foundation

/// `CMIOExtensionDeviceSource` 実装 ― virtual camera device の本体。
///
/// device は 1 つ以上の stream を持つ。Decoy では 720p / 30 fps の単一
/// stream を公開し、`DecoyCameraExtensionStreamSource` が frame を送出する。
final class DecoyCameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) lazy var device: CMIOExtensionDevice = CMIOExtensionDevice(
        localizedName: localizedName,
        deviceID: deviceID,
        legacyDeviceID: deviceID.uuidString,
        source: self
    )
    private let deviceID = UUID()
    private let localizedName: String
    private let streamSource = DecoyCameraExtensionStreamSource()

    init(localizedName: String) {
        self.localizedName = localizedName
        super.init()
        do {
            try device.addStream(streamSource.stream)
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
