import SwiftUI

struct EmployeeRootView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        TabView {
        

            EmployeeAvailabilityView()
                .tabItem {
                    Label("Когда доступен", systemImage: "pencil")
                }
            EmployeeScheduleView()
                .tabItem {
                    Label("Расписание", systemImage: "calendar")
                }

            EmployeeSettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
        }
    }
}

#Preview {
    EmployeeRootView()
}
