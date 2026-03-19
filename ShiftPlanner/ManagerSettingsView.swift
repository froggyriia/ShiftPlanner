import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManagerSettingsView: View {
    @EnvironmentObject var session: SessionViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var companyName = ""
    @State private var inviteCode = ""

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
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadManagerData()
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
                Text("Электронная почта")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(email.isEmpty ? "Почта не указана" : email)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            Button("Сохранить имя") {
                saveName()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Компания")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Название компании")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(companyName.isEmpty ? "Компания ещё не создана" : companyName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Код приглашения")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(inviteCode.isEmpty ? "Код приглашения отсутствует" : inviteCode)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Действия")
                .font(.headline)

            Button("Выйти из аккаунта") {
                session.logout()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func loadManagerData() {
        guard let user = Auth.auth().currentUser else {
            message = "Не удалось найти текущего пользователя."
            return
        }

        isLoading = true
        message = ""

        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                isLoading = false
                message = "Не удалось загрузить данные пользователя: \(error.localizedDescription)"
                return
            }

            let data = snapshot?.data() ?? [:]

            name = data["name"] as? String ?? ""
            email = data["email"] as? String ?? user.email ?? ""

            db.collection("companies")
                .whereField("ownerId", isEqualTo: user.uid)
                .getDocuments { companySnapshot, companyError in
                    isLoading = false

                    if let companyError = companyError {
                        message = "Не удалось загрузить данные компании: \(companyError.localizedDescription)"
                        return
                    }

                    guard let companyDoc = companySnapshot?.documents.first else {
                        companyName = ""
                        inviteCode = ""
                        return
                    }

                    let companyData = companyDoc.data()
                    companyName = companyData["name"] as? String ?? ""
                    inviteCode = companyData["inviteCode"] as? String ?? ""
                }
        }
    }

    private func saveName() {
        guard let user = Auth.auth().currentUser else {
            message = "Не удалось найти текущего пользователя."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "Имя не может быть пустым."
            return
        }

        isLoading = true
        message = ""

        db.collection("users").document(user.uid).updateData([
            "name": trimmedName
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не удалось сохранить имя: \(error.localizedDescription)"
            } else {
                name = trimmedName
                message = "Имя успешно обновлено."
            }
        }
    }
}

#Preview {
    ManagerSettingsView()
}
