import WidgetKit
import SwiftUI

@main
struct SpotPriceWidgetFinlandBundle: WidgetBundle {
    var body: some Widget {
        SpotPriceWidgetFinland()
        FinlandGridForecastWidget()
        HelsinkiAirRadarWidget()
    }
}
