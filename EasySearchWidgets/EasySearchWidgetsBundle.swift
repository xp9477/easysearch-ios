import SwiftUI
import WidgetKit

@main
struct EasySearchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SearchWidget()
        UTProgressWidget()
        TrainingWidget()
        LockScreenStatusWidget()
    }
}
