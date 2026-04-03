import Foundation

func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
}

func endOfDay(_ date: Date) -> Date {
    let start = startOfDay(date)
    return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
}
