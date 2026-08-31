import Foundation

@objc(SpotPriceWidgetUninstalling)
protocol SpotPriceWidgetUninstalling {
    func moveContainingAppToTrash(
        withReply reply: @escaping (_ destinationPath: String?, _ errorMessage: String?) -> Void
    )

    func installUpdate(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        withReply reply: @escaping (_ installedVersion: String?, _ errorMessage: String?) -> Void
    )
}
