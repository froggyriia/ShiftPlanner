import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ManagerGeneratedScheduleView: View {
    @State private var companyId: String? = nil
    @State private var requirements: [ShiftRequirement] = []
    @State private var employees: [CompanyEmployee] = []
    @State private var generatedShifts: [GeneratedShift] = []
    @State private var monthlyAvailabilityMap: [String: [Int: String]] = [:]

    @State private var isLoading = false
    @State private var message = ""

    @State private var showingAddShiftSheet = false
    @State private var selectedDayForNewShift: Int? = nil
    @State private var selectedDayOfWeekForNewShift = ""

    let db = Firestore.firestore()
    let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading && companyId == nil {
                    ProgressView("Загрузка...")
                } else if companyId == nil {
                    Text("Компания не найдена")
                        .foregroundColor(.gray)
                } else {
                    generatedScheduleSection
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
        .sheet(isPresented: $showingAddShiftSheet) {
            if let day = selectedDayForNewShift, let companyId = companyId {
                AddManualShiftSheet(
                    companyId: companyId,
                    day: day,
                    dayOfWeek: selectedDayOfWeekForNewShift,
                    positions: availablePositions(),
                    employees: employees,
                    onSave: { newShift in
                        generatedShifts.append(newShift)
                        generatedShifts.sort {
                            if $0.day == $1.day {
                                return minutesFromTimeString($0.startHour) < minutesFromTimeString($1.startHour)
                            }
                            return $0.day < $1.day
                        }
                        message = "Смена добавлена"
                    }
                )
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
                    message = "requirements: \(requirements.count), employees: \(employees.count)"
                    loadMonthlyAvailabilityForCurrentMonth {
                        generateScheduleForCurrentMonth()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || requirements.isEmpty || employees.isEmpty)
            }

            if generatedShifts.isEmpty {
                Text("Расписания еще нет")
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 14) {
                    ForEach(groupedGeneratedShifts()) { dayGroup in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(formattedDateTitle(day: dayGroup.day, dayOfWeek: dayGroup.dayOfWeek))
                                    .font(.headline)

                                Spacer()

                                Button("Добавить смену") {
                                    selectedDayForNewShift = dayGroup.day
                                    selectedDayOfWeekForNewShift = dayGroup.dayOfWeek
                                    showingAddShiftSheet = true
                                }
                                .buttonStyle(.bordered)
                            }

                            ForEach(dayGroup.shifts) { shift in
                                GeneratedShiftRowCard(
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
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(14)
                    }
                }
            }
        }
    }

    private func groupedGeneratedShifts() -> [GeneratedShiftDayGroup] {
        let grouped = Dictionary(grouping: generatedShifts) { shift in
            "\(shift.year)-\(shift.month)-\(shift.day)"
        }

        return grouped.map { key, shifts in
            let sortedShifts = shifts.sorted {
                minutesFromTimeString($0.startHour) < minutesFromTimeString($1.startHour)
            }

            let first = sortedShifts[0]

            return GeneratedShiftDayGroup(
                id: key,
                day: first.day,
                dayOfWeek: first.dayOfWeek,
                shifts: sortedShifts
            )
        }
        .sorted { $0.day < $1.day }
    }

    private func formattedDateTitle(day: Int, dayOfWeek: String) -> String {
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        let monthName = monthFormatter.string(from: now)

        return "\(monthName.capitalized) \(day) · \(dayOfWeek)"
    }

    private func minutesFromTimeString(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func availablePositions() -> [WorkPosition] {
        let unique = Dictionary(grouping: requirements, by: { $0.positionId })
        return unique.compactMap { _, reqs in
            guard let first = reqs.first else { return nil }
            return WorkPosition(
                id: first.positionId,
                companyId: first.companyId,
                name: first.positionName
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func loadManagerCompany() {
        guard let user = Auth.auth().currentUser else {
            message = "Пользователь не найден"
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
                    message = "Компания не найдена"
                    return
                }

                companyId = document.documentID
                isLoading = false

                loadRequirements()
                loadEmployees()
                loadGeneratedSchedule()
            }
    }

    private func loadRequirements() {
        guard let companyId = companyId else { return }

        db.collection("shift_requirements")
            .whereField("companyId", isEqualTo: companyId)
            .getDocuments { snapshot, _ in
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
            }
    }

    private func loadEmployees() {
        guard let companyId = companyId else { return }

        db.collection("users")
            .whereField("companyId", isEqualTo: companyId)
            .whereField("role", isEqualTo: "employee")
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []

                employees = docs.map { doc in
                    let data = doc.data()

                    return CompanyEmployee(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "--",
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
                    message = "Не получилось загрузить: \(error.localizedDescription)"
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
                    message = "Не получилось загрузить расписание: \(error.localizedDescription)"
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
                        status: data["status"] as? String ?? "draft"
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
            message = "Компания не найдена"
            return
        }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        guard let dayRange = calendar.range(of: .day, in: .month, for: now) else {
            message = "Ошибка при загрузке дней"
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
                    message = "Не получилось сбросить старые данные: \(error.localizedDescription)"
                    return
                }

                let batch = db.batch()
                snapshot?.documents.forEach { batch.deleteDocument($0.reference) }

                batch.commit { error in
                    if let error = error {
                        isLoading = false
                        message = "Не получилось сбросить старые данные: \(error.localizedDescription)"
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
                        status: "draft"
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
                message = "Ошибка при сохранении расписания: \(error.localizedDescription)"
            } else {
                message = "Расписание сгенерировано"
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
                message = "Не получилось переназначить смену: \(error.localizedDescription)"
            } else {
                if let index = generatedShifts.firstIndex(where: { $0.id == shift.id }) {
                    generatedShifts[index].employeeId = employee.id
                    generatedShifts[index].employeeName = employee.name
                }
                message = "Смена переназначена"
            }
        }
    }

    private func updateGeneratedShiftTime(shift: GeneratedShift, newStartHour: String, newEndHour: String) {
        guard minutesFromTimeString(newStartHour) < minutesFromTimeString(newEndHour) else {
            message = "Конечное время не может быть раньше начального"
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
                message = "Не получилось обновить время смены: \(error.localizedDescription)"
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

                message = "Время смены обновлено"
            }
        }
    }

    private func deleteGeneratedShift(_ shift: GeneratedShift) {
        isLoading = true
        message = ""

        db.collection("generated_schedule").document(shift.id).delete { error in
            isLoading = false

            if let error = error {
                message = "Не получилось удалить смену: \(error.localizedDescription)"
            } else {
                generatedShifts.removeAll { $0.id == shift.id }
                message = "Смена удалена"
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

struct AddManualShiftSheet: View {
    @Environment(\.dismiss) private var dismiss

    let companyId: String
    let day: Int
    let dayOfWeek: String
    let positions: [WorkPosition]
    let employees: [CompanyEmployee]
    let onSave: (GeneratedShift) -> Void

    @State private var selectedPositionId = ""
    @State private var selectedEmployeeId = ""
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 18, minute: 0)) ?? Date()

    @State private var isSaving = false
    @State private var message = ""

    let db = Firestore.firestore()
    let calendar = Calendar.current

    var body: some View {
        NavigationView {
            Form {
                Section("День") {
                    Text("\(day) · \(dayOfWeek)")
                }

                Section("Должность") {
                    Picker("Выберите должность", selection: $selectedPositionId) {
                        Text("Выберите должность").tag("")
                        ForEach(positions) { position in
                            Text(position.name).tag(position.id)
                        }
                    }
                }

                Section("Сотрудник") {
                    Picker("Выберите сотрудника", selection: $selectedEmployeeId) {
                        Text("Выберите сотрудника").tag("")
                        ForEach(filteredEmployees()) { employee in
                            Text(employee.name).tag(employee.id)
                        }
                    }
                }

                Section("Время") {
                    DatePicker("Начало", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Конец", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Новая смена")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveShift()
                    }
                    .disabled(
                        isSaving ||
                        selectedPositionId.isEmpty ||
                        selectedEmployeeId.isEmpty ||
                        minutesFromDate(startTime) >= minutesFromDate(endTime)
                    )
                }
            }
        }
    }

    private func filteredEmployees() -> [CompanyEmployee] {
        guard !selectedPositionId.isEmpty else { return [] }
        return employees.filter { $0.assignedPositionId == selectedPositionId }
    }

    private func selectedPositionName() -> String {
        positions.first(where: { $0.id == selectedPositionId })?.name ?? ""
    }

    private func selectedEmployeeName() -> String {
        employees.first(where: { $0.id == selectedEmployeeId })?.name ?? ""
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func saveShift() {
        let startHour = timeString(from: startTime)
        let endHour = timeString(from: endTime)

        guard minutesFromDate(startTime) < minutesFromDate(endTime) else {
            message = "Конечное время должно быть позже начального"
            return
        }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        isSaving = true
        message = ""

        let docRef = db.collection("generated_schedule").document()

        let payload: [String: Any] = [
            "companyId": companyId,
            "year": year,
            "month": month,
            "day": day,
            "dayOfWeek": dayOfWeek,
            "startHour": startHour,
            "endHour": endHour,
            "positionId": selectedPositionId,
            "positionName": selectedPositionName(),
            "employeeId": selectedEmployeeId,
            "employeeName": selectedEmployeeName(),
            "status": "manual",
            "createdAt": Timestamp()
        ]

        docRef.setData(payload) { error in
            isSaving = false

            if let error = error {
                message = "Не получилось сохранить смену: \(error.localizedDescription)"
            } else {
                let newShift = GeneratedShift(
                    id: docRef.documentID,
                    companyId: companyId,
                    year: year,
                    month: month,
                    day: day,
                    dayOfWeek: dayOfWeek,
                    startHour: startHour,
                    endHour: endHour,
                    positionId: selectedPositionId,
                    positionName: selectedPositionName(),
                    employeeId: selectedEmployeeId,
                    employeeName: selectedEmployeeName(),
                    status: "manual"
                )

                onSave(newShift)
                dismiss()
            }
        }
    }
}
