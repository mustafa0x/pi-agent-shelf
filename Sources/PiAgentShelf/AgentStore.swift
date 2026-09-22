import Foundation

final class AgentStore: ObservableObject {
    @Published private(set) var agents: [PiAgent] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var focusError: String?

    private let scanner = AgentScanner()
    private let ghosttyClient = GhosttyClient()
    private var timer: Timer?

    init(agents: [PiAgent] = []) {
        self.agents = agents
    }

    func start() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: 90, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !isRefreshing else { return }
        let targets = GhosttyClient.runningTargets()
        guard !targets.isEmpty else {
            errorMessage = GhosttyClientError.notRunning.localizedDescription
            return
        }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.scanner.scan(ghosttyTargets: targets)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.agents = result.agents
                self.errorMessage = result.errorMessage
                self.isRefreshing = false
            }
        }
    }

    func focus(_ agent: PiAgent, completion: @escaping (Bool) -> Void) {
        let targetIsRunning = GhosttyClient.runningTargets().contains {
            $0.processIdentifier == agent.ghosttyTarget.processIdentifier
                && $0.bundleIdentifier == agent.ghosttyTarget.bundleIdentifier
        }
        guard targetIsRunning else {
            focusError = GhosttyClientError.notRunning.localizedDescription
            completion(false)
            return
        }

        focusError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result: Result<Void, Error>
            do {
                try self.ghosttyClient.focus(tty: agent.tty, target: agent.ghosttyTarget)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success:
                    completion(true)
                case .failure(let error):
                    self?.focusError = error.localizedDescription
                    completion(false)
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
