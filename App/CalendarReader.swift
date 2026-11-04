import SwiftUI
import EventKit
@MainActor final class CalendarReader:ObservableObject {
    @Published var events:[EKEvent]=[]
    @Published var message=""
    private let store=EKEventStore()
    func request() async {
        do { if try await store.requestFullAccessToEvents(){refresh()} else{message="Calendar access is off. You can type a task."} }
        catch{message="Calendar is unavailable. You can type a task."}
    }
    func refresh(){
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else{return}
        let start=Calendar.current.startOfDay(for:Date()),end=Calendar.current.date(byAdding:.day,value:1,to:start)!
        events=store.events(matching:store.predicateForEvents(withStart:start,end:end,calendars:nil)).filter{$0.status != .canceled}.sorted{$0.startDate<$1.startDate}
    }
}
