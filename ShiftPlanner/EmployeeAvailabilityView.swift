import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CalendarDayItem: Identifiable {
    let id = UUID()
    let day: Int?
}

struct EmployeeAvailabilityView: View {
    @State private var companyId: String = ""
    @State private var currentDate = Date()

    @State private var desiredMonthlyHours = ""
    @State private var desiredMonthlyShifts = ""

    @State private var dayStatuses: [Int: AvailabilityStatus] = [:]

    @State private var isLoading = false
    @State private var message = ""

    let db = Firestore.firestore()
    private let calendar = Calendar.current

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthHeader
                    preferenceSection
                    legendSection
                    calendarGridSection

                    Button("Сохранить") {
                        saveAvailability()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || companyId.isEmpty)

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Когда доступен")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadCurrentUserCompanyAndAvailability()
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(monthTitle)
                .font(.title2)
                .bold()

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Предпочтения на месяц")
                .font(.headline)

            TextField("Желаемое количество часов в месяц", text: $desiredMonthlyHours)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            TextField("Желаемое количество смен в месяц", text: $desiredMonthlyShifts)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var legendSection: some View {
        HStack(spacing: 12) {
            legendItem(color: .green, text: "Могу")
            legendItem(color: .yellow, text: "По возможности")
            legendItem(color: .red, text: "не могу")
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)

            Text(text)
                .font(.caption)
        }
    }

    private var calendarGridSection: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Нажмите на день, чтобы изменить")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(weekDaySymbols(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .bold()
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { item in
                    dayCell(for: item.day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for day: Int?) -> some View {
        if let day = day {
            let status = dayStatuses[day] ?? .available

            Button {
                dayStatuses[day] = status.next()
            } label: {
                Text("\(day)")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(status.color.opacity(0.85))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            Color.clear
                .frame(height: 42)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: currentDate)
    }

    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentDate) {
            currentDate = newDate
            loadAvailability()
        }
    }

    private func weekDaySymbols() -> [String] {
        ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    }

    private func daysInMonth() -> [CalendarDayItem] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
            let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday,
            let range = calendar.range(of: .day, in: .month, for: currentDate)
        else {
            return []
        }

        let adjustedFirstWeekday = (firstWeekday + 5) % 7

        var result: [CalendarDayItem] = []

        for _ in 0..<adjustedFirstWeekday {
            result.append(CalendarDayItem(day: nil))
        }

        for day in range {
            result.append(CalendarDayItem(day: day))
        }

        return result
    }

    private func loadCurrentUserCompanyAndAvailability() {
        guard let user = Auth.auth().currentUser else {
            message = "Пользователь не найден"
            return
        }

        isLoading = true
        message = ""

        db.collection("users").document(user.uid).getDocument { snapshot, error in
            isLoading = false

            if let error = error {
                message = "Не получилось загрузить данные пользователя: \(error.localizedDescription)"
                return
            }

            let data = snapshot?.data()
            companyId = data?["companyId"] as? String ?? ""

            if companyId.isEmpty {
                message = "Вы еще не присоединились к компании. Присоединитесь с помощью кода от менеджера"
            } else {
                loadAvailability()
            }
        }
    }

    private func loadAvailability() {
        guard let user = Auth.auth().currentUser else { return }
        guard !companyId.isEmpty else { return }

        isLoading = true
        message = ""

        let year = calendar.component(.year, from: currentDate)
        let month = calendar.component(.month, from: currentDate)

        db.collection("monthly_availability")
            .whereField("userId", isEqualTo: user.uid)
            .whereField("year", isEqualTo: year)
            .whereField("month", isEqualTo: month)
            .getDocuments { snapshot, error in
                isLoading = false

                if let error = error {
                    message = "Не получилось загрузить: \(error.localizedDescription)"
                    return
                }

                guard let document = snapshot?.documents.first else {
                    desiredMonthlyHours = ""
                    desiredMonthlyShifts = ""
                    dayStatuses = defaultDayStatuses()
                    return
                }

                let data = document.data()
                let savedHours = data["desiredMonthlyHours"] as? Int ?? 0
                let savedShifts = data["desiredMonthlyShifts"] as? Int ?? 0

                desiredMonthlyHours = savedHours == 0 ? "" : String(savedHours)
                desiredMonthlyShifts = savedShifts == 0 ? "" : String(savedShifts)

                let rawDays = data["days"] as? [String: String] ?? [:]
                var parsedStatuses: [Int: AvailabilityStatus] = defaultDayStatuses()

                for (key, value) in rawDays {
                    if let day = Int(key), let status = AvailabilityStatus(rawValue: value) {
                        parsedStatuses[day] = status
                    }
                }

                dayStatuses = parsedStatuses
            }
    }

    private func defaultDayStatuses() -> [Int: AvailabilityStatus] {
        guard let range = calendar.range(of: .day, in: .month, for: currentDate) else {
            return [:]
        }

        var result: [Int: AvailabilityStatus] = [:]
        for day in range {
            result[day] = .available
        }
        return result
    }

    private func saveAvailability() {
        guard let user = Auth.auth().currentUser else {
            message = "No logged in user found."
            return
        }

        guard !companyId.isEmpty else {
            message = "Сначала присоединитесь к компании с помощью кода от менеджера"
            return
        }

        let year = calendar.component(.year, from: currentDate)
        let month = calendar.component(.month, from: currentDate)

        let hours = Int(desiredMonthlyHours) ?? 0
        let shifts = Int(desiredMonthlyShifts) ?? 0

        var daysPayload: [String: String] = [:]
        for (day, status) in dayStatuses {
            daysPayload[String(day)] = status.rawValue
        }

        isLoading = true
        message = ""

        let data: [String: Any] = [
            "userId": user.uid,
            "companyId": companyId,
            "year": year,
            "month": month,
            "desiredMonthlyHours": hours,
            "desiredMonthlyShifts": shifts,
            "days": daysPayload,
            "updatedAt": Timestamp()
        ]

        let documentId = "\(user.uid)_\(year)_\(month)"

        db.collection("monthly_availability").document(documentId).setData(data) { error in
            isLoading = false

            if let error = error {
                message = "Не получилось сохранить: \(error.localizedDescription)"
            } else {
                message = "Успешно сохранено"
            }
        }
    }
}

#Preview {
    EmployeeAvailabilityView()
}
