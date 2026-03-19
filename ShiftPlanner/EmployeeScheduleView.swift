import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EmployeeScheduleView: View {
    enum ScheduleScope: String, CaseIterable {
        case month = "Месяц"
        case week = "Неделя"
        case day = "День"
    }

    @State private var companyId: String = ""
    @State private var currentUserId: String = ""
    @State private var shifts: [GeneratedShift] = []

    @State private var selectedScope: ScheduleScope = .month
    @State private var showOnlyMyShifts = false
    @State private var selectedDate = Date()

    @State private var isLoading = false
    @State private var message = ""

    let db = Firestore.firestore()
    let calendar = Calendar.current

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filtersSection
                    summarySection

                    if isLoading {
                        ProgressView("Расписание загружается...")
                    } else if filteredShifts().isEmpty {
                        Text("Нет доступного расписания")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(groupedShifts()) { dayGroup in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(formattedDateTitle(day: dayGroup.day, dayOfWeek: dayGroup.dayOfWeek))
                                    .font(.headline)

                                ForEach(dayGroup.shifts) { shift in
                                    EmployeeShiftRowCard(
                                        shift: shift,
                                        isCurrentUserShift: shift.employeeId == currentUserId
                                    )
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                        }
                    }

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Мое расписание")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadCurrentUserAndSchedule()
            }
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Scope", selection: $selectedScope) {
                ForEach(ScheduleScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Мои смены", isOn: $showOnlyMyShifts)

            HStack {
                Button {
                    moveSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(scopeTitle)
                    .font(.headline)

                Spacer()

                Button {
                    moveSelection(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }

            if selectedScope == .day {
                DatePicker(
                    "Выбранный день",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }
        }
    }
    
    private var summarySection: some View {
        let myVisibleShifts = filteredShifts().filter { $0.employeeId == currentUserId }
        let totalShifts = myVisibleShifts.count
        let totalMinutes = myVisibleShifts.reduce(0) { partialResult, shift in
            partialResult + shiftDurationMinutes(shift)
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        return VStack(alignment: .leading, spacing: 12) {
            Text("Расписание")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Мои смены")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(totalShifts)")
                        .font(.title2)
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Мои часы")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(hours)h \(minutes)m")
                        .font(.title2)
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    private var scopeTitle: String {
        let formatter = DateFormatter()

        switch selectedScope {
        case .month:
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: selectedDate)

        case .day:
            formatter.dateFormat = "d MMMM yyyy"
            return formatter.string(from: selectedDate)

        case .week:
            guard let weekInterval = calendar.dateInterval(of: .weekOfMonth, for: selectedDate) else {
                return "Week"
            }

            let startFormatter = DateFormatter()
            startFormatter.dateFormat = "d MMM"

            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "d MMM"

            let startText = startFormatter.string(from: weekInterval.start)
            let endText = endFormatter.string(from: weekInterval.end.addingTimeInterval(-1))

            return "\(startText) – \(endText)"
        }
    }
    
    private func shiftDurationMinutes(_ shift: GeneratedShift) -> Int {
        let start = timeToMinutes(shift.startHour)
        let end = timeToMinutes(shift.endHour)
        return max(0, end - start)
    }

    private func moveSelection(by value: Int) {
        switch selectedScope {
        case .month:
            if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
                selectedDate = newDate
                loadSchedule()
            }

        case .week:
            if let newDate = calendar.date(byAdding: .day, value: value * 7, to: selectedDate) {
                selectedDate = newDate
                loadSchedule()
            }

        case .day:
            if let newDate = calendar.date(byAdding: .day, value: value, to: selectedDate) {
                selectedDate = newDate
                loadSchedule()
            }
        }
    }

    private func loadCurrentUserAndSchedule() {
        guard let user = Auth.auth().currentUser else {
            message = "Пользователь не найден"
            return
        }

        currentUserId = user.uid
        isLoading = true
        message = ""

        db.collection("users").document(user.uid).getDocument { snapshot, error in
            if let error = error {
                isLoading = false
                message = "Не получилось загрузить подьзователя: \(error.localizedDescription)"
                return
            }

            let data = snapshot?.data()
            companyId = data?["companyId"] as? String ?? ""

            if companyId.isEmpty {
                isLoading = false
                message = "Вы еще не присоединились к компании. Присоединитесь с помощью кода от менеджера"
                return
            }

            loadSchedule()
        }
    }

    private func loadSchedule() {
        let year = calendar.component(.year, from: selectedDate)
        let month = calendar.component(.month, from: selectedDate)

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

                shifts = docs.map { doc in
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
                        return timeToMinutes($0.startHour) < timeToMinutes($1.startHour)
                    }
                    return $0.day < $1.day
                }
            }
    }

    private func filteredShifts() -> [GeneratedShift] {
        var result = shifts

        if showOnlyMyShifts {
            result = result.filter { $0.employeeId == currentUserId }
        }

        switch selectedScope {
        case .month:
            return result

        case .day:
            let selectedDay = calendar.component(.day, from: selectedDate)
            return result.filter { $0.day == selectedDay }

        case .week:
            guard let weekInterval = calendar.dateInterval(of: .weekOfMonth, for: selectedDate) else {
                return result
            }

            return result.filter { shift in
                guard let shiftDate = calendar.date(from: DateComponents(year: shift.year, month: shift.month, day: shift.day)) else {
                    return false
                }
                return weekInterval.contains(shiftDate)
            }
        }
    }

    private func groupedShifts() -> [GeneratedShiftDayGroup] {
        let grouped = Dictionary(grouping: filteredShifts()) { shift in
            "\(shift.year)-\(shift.month)-\(shift.day)"
        }

        return grouped.map { key, shifts in
            let sortedShifts = shifts.sorted {
                timeToMinutes($0.startHour) < timeToMinutes($1.startHour)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        let monthName = formatter.string(from: selectedDate)

        return "\(monthName) \(day) · \(dayOfWeek)"
    }

    private func timeToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}

struct GeneratedShiftDayGroup: Identifiable {
    let id: String
    let day: Int
    let dayOfWeek: String
    let shifts: [GeneratedShift]
}

struct EmployeeShiftRowCard: View {
    let shift: GeneratedShift
    let isCurrentUserShift: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(shift.startHour) – \(shift.endHour)")
                    .font(.headline)

                Spacer()

                if isCurrentUserShift {
                    Text("MY SHIFT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.18))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }

            Text(shift.positionName)
                .font(.subheadline)

            Text(shift.employeeName)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrentUserShift ? Color.green.opacity(0.22) : Color(.systemGray5))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrentUserShift ? Color.green.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }
}
