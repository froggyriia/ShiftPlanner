import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManagerRequirementsView: View {
    @State private var companyId: String? = nil
    @State private var positions: [WorkPosition] = []
    @State private var requirements: [ShiftRequirement] = []

    @State private var selectedDays: Set<String> = []
    @State private var startTime = Self.makeTime(hour: 7, minute: 0)
    @State private var endTime = Self.makeTime(hour: 11, minute: 0)
    @State private var selectedPositionId = ""
    @State private var selectedPositionName = ""
    @State private var requiredCount = 1

    @State private var isLoading = false
    @State private var message = ""

    let db = Firestore.firestore()
    let calendar = Calendar.current

    let days = [
        "Понедельник", "Вторник", "Среда",
        "Четверг", "Пятница", "Суббота", "Воскресенье"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading && companyId == nil {
                    ProgressView("Загрузка...")
                } else if companyId == nil {
                    Text("Компания не найдена.")
                        .foregroundColor(.gray)
                } else {
                    createRequirementSection
                    Divider()
                    requirementsSection
                }

                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            loadManagerCompany()
        }
    }

    private var createRequirementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Добавить правило для смен")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Выберите дни")
                    .font(.subheadline)
                    .bold()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        Button {
                            toggleDay(day)
                        } label: {
                            Text(shortDayName(day))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedDays.contains(day) ? Color.blue : Color(.systemGray5))
                                .foregroundColor(selectedDays.contains(day) ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }

                HStack {
                    Button("Будни") {
                        selectedDays = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница"]
                    }

                    Button("Выходные") {
                        selectedDays = ["Суббота", "Воскресенье"]
                    }

                    Button("Все") {
                        selectedDays = Set(days)
                    }

                    Button("Очистить") {
                        selectedDays.removeAll()
                    }
                }
                .buttonStyle(.bordered)
            }

            DatePicker(
                "Время начала",
                selection: $startTime,
                displayedComponents: .hourAndMinute
            )

            DatePicker(
                "Время окончания",
                selection: $endTime,
                displayedComponents: .hourAndMinute
            )

            Picker("Должность", selection: $selectedPositionId) {
                Text("Выберите должность").tag("")
                ForEach(positions) { position in
                    Text(position.name).tag(position.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPositionId) { newValue in
                if let position = positions.first(where: { $0.id == newValue }) {
                    selectedPositionName = position.name
                }
            }

            Stepper("Нужно сотрудников: \(requiredCount)", value: $requiredCount, in: 1...20)

            Button("Добавить правило") {
                addRequirement()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isLoading ||
                selectedDays.isEmpty ||
                selectedPositionId.isEmpty ||
                minutesFromDate(startTime) >= minutesFromDate(endTime)
            )
        }
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Текущие правила")
                    .font(.headline)

                Spacer()

                Button("Обновить") {
                    loadRequirements()
                }
                .disabled(isLoading)
            }

            if requirements.isEmpty {
                Text("Правила ещё не добавлены.")
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 10) {
                    ForEach(requirements) { requirement in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(requirement.dayOfWeek)
                                    .font(.headline)

                                Text("\(requirement.startHour) – \(requirement.endHour)")
                                    .font(.subheadline)

                                Text("\(requirement.positionName) · \(requirement.requiredCount) сотрудник(а)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                deleteRequirement(requirement)
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
    }

    private func toggleDay(_ day: String) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func shortDayName(_ day: String) -> String {
        switch day {
        case "Понедельник": return "Пн"
        case "Вторник": return "Вт"
        case "Среда": return "Ср"
        case "Четверг": return "Чт"
        case "Пятница": return "Пт"
        case "Суббота": return "Сб"
        case "Воскресенье": return "Вс"
        default: return day
        }
    }

    private static func makeTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func minutesFromTimeString(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func loadManagerCompany() {
        guard let user = Auth.auth().currentUser else {
            message = "Не удалось найти текущего пользователя."
            return
        }

        isLoading = true
        message = ""

        db.collection("companies")
            .whereField("ownerId", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error = error {
                    isLoading = false
                    message = "Не удалось загрузить данные компании: \(error.localizedDescription)"
                    return
                }

                guard let document = snapshot?.documents.first else {
                    isLoading = false
                    message = "Компания не найдена."
                    return
                }

                companyId = document.documentID
                isLoading = false

                loadPositions()
                loadRequirements()
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
                    message = "Не удалось загрузить должности: \(error.localizedDescription)"
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

    private func loadRequirements() {
        guard let companyId = companyId else { return }

        isLoading = true
        message = ""

        db.collection("shift_requirements")
            .whereField("companyId", isEqualTo: companyId)
            .getDocuments { snapshot, error in
                isLoading = false

                if let error = error {
                    message = "Не удалось загрузить правила: \(error.localizedDescription)"
                    return
                }

                let docs = snapshot?.documents ?? []

                requirements = docs.map { doc in
                    let data = doc.data()
                    return ShiftRequirement(
                        id: doc.documentID,
                        companyId: data["companyId"] as? String ?? "",
                        dayOfWeek: data["dayOfWeek"] as? String ?? "",
                        startHour: data["startHour"] as? String ?? "",
                        endHour: data["endHour"] as? String ?? "",
                        positionId: data["positionId"] as? String ?? "",
                        positionName: data["positionName"] as? String ?? "",
                        requiredCount: data["requiredCount"] as? Int ?? 1
                    )
                }
                .sorted {
                    if $0.dayOfWeek == $1.dayOfWeek {
                        return minutesFromTimeString($0.startHour) < minutesFromTimeString($1.startHour)
                    }
                    return (days.firstIndex(of: $0.dayOfWeek) ?? 0) < (days.firstIndex(of: $1.dayOfWeek) ?? 0)
                }
            }
    }

    private func addRequirement() {
        guard let companyId = companyId else {
            message = "Компания не найдена."
            return
        }

        guard let selectedPosition = positions.first(where: { $0.id == selectedPositionId }) else {
            message = "Пожалуйста, выберите должность."
            return
        }

        guard !selectedDays.isEmpty else {
            message = "Пожалуйста, выберите хотя бы один день."
            return
        }

        let startHour = timeString(from: startTime)
        let endHour = timeString(from: endTime)

        guard minutesFromTimeString(startHour) < minutesFromTimeString(endHour) else {
            message = "Время окончания должно быть позже времени начала."
            return
        }

        isLoading = true
        message = ""

        let batch = db.batch()

        for day in selectedDays {
            let docRef = db.collection("shift_requirements").document()

            let requirementData: [String: Any] = [
                "companyId": companyId,
                "dayOfWeek": day,
                "startHour": startHour,
                "endHour": endHour,
                "positionId": selectedPosition.id,
                "positionName": selectedPosition.name,
                "requiredCount": requiredCount,
                "createdAt": Timestamp()
            ]

            batch.setData(requirementData, forDocument: docRef)
        }

        batch.commit { error in
            isLoading = false

            if let error = error {
                message = "Не удалось добавить правила: \(error.localizedDescription)"
            } else {
                message = "Правила успешно добавлены."

                selectedDays.removeAll()
                selectedPositionId = ""
                selectedPositionName = ""
                requiredCount = 1
                startTime = Self.makeTime(hour: 7, minute: 0)
                endTime = Self.makeTime(hour: 11, minute: 0)

                loadRequirements()
            }
        }
    }

    private func deleteRequirement(_ requirement: ShiftRequirement) {
        isLoading = true
        message = ""

        db.collection("shift_requirements").document(requirement.id).delete { error in
            isLoading = false

            if let error = error {
                message = "Не удалось удалить правило: \(error.localizedDescription)"
            } else {
                requirements.removeAll { $0.id == requirement.id }
                message = "Правило удалено."
            }
        }
    }
}
