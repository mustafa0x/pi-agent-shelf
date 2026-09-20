import Foundation

final class AgentStore: ObservableObject {
    @Published private(set) var agents: [PiAgent] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let scanner = AgentScanner()
    private var timer: Timer?

    init(agents: [PiAgent] = []) {
        self.agents = agents
    }

    func start() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.scanner.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.agents = result.agents
                self.errorMessage = result.errorMessage
                self.isRefreshing = false
            }
        }
    }

    func focus(_ agent: PiAgent, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try GhosttyClient.focus(terminalID: agent.terminalID)
                DispatchQueue.main.async {
                    self?.errorMessage = nil
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
