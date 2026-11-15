import Foundation

public struct ProcessOutput: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

enum ProcessRunner {
    /// Runs a tool to completion. Secrets go in through `stdin` or `environment`,
    /// never through `arguments`: those are visible to every process in `ps`.
    /// Ejecuta una herramienta hasta el final. Los secretos entran por `stdin` o
    /// `environment`, nunca por `arguments`: esos los ve cualquier proceso en `ps`.
    static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30,
        waitingFor what: String
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            throw SwitchError.cliFailed(tr("could not run \(executable): \(error.localizedDescription)", "no pude ejecutar \(executable): \(error.localizedDescription)"))
        }

        // Drain both pipes while the tool runs: a full pipe would block it forever.
        // Se vacían las dos tuberías mientras corre: una tubería llena lo bloquearía.
        let collected = Collected()
        let readers = DispatchGroup()
        for (pipe, isError) in [(output, false), (errors, true)] {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.set(data, isError: isError)
                readers.leave()
            }
        }

        if let stdin {
            try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        }
        try? input.fileHandleForWriting.close()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            throw SwitchError.timeout(what)
        }
        readers.wait()

        return ProcessOutput(
            status: process.terminationStatus,
            stdout: String(decoding: collected.out, as: UTF8.self),
            stderr: String(decoding: collected.err, as: UTF8.self)
        )
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()

        func set(_ data: Data, isError: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if isError { stderr = data } else { stdout = data }
        }

        var out: Data { lock.lock(); defer { lock.unlock() }; return stdout }
        var err: Data { lock.lock(); defer { lock.unlock() }; return stderr }
    }
}
