import SwiftUI

struct GeneratedShiftRowCard: View {
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
        _editedStartTime = State(initialValue: GeneratedShiftRowCard.dateFromTimeString(shift.startHour))
        _editedEndTime = State(initialValue: GeneratedShiftRowCard.dateFromTimeString(shift.endHour))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(shift.startHour) – \(shift.endHour)")
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
                Text("Изменить время")
                    .font(.subheadline)
                    .bold()

                DatePicker(
                    "Начало",
                    selection: $editedStartTime,
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    "Конец",
                    selection: $editedEndTime,
                    displayedComponents: .hourAndMinute
                )

                Button("Сохранить") {
                    onUpdateTime(
                        GeneratedShiftRowCard.timeString(from: editedStartTime),
                        GeneratedShiftRowCard.timeString(from: editedEndTime)
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    GeneratedShiftRowCard.minutes(from: editedStartTime) >=
                    GeneratedShiftRowCard.minutes(from: editedEndTime)
                )
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("Удалить")
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
