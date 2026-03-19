import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EmployeeSettingsView: View {
    @EnvironmentObject var session: SessionViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var companyName = ""
    @State private var assignedPositionName = ""

    @State private var isLoading = false
    @State private var message = ""

    let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileSection
                    companySection
                    actionsSection

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadUserData()
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Профиль")
                .font(.headline)

            TextField("Имя", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(email.isEmpty ? "No email" : email)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            Button("Сохранить") {
                saveName()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Информация о работе")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Компания")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(companyName.isEmpty ? "Вы еще не присоединились к компании. Присоединитесь с помощью кода от менеджера" : companyName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Должность")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(assignedPositionName.isEmpty ? "Должность еще не назначена" : assignedPositionName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            Button("Log out") {
                session.logout()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func loadUserData() {
        guard let user = Auth.auth().currentUser else {
            message = "No logged in user found."
            return
        }

        isLoading = true
        message = ""

        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                isLoading = false
                message = "Failed to load user: \(error.localizedDescription)"
                return
            }

            let data = snapshot?.data() ?? [:]

            name = data["name"] as? String ?? ""
            email = data["email"] as? String ?? user.email ?? ""
            assignedPositionName = data["assignedPositionName"] as? String ?? ""

            let companyId = data["companyId"] as? String ?? ""

            if companyId.isEmpty {
                companyName = ""
                isLoading = false
                return
            }

            db.collection("companies").document(companyId).getDocument { companySnapshot, companyError in
                isLoading = false

                if let companyError = companyError {
                    message = "Failed to load company: \(companyError.localizedDescription)"
                    return
                }

                let companyData = companySnapshot?.data() ?? [:]
                companyName = companyData["name"] as? String ?? ""
            }
        }
    }

    private func saveName() {
        guard let user = Auth.auth().currentUser else {
            message = "No logged in user found."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "Name cannot be empty."
            return
        }

        isLoading = true
        message = ""

        db.collection("users").document(user.uid).updateData([
            "name": trimmedName
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Failed to save name: \(error.localizedDescription)"
            } else {
                name = trimmedName
                message = "Name updated successfully."
            }
        }
    }
}

#Preview {
    EmployeeSettingsView()
}
