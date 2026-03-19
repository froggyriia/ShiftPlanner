import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManagerScheduleView: View {
    @State private var companyId: String? = nil
    @State private var positions: [WorkPosition] = []
    @State private var requirements: [ShiftRequirement] = []
    @State private var employees: [CompanyEmployee] = []
    @State private var generatedShifts: [GeneratedShift] = []
    @State private var monthlyAvailabilityMap: [String: [Int: String]] = [:]

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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Настройка расписания")
                        .font(.largeTitle)
                        .bold()

                    if isLoading && companyId == nil {
                        ProgressView("Загрузка...")
                    } else if companyId == nil {
                        Text("Компания не найдена.")
                            .foregroundColor(.gray)
                    } else {
                        createRequirementSection
                        Divider()
                        requirementsSection
                        Divider()
                        generatedScheduleSection
                    }

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
            }
            .onAppear {
                loadManagerCompany()
            }
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

    private var generatedScheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Сгенерированное расписание")
                    .font(.headline)

                Spacer()

                Button("Сгенерировать") {
                    loadMonthlyAvailabilityForCurrentMonth {
                        generateScheduleForCurrentMonth()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || requirements.isEmpty || employees.isEmpty)
            }

            if generatedShifts.isEmpty {
                Text("Сгенерированного расписания пока нет.")
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 10) {
                    ForEach(generatedShifts) { shift in
                        GeneratedShiftCard(
                            shift: shift,
                            eligibleEmployees: eligibleEmployees(for: shift),
                            onReassign: { newEmployeeId in
                                if let employee = employees.first(where: { $0.id == newEmployeeId }) {
                                    reassignShift(shift: shift, to: employee)
                                }
                            },
                            onUpdateTime: { newStart, newEnd in
                                updateGeneratedShiftTime(
                                    shift: shift,
                                    newStartHour: newStart,
                                    newEndHour: newEnd
                                )
                            },
                            onDelete: {
                                deleteGeneratedShift(shift)
                            }
                        )
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
                loadEmployees()
                loadGeneratedSchedule()
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
                    message = "Не удалось загрузить сотрудников: \(error.localizedDescription)"
                    return
                }

                let docs = snapshot?.documents ?? []

                employees = docs.map { doc in
                    let data = doc.data()

                    return CompanyEmployee(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Неизвестно",
                        email: data["email"] as? String ?? "",
                        systemRole: data["role"] as? String ?? "сотрудник",
                        assignedPositionId: data["assignedPositionId"] as? String ?? "",
                        assignedPositionName: data["assignedPositionName"] as? String ?? ""
                    )
                }
            }
    }

    private func loadMonthlyAvailabilityForCurrentMonth(completion: @escaping () -> Void) {
        guard let companyId = companyId else {
            completion()
            return
        }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        db.collection("monthly_availability")
            .whereField("companyId", isEqualTo: companyId)
            .whereField("year", isEqualTo: year)
            .whereField("month", isEqualTo: month)
            .getDocuments { snapshot, error in
                if let error = error {
                    message = "Не удалось загрузить доступность сотрудников: \(error.localizedDescription)"
                    completion()
                    return
                }

                var result: [String: [Int: String]] = [:]

                for doc in snapshot?.documents ?? [] {
                    let data = doc.data()
                    let userId = data["userId"] as? String ?? ""
                    let rawDays = data["days"] as? [String: String] ?? [:]

                    var parsed: [Int: String] = [:]
                    for (key, value) in rawDays {
                        if let day = Int(key) {
                            parsed[day] = value
                        }
                    }

                    result[userId] = parsed
                }

                monthlyAvailabilityMap = result
                completion()
            }
    }

    private func availabilityStatusForEmployee(employeeId: String, day: Int) -> String {
        let employeeDays = monthlyAvailabilityMap[employeeId] ?? [:]
        return employeeDays[day] ?? "available"
    }

    private func loadGeneratedSchedule() {
        guard let companyId = companyId else { return }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        isLoading = true
        message = ""

        db.collection("generated_schedule")
            .whereField("companyId", isEqualTo: companyId)
            .whereField("year", isEqualTo: year)
            .whereField("month", isEqualTo: month)
            .getDocuments { snapshot, error in
                isLoading = false

                if let error = error {
                    message = "Не удалось загрузить сгенерированное расписание: \(error.localizedDescription)"
                    return
                }

                let docs = snapshot?.documents ?? []

                generatedShifts = docs.map { doc in
                    let data = doc.data()
                    return GeneratedShift(
                        id: doc.documentID,
                        companyId: data["companyId"] as? String ?? "",
                        year: data["year"] as? Int ?? year,
                        month: data["month"] as? Int ?? month,
                        day: data["day"] as? Int ?? 1,
                        dayOfWeek: data["dayOfWeek"] as? String ?? "",
                        startHour: data["startHour"] as? String ?? "",
                        endHour: data["endHour"] as? String ?? "",
                        positionId: data["positionId"] as? String ?? "",
                        positionName: data["positionName"] as? String ?? "",
                        employeeId: data["employeeId"] as? String ?? "",
                        employeeName: data["employeeName"] as? String ?? "",
                        status: data["status"] as? String ?? "черновик"
                    )
                }
                .sorted {
                    if $0.day == $1.day {
                        return minutesFromTimeString($0.startHour) < minutesFromTimeString($1.startHour)
                    }
                    return $0.day < $1.day
                }
            }
    }

    private func generateScheduleForCurrentMonth() {
        guard let companyId = companyId else {
            message = "Компания не найдена."
            return
        }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        guard let dayRange = calendar.range(of: .day, in: .month, for: now) else {
            message = "Не удалось определить дни месяца."
            return
        }

        isLoading = true
        message = ""

        db.collection("generated_schedule")
            .whereField("companyId", isEqualTo: companyId)
            .whereField("year", isEqualTo: year)
            .whereField("month", isEqualTo: month)
            .getDocuments { snapshot, error in
                if let error = error {
                    isLoading = false
                    message = "Не удалось очистить старое расписание: \(error.localizedDescription)"
                    return
                }

                let batch = db.batch()
                snapshot?.documents.forEach { batch.deleteDocument($0.reference) }

                batch.commit { error in
                    if let error = error {
                        isLoading = false
                        message = "Не удалось очистить старое расписание: \(error.localizedDescription)"
                        return
                    }

                    generateFreshSchedule(companyId: companyId, year: year, month: month, dayRange: dayRange)
                }
            }
    }

    private func generateFreshSchedule(companyId: String, year: Int, month: Int, dayRange: Range<Int>) {
        var employeeShiftCounts: [String: Int] = [:]
        var assignedPerDay: [String: [(start: String, end: String, employeeId: String)]] = [:]
        var newShifts: [GeneratedShift] = []

        for day in dayRange {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }

            let weekdayIndex = calendar.component(.weekday, from: date)
            let dayOfWeek = weekdayName(from: weekdayIndex)

            let dayRequirements = requirements.filter { $0.dayOfWeek == dayOfWeek }

            for requirement in dayRequirements {
                let matchingEmployees = employees.filter {
                    $0.assignedPositionId == requirement.positionId
                }

                let availableEmployees = matchingEmployees
                    .filter { availabilityStatusForEmployee(employeeId: $0.id, day: day) == "available" }
                    .sorted { (employeeShiftCounts[$0.id] ?? 0) < (employeeShiftCounts[$1.id] ?? 0) }

                let ifNeededEmployees = matchingEmployees
                    .filter { availabilityStatusForEmployee(employeeId: $0.id, day: day) == "ifNeeded" }
                    .sorted { (employeeShiftCounts[$0.id] ?? 0) < (employeeShiftCounts[$1.id] ?? 0) }

                let rankedEmployees = availableEmployees + ifNeededEmployees

                var assignedCount = 0

                for employee in rankedEmployees {
                    if assignedCount >= requirement.requiredCount { break }

                    let dayKey = "\(day)"
                    let currentAssignments = assignedPerDay[dayKey] ?? []

                    let hasConflict = currentAssignments.contains {
                        $0.employeeId == employee.id &&
                        timeRangesOverlap(
                            start1: $0.start,
                            end1: $0.end,
                            start2: requirement.startHour,
                            end2: requirement.endHour
                        )
                    }

                    if hasConflict {
                        continue
                    }

                    let shift = GeneratedShift(
                        id: UUID().uuidString,
                        companyId: companyId,
                        year: year,
                        month: month,
                        day: day,
                        dayOfWeek: dayOfWeek,
                        startHour: requirement.startHour,
                        endHour: requirement.endHour,
                        positionId: requirement.positionId,
                        positionName: requirement.positionName,
                        employeeId: employee.id,
                        employeeName: employee.name,
                        status: "черновик"
                    )

                    newShifts.append(shift)
                    assignedCount += 1
                    employeeShiftCounts[employee.id, default: 0] += 1
                    assignedPerDay[dayKey, default: []].append(
                        (start: requirement.startHour, end: requirement.endHour, employeeId: employee.id)
                    )
                }
            }
        }

        saveGeneratedShifts(newShifts)
    }

    private func saveGeneratedShifts(_ shifts: [GeneratedShift]) {
        let batch = db.batch()

        for shift in shifts {
            let ref = db.collection("generated_schedule").document()
            batch.setData([
                "companyId": shift.companyId,
                "year": shift.year,
                "month": shift.month,
                "day": shift.day,
                "dayOfWeek": shift.dayOfWeek,
                "startHour": shift.startHour,
                "endHour": shift.endHour,
                "positionId": shift.positionId,
                "positionName": shift.positionName,
                "employeeId": shift.employeeId,
                "employeeName": shift.employeeName,
                "status": shift.status,
                "createdAt": Timestamp()
            ], forDocument: ref)
        }

        batch.commit { error in
            isLoading = false

            if let error = error {
                message = "Не удалось сохранить сгенерированное расписание: \(error.localizedDescription)"
            } else {
                message = "Расписание успешно сгенерировано."
                loadGeneratedSchedule()
            }
        }
    }

    private func eligibleEmployees(for shift: GeneratedShift) -> [CompanyEmployee] {
        employees.filter { $0.assignedPositionId == shift.positionId }
    }

    private func reassignShift(shift: GeneratedShift, to employee: CompanyEmployee) {
        isLoading = true
        message = ""

        db.collection("generated_schedule").document(shift.id).updateData([
            "employeeId": employee.id,
            "employeeName": employee.name
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не удалось переназначить смену: \(error.localizedDescription)"
            } else {
                if let index = generatedShifts.firstIndex(where: { $0.id == shift.id }) {
                    generatedShifts[index].employeeId = employee.id
                    generatedShifts[index].employeeName = employee.name
                }
                message = "Смена переназначена."
            }
        }
    }

    private func updateGeneratedShiftTime(shift: GeneratedShift, newStartHour: String, newEndHour: String) {
        guard minutesFromTimeString(newStartHour) < minutesFromTimeString(newEndHour) else {
            message = "Время окончания должно быть позже времени начала."
            return
        }

        isLoading = true
        message = ""

        db.collection("generated_schedule").document(shift.id).updateData([
            "startHour": newStartHour,
            "endHour": newEndHour
        ]) { error in
            isLoading = false

            if let error = error {
                message = "Не удалось обновить время смены: \(error.localizedDescription)"
            } else {
                if let index = generatedShifts.firstIndex(where: { $0.id == shift.id }) {
                    generatedShifts[index] = GeneratedShift(
                        id: generatedShifts[index].id,
                        companyId: generatedShifts[index].companyId,
                        year: generatedShifts[index].year,
                        month: generatedShifts[index].month,
                        day: generatedShifts[index].day,
                        dayOfWeek: generatedShifts[index].dayOfWeek,
                        startHour: newStartHour,
                        endHour: newEndHour,
                        positionId: generatedShifts[index].positionId,
                        positionName: generatedShifts[index].positionName,
                        employeeId: generatedShifts[index].employeeId,
                        employeeName: generatedShifts[index].employeeName,
                        status: generatedShifts[index].status
                    )
                }

                generatedShifts.sort {
                    if $0.day == $1.day {
                        return minutesFromTimeString($0.startHour) < minutesFromTimeString($1.startHour)
                    }
                    return $0.day < $1.day
                }

                message = "Время смены обновлено."
            }
        }
    }

    private func deleteGeneratedShift(_ shift: GeneratedShift) {
        isLoading = true
        message = ""

        db.collection("generated_schedule").document(shift.id).delete { error in
            isLoading = false

            if let error = error {
                message = "Не удалось удалить смену: \(error.localizedDescription)"
            } else {
                generatedShifts.removeAll { $0.id == shift.id }
                message = "Смена удалена."
            }
        }
    }

    private func weekdayName(from weekdayIndex: Int) -> String {
        switch weekdayIndex {
        case 2: return "Понедельник"
        case 3: return "Вторник"
        case 4: return "Среда"
        case 5: return "Четверг"
        case 6: return "Пятница"
        case 7: return "Суббота"
        case 1: return "Воскресенье"
        default: return ""
        }
    }

    private func timeRangesOverlap(start1: String, end1: String, start2: String, end2: String) -> Bool {
        let s1 = minutesFromTimeString(start1)
        let e1 = minutesFromTimeString(end1)
        let s2 = minutesFromTimeString(start2)
        let e2 = minutesFromTimeString(end2)

        return max(s1, s2) < min(e1, e2)
    }
}

struct ShiftRequirement: Identifiable {
    let id: String
    let companyId: String
    let dayOfWeek: String
    let startHour: String
    let endHour: String
    let positionId: String
    let positionName: String
    let requiredCount: Int
}

struct GeneratedShift: Identifiable {
    let id: String
    let companyId: String
    let year: Int
    let month: Int
    let day: Int
    let dayOfWeek: String
    let startHour: String
    let endHour: String
    let positionId: String
    let positionName: String
    var employeeId: String
    var employeeName: String
    let status: String
}

struct GeneratedShiftCard: View {
    let shift: GeneratedShift
    let eligibleEmployees: [CompanyEmployee]

    let onReassign: (String) -> Void
    let onUpdateTime: (String, String) -> Void
    let onDelete: () -> Void

    @State private var selectedEmployeeId: String
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date

    init(
        shift: GeneratedShift,
        eligibleEmployees: [CompanyEmployee],
        onReassign: @escaping (String) -> Void,
        onUpdateTime: @escaping (String, String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.shift = shift
        self.eligibleEmployees = eligibleEmployees
        self.onReassign = onReassign
        self.onUpdateTime = onUpdateTime
        self.onDelete = onDelete

        _selectedEmployeeId = State(initialValue: shift.employeeId)
        _editedStartTime = State(initialValue: GeneratedShiftCard.dateFromTimeString(shift.startHour))
        _editedEndTime = State(initialValue: GeneratedShiftCard.dateFromTimeString(shift.endHour))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("День \(shift.day) · \(shift.dayOfWeek)")
                .font(.headline)

            Text(shift.positionName)
                .font(.subheadline)

            Text("Назначен: \(shift.employeeName)")
                .font(.subheadline)
                .foregroundColor(.gray)

            Picker("Переназначить сотрудника", selection: $selectedEmployeeId) {
                ForEach(eligibleEmployees) { employee in
                    Text(employee.name).tag(employee.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedEmployeeId) { newValue in
                onReassign(newValue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Время смены")
                    .font(.subheadline)
                    .bold()

                DatePicker(
                    "Начало",
                    selection: $editedStartTime,
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    "Окончание",
                    selection: $editedEndTime,
                    displayedComponents: .hourAndMinute
                )

                Button("Сохранить время") {
                    onUpdateTime(
                        GeneratedShiftCard.timeString(from: editedStartTime),
                        GeneratedShiftCard.timeString(from: editedEndTime)
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    GeneratedShiftCard.minutes(from: editedStartTime) >=
                    GeneratedShiftCard.minutes(from: editedEndTime)
                )
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("Удалить назначение")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private static func dateFromTimeString(_ time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.count > 0 ? parts[0] : 0
        let minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }
}

#Preview {
    ManagerScheduleView()
}
