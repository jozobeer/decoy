import CoreMediaIO
import Foundation

/// `CMIOExtensionProviderSource` 実装 ― extension の root。
///
/// extension は 1 つの provider を持ち、provider は 1 つ以上の device を
/// 公開する。Decoy では「Decoy」という名前の virtual camera device を
/// ひとつだけ公開する。
final class DecoyCameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource: DecoyCameraExtensionDeviceSource

    init(clientQueue: DispatchQueue?) {
        deviceSource = DecoyCameraExtensionDeviceSource(localizedName: "Decoy")
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            // device 追加失敗は extension 全体が機能しなくなるため致命的だが、
            // throw できる場所ではないので fatalError で潰す。
            fatalError("Failed to add device to provider: \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            result.manufacturer = "Decoy"
        }
        return result
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
