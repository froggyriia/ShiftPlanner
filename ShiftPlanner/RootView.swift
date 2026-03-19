import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionViewModel()

    var body: some View {
        Group {
            if session.isLoading {
                ProgressView("Loading...")
            } else if session.firebaseUser == nil {
                AuthView()
                    .environmentObject(session)
            } else if session.userRole == "manager" {
                ManagerRootView()
                    .environmentObject(session)
            } else if session.userRole == "employee" {
                EmployeeRootView()
                    .environmentObject(session)
            } else {
                VStack(spacing: 16) {
                    Text("Could not determine user role.")
                    Button("Log out") {
                        session.logout()
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
}
