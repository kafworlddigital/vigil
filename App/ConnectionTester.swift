import Foundation

enum ConnectionTester {
    @MainActor static func run() async -> [ConnectionResult] {
        let ai=VigilAI.shared
        ai.start()
        await ai.testAll()
        return ConnectionStatus.results(ai.models,viaBrain:ai.usingBrain)
    }
}
