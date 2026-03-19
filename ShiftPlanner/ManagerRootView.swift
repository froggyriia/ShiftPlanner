import SwiftUI

struct ManagerRootView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        TabView {
            ManagerCompanySetupView()
                .tabItem {
                    Label("Панель", systemImage: "building.2")
                }

            ManagerRequirementsView()
                .tabItem {
                    Label("Правила", systemImage: "list.bullet.rectangle")
                }

            ManagerGeneratedScheduleView()
                .tabItem {
                    Label("Расписание", systemImage: "calendar")
                }

            ManagerSettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ManagerRootView()
}
