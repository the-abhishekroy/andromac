import WidgetKit
import SwiftUI

@main
struct AndromacWidgetBundle: WidgetBundle {
    var body: some Widget {
        AndromacStatusWidget()
        if #available(macOS 26.0, *) {
            ConnectionControl()
            ViewPhoneControl()
        }
    }
}
