import Foundation

@objc(SpotPriceWidgetUninstalling)
protocol SpotPriceWidgetUninstalling {
    func moveContainingAppToTrash(
        withReply reply: @escaping (_ destinationPath: String?, _ errorMessage: String?) -> Void
    )
}
