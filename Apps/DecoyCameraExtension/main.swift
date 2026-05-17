import CoreMediaIO
import Foundation

// CMIO Camera Extension の entry point。
// `CMIOExtensionProvider.startService(provider:)` に登録した provider が
// `CMIOExtensionProvider` framework によって client (Zoom 等) からの参照
// 経路に乗る。RunLoop は extension manager が回し続ける。
let providerSource = DecoyCameraExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
