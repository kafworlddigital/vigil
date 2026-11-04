import SwiftUI
struct FocusSummary: View {
    let session: FocusSession
    private struct Inspection: Identifiable { let id: String }
    @State private var inspection: Inspection?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.task).font(.fredoka(22))
            if session.usedDeveloperMode == true {
                Text("Developer test · \(FocusSession.clock(session.realActiveElapsed)) real active time · timeline uses focus-clock time")
                    .font(.plexMono(11)).foregroundStyle(.secondary)
            }
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(FocusSession.clock(session.elapsed)) active")
                .font(.plexMono(11)).foregroundStyle(.secondary)
            Button { inspect("all") } label: {
                FocusTimeline(session: session).frame(height: 40)
            }.buttonStyle(.plain).accessibilityLabel("Inspect focus checks")
            HStack(spacing: 16) {
                legend("On task", .green, category: "on_task")
                legend("Off task", Color(hex: 0xEBAC73), category: "off_task")
                legend("Unknown", .gray, category: "uncertain")
            }.font(.plexSans(11))
            Text("Tap a category to see probabilities and confidence. Grey also includes unchecked time. Pauses are excluded.")
                .font(.plexSans(11)).foregroundStyle(.secondary)
        }
        .sheet(item: $inspection) { selection in FocusCheckList(session: session, category: selection.id) }
    }
    private func inspect(_ category: String) {
        inspection = Inspection(id: category)
    }
    private func legend(_ name: String, _ color: Color, category: String) -> some View {
        Button { inspect(category) } label: {
            HStack(spacing: 5) { Rectangle().fill(color).frame(width: 9, height: 9); Text(name) }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Inspect \(name) confidence")
    }
}

private struct FocusCheckList: View {
    let session: FocusSession
    @State var category: String
    @Environment(\.dismiss) private var dismiss
    private var checks: [FocusCheck] {
        session.checks.reversed().filter {
            if $0.activity == .paused { return false }
            if category == "all" { return true }
            if category == "uncertain" { return [.uncertain, .unavailable, .privateSkipped].contains($0.activity) }
            return $0.activity.rawValue == category
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show checks", selection: $category) {
                        Text("All").tag("all")
                        Text("On task").tag("on_task")
                        Text("Off task").tag("off_task")
                        Text("Unknown").tag("uncertain")
                    }.pickerStyle(.segmented)
                    Text("Each check is a periodic observation. Developer Mode checks every 10 real seconds with a 4× clock. Category probabilities and overall decision confidence are separate model estimates, not guarantees.")
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                }
                Section("Latest checks first") {
                    if checks.isEmpty {
                        Text("No checks recorded in this category yet. Unchecked time has no confidence estimate.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(checks) { check in
                        NavigationLink {
                            FocusCheckDetail(check: check)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(check.activity.focusName).font(.fredoka(20))
                                    Spacer()
                                    Text(FocusSession.clock(check.elapsed)).font(.plexMono(12))
                                }
                                if let estimate = check.estimate(for: check.activity) {
                                    Text("Category probability \(estimate.focusPercent) · confidence \(check.confidence.focusPercent)")
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                } else if [.unavailable,.privateSkipped].contains(check.activity) {
                                    Text("Check unavailable or stale · no valid estimate")
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                } else {
                                    Text("Category probability not saved · confidence \(check.confidence.focusPercent)")
                                        .font(.plexSans(12)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.navigationTitle("Focus checks")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private struct FocusCheckDetail: View {
    let check: FocusCheck
    var body: some View {
        List {
            Section {
                LabeledContent("Observation", value: check.activity.focusName)
                LabeledContent("Active session time", value: FocusSession.clock(check.elapsed))
            }
            if [.unavailable,.privateSkipped].contains(check.activity) {
                Text("This check failed or arrived too late. It has no valid confidence estimate and does not count toward a nudge.")
            } else {
                Section("Category probabilities") {
                    ForEach([FocusActivity.onTask, .offTask, .uncertain], id: \.rawValue) { category in
                        LabeledContent(category.focusName, value: check.estimate(for: category)?.focusPercent ?? "Not saved")
                    }
                }
                Section("Decision confidence") {
                    LabeledContent("Overall confidence", value: check.confidence.focusPercent)
                    Text("Confidence is reported separately by the API. It is not the probability of a particular category.")
                        .font(.plexSans(13)).foregroundStyle(.secondary)
                }
                if check.probabilities == nil {
                    Text("This older check saved only the Off task probability and overall confidence. The other probabilities weren't saved.")
                        .foregroundStyle(.secondary)
                }
                if check.nudged { Label("Vigil gave a gentle nudge after this check", systemImage: "bubble.left") }
            }
        }.navigationTitle("Check details")
    }
}

private extension FocusActivity {
    var focusName: String {
        switch self {
        case .onTask: return "On task"
        case .offTask: return "Off task"
        case .uncertain: return "Unknown"
        case .unavailable: return "Unavailable"
        case .paused: return "Paused"
        case .privateSkipped: return "Private (skipped)"
        }
    }
}

private extension Double {
    var focusPercent: String { formatted(.percent.precision(.fractionLength(0...1))) }
}

struct FocusTimeline: View {
    let session: FocusSession
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray.opacity(0.35)))
            let total = max(1, session.status == .ended ? session.elapsed : session.duration)
            for check in session.checks where [.onTask, .offTask].contains(check.activity) {
                let span = check.sampleDuration ?? 30
                let start = max(0, check.elapsed - span)
                let rect = CGRect(x: start / total * size.width, y: 0,
                                  width: min(span, check.elapsed) / total * size.width, height: size.height)
                context.fill(Path(rect), with: .color(check.activity == .onTask ? .green : Color(hex: 0xEBAC73)))
            }
        }.overlay(Rectangle().stroke(.white.opacity(0.3), lineWidth: 1))
            .accessibilityLabel("Focus timeline: green on task, peach off task, grey unknown")
    }
}
