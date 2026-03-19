import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManagerCompanySetupView: View {
    @State private var companyId: String? = nil
    @State private var companyName = ""
    @State private var newCompanyName = ""

    @State private var newPositionName = ""
    @State private var positions: [WorkPosition] = []
    @State private var employees: [CompanyEmployee] = []

    @State private var isLoading = false
    @State private var message = ""
    @State private var inviteCode = ""

    let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Дашборд")
                    .font(.largeTitle)
                    .bold()

                if isLoading && companyId == nil {
                    ProgressView("Загрузка...")
                } else if companyId == nil {
                    createCompanySection
                } else {
                    existingCompanySection
                }

                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding()
            
            .onAppear {
                loadManagerCompany()
            }
        }
    }

    private var createCompanySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Создать компанию")
                .font(.headline)

            TextField("Название компании", text: $newCompanyName)
                .textFieldStyle(.roundedBorder)

            Button("Создать") {
                createCompany()
            }
            .buttonStyle(.borderedProminent)
            .disabled(newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
    }

    private var existingCompanySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 12) {
                    Text("Компания")
                        .font(.headline)

                    TextField("Название компании", text: $companyName)
                        .textFieldStyle(.roundedBorder)

                    Button("Сохранить") {
                        updateCompanyName()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Код приглашения")
                        .font(.headline)

                    HStack {
                        Text(inviteCode.isEmpty ? "—" : inviteCode)
                            .font(.title2)
                            .bold()

                        Spacer()

                    
                        
                        ShareLink(item: inviteCode) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Рабочие позиции")
                        .font(.headline)

                    HStack {
                        TextField("Добавить позицию", text: $newPositionName)
                            .textFieldStyle(.roundedBorder)

                        Button("Добавить") {
                            addPosition()
                        }
                        .disabled(newPositionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }

                    if positions.isEmpty {
                        Text("-")
                            .foregroundColor(.gray)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(positions) { position in
                                HStack {
                                    Text(position.name)

                                    Spacer()

                                    Button(role: .destructive) {
                                        if let index = positions.firstIndex(where: { $0.id == position.id }) {
                                            deletePosition(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .disabled(isLoading)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Сотрудники")
                            .font(.headline)

                        Spacer()

                        Button("Обновить") {
                            loadEmployees()
                        }
                        .disabled(isLoading)
                    }

                    if employees.isEmpty {
                        Text("Сотрудники еще не присоединились")
                            .foregroundColor(.gray)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(employees) { employee in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(employee.name)
                                        .font(.headline)

                                    Text(employee.email)
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    Text(
                                        employee.assignedPositionName.isEmpty
                                        ? "Позиция еще не назначена"
                                        : "Назначено: \(employee.assignedPositionName)"
                                    )
                                    .font(.subheadline)

                                    Picker(
                                        "Назначить позицию",
                                        selection: Binding(
                                            get: { employee.assignedPositionId },
                                            set: { newPositionId in
                                                if newPositionId.isEmpty {
                                                    removeAssignedPosition(from: employee)
                                                } else if let selectedPosition = positions.first(where: { $0.id == newPositionId }) {
                                                    assignPosition(to: employee, position: selectedPosition)
                                                }
                                            }
                                        )
                                    ) {
                                        Text("Не назанчена позиция").tag("")
                                        ForEach(positions) { position in
                                            Text(position.name).tag(position.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .disabled(isLoading || positions.isEmpty)

                                    Button(role: .destructive) {
                                        removeEmployeeFromCompany(employee)
                                    } label: {
                                        Text("Удалить из компании")
                                    }
                                    .disabled(isLoading)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func loadManagerCompany() {
        guard let user = Auth.auth().currentUser else {
            message = "Данные о пользователе не найдены"
            return
        }

        isLoading = true
        message = ""

        db.collection("companies")
            .whereField("ownerId", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    isLoading = false
                    message = "Не получилось загрузить данные о компании: \(error.localizedDescription)"
                    return
                }

                guard let document = snapshot?.documents.first else {
                    isLoading = false
                    message = "Компания еще не создана"
                    return
                }

                companyId = document.documentID
                companyName = document.data()["name"] as? String ?? ""
                inviteCode = document.data()["inviteCode"] as? String ?? ""
                isLoading = false

                loadPositions()
                loadEmployees()
            }
    }

    private func generateInviteCode(length: Int = 6) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in letters.randomElement() })
    }

    private func createCompany() {
        guard let user = Auth.auth().currentUser else {
            message = "Данные о пользователе не найдены"
            return
        }

        let trimmedName = newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isLoading = true
        message = ""

        let newInviteCode = generateInviteCode()

        let companyData: [String: Any] = [
            "name": trimmedName,
            "ownerId": user.uid,
            "inviteCode": newInviteCode,
            "createdAt": Timestamp()
        ]

        let docRef = db.collection("companies").document()

        docRef.setData(companyData) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось создать компанию: \(error.localizedDescription)"
            } else {
                companyId = docRef.documentID
                companyName = trimmedName
                newCompanyName = ""
                inviteCode = newInviteCode
                message = "Компания успешно создана"

                loadPositions()
                loadEmployees()
            }
        }
    }

    private func updateCompanyName() {
        guard let companyId = companyId else { return }

        let trimmedName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isLoading = true
        message = ""

        db.collection("companies").document(companyId).updateData([
            "name": trimmedName
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось обновить данные о компании: \(error.localizedDescription)"
            } else {
                companyName = trimmedName
                message = "Название компании обновлено"
            }
        }
    }

    private func loadPositions() {
        guard let companyId = companyId else { return }

        isLoading = true
        message = ""

        db.collection("work_positions")
            .whereField("companyId", isEqualTo: companyId)
            .getDocuments { snapshot, error in
                isLoading = false

                if let error = error {
                    message = "Не получилось загрузить данные о позициях: \(error.localizedDescription)"
                    return
                }

                let docs = snapshot?.documents ?? []

                positions = docs.map { doc in
                    let data = doc.data()
                    return WorkPosition(
                        id: doc.documentID,
                        companyId: data["companyId"] as? String ?? "",
                        name: data["name"] as? String ?? ""
                    )
                }
            }
    }

    private func addPosition() {
        guard let companyId = companyId else {
            message = "Сначала создайте компанию"
            return
        }

        let trimmedName = newPositionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isLoading = true
        message = ""

        let positionData: [String: Any] = [
            "companyId": companyId,
            "name": trimmedName,
            "createdAt": Timestamp()
        ]

        let docRef = db.collection("work_positions").document()

        docRef.setData(positionData) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось добавить позицию: \(error.localizedDescription)"
            } else {
                positions.append(
                    WorkPosition(
                        id: docRef.documentID,
                        companyId: companyId,
                        name: trimmedName
                    )
                )
                newPositionName = ""
                message = "Позиция добавлена"
            }
        }
    }

    private func deletePosition(at offsets: IndexSet) {
        guard let index = offsets.first else { return }

        let position = positions[index]

        isLoading = true
        message = ""

        db.collection("work_positions").document(position.id).delete { error in
            isLoading = false

            if let error = error {
                message = "Не получилось удалить позицию: \(error.localizedDescription)"
            } else {
                positions.remove(atOffsets: offsets)
                message = "Позиция удалена"
            }
        }
    }

    private func loadEmployees() {
        guard let companyId = companyId else { return }

        isLoading = true
        message = ""

        db.collection("users")
            .whereField("companyId", isEqualTo: companyId)
            .whereField("role", isEqualTo: "employee")
            .getDocuments { snapshot, error in
                isLoading = false

                if let error = error {
                    message = "Не получилось загрузить сотрудников: \(error.localizedDescription)"
                    return
                }

                let docs = snapshot?.documents ?? []

                employees = docs.map { doc in
                    let data = doc.data()

                    return CompanyEmployee(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "-",
                        email: data["email"] as? String ?? "",
                        systemRole: data["role"] as? String ?? "employee",
                        assignedPositionId: data["assignedPositionId"] as? String ?? "",
                        assignedPositionName: data["assignedPositionName"] as? String ?? ""
                    )
                }
            }
    }

    private func assignPosition(to employee: CompanyEmployee, position: WorkPosition) {
        isLoading = true
        message = ""

        db.collection("users").document(employee.id).updateData([
            "assignedPositionId": position.id,
            "assignedPositionName": position.name
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось назначить позицию: \(error.localizedDescription)"
            } else {
                if let index = employees.firstIndex(where: { $0.id == employee.id }) {
                    employees[index].assignedPositionId = position.id
                    employees[index].assignedPositionName = position.name
                }
                message = "Позиция назначена"
            }
        }
    }

    private func removeAssignedPosition(from employee: CompanyEmployee) {
        isLoading = true
        message = ""

        db.collection("users").document(employee.id).updateData([
            "assignedPositionId": FieldValue.delete(),
            "assignedPositionName": FieldValue.delete()
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Failed to remove assigned position: \(error.localizedDescription)"
            } else {
                if let index = employees.firstIndex(where: { $0.id == employee.id }) {
                    employees[index].assignedPositionId = ""
                    employees[index].assignedPositionName = ""
                }
                message = "Назначенная позиция удалена"
            }
        }
    }

    private func removeEmployeeFromCompany(_ employee: CompanyEmployee) {
        isLoading = true
        message = ""

        db.collection("users").document(employee.id).updateData([
            "companyId": FieldValue.delete(),
            "assignedPositionId": FieldValue.delete(),
            "assignedPositionName": FieldValue.delete()
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось удалить сотрудника из компании: \(error.localizedDescription)"
            } else {
                employees.removeAll { $0.id == employee.id }
                message = "Сотрудник удален из компании."
            }
        }
    }
}

struct WorkPosition: Identifiable {
    let id: String
    let companyId: String
    let name: String
}

struct CompanyEmployee: Identifiable {
    let id: String
    let name: String
    let email: String
    let systemRole: String
    var assignedPositionId: String
    var assignedPositionName: String
}

#Preview {
    ManagerCompanySetupView()
}
