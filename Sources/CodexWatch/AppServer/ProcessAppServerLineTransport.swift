import Darwin
import Foundation

actor ProcessAppServerLineTransport: AppServerLineTransport {
    private let executableURL: URL
    private let maximumLineBytes: Int
    private var process: Process?
    private var standardInput: FileHandle?
    private var readerTask: Task<Void, Never>?

    init(
        executableURL: URL,
        maximumLineBytes: Int = CodexAppServerClient.maximumLineBytes
    ) {
        self.executableURL = executableURL
        self.maximumLineBytes = maximumLineBytes
    }

    init(
        locator: CodexExecutableLocator,
        maximumLineBytes: Int = CodexAppServerClient.maximumLineBytes
    ) throws {
        self.init(
            executableURL: try locator.locate(),
            maximumLineBytes: maximumLineBytes
        )
    }

    func start(
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async throws {
        guard process == nil else {
            throw AppServerError.transportFailure
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let child = Process()
        child.executableURL = executableURL
        child.arguments = ["app-server"]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
        } catch {
            throw AppServerError.transportFailure
        }

        let input = inputPipe.fileHandleForWriting
        let output = outputPipe.fileHandleForReading
        // A write racing child exit must fail with EPIPE, not kill the app via SIGPIPE.
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        process = child
        standardInput = input
        readerTask = Task.detached(priority: .utility) { [maximumLineBytes] in
            await Self.readLines(
                from: output,
                maximumLineBytes: maximumLineBytes,
                receiveLine: receiveLine,
                termination: termination
            )
        }
    }

    func send(_ line: Data) async throws {
        guard line.count <= maximumLineBytes,
              let standardInput,
              process?.isRunning == true else {
            throw AppServerError.transportFailure
        }
        var framedLine = line
        framedLine.append(0x0A)
        do {
            try standardInput.write(contentsOf: framedLine)
        } catch {
            throw AppServerError.transportFailure
        }
    }

    func stop() async {
        readerTask?.cancel()
        readerTask = nil

        try? standardInput?.close()
        standardInput = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        // The reader owns stdout and closes it on exit, so a descriptor number
        // is never freed (and reused by a reconnect) while a read may be pending.
    }

    private nonisolated static func readLines(
        from handle: FileHandle,
        maximumLineBytes: Int,
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async {
        defer { try? handle.close() }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
        do {
            while !Task.isCancelled {
                let remainingThroughDetectionByte = maximumLineBytes - buffer.count + 1
                guard remainingThroughDetectionByte > 0 else {
                    await termination(AppServerError.lineTooLarge(maxBytes: maximumLineBytes))
                    return
                }
                let readCount = min(chunk.count, remainingThroughDetectionByte)
                // FileHandle.read(upToCount:) may wait to fill the buffer on a pipe.
                // POSIX read returns currently available bytes, so a short JSONL reply
                // is delivered while the long-lived server keeps stdout open.
                let count = Darwin.read(handle.fileDescriptor, &chunk, readCount)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw AppServerError.transportFailure
                }
                guard count > 0 else {
                    if !buffer.isEmpty {
                        await receiveLine(strippingCarriageReturn(from: buffer))
                    }
                    await termination(nil)
                    return
                }
                buffer.append(contentsOf: chunk.prefix(count))

                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newlineIndex])
                    buffer.removeSubrange(...newlineIndex)
                    let normalized = strippingCarriageReturn(from: line)
                    guard normalized.count <= maximumLineBytes else {
                        await termination(
                            AppServerError.lineTooLarge(maxBytes: maximumLineBytes)
                        )
                        return
                    }
                    await receiveLine(normalized)
                }

                guard buffer.count <= maximumLineBytes else {
                    await termination(AppServerError.lineTooLarge(maxBytes: maximumLineBytes))
                    return
                }
            }
        } catch {
            if !Task.isCancelled {
                await termination(AppServerError.transportFailure)
            }
        }
    }

    private nonisolated static func strippingCarriageReturn(from data: Data) -> Data {
        guard data.last == 0x0D else { return data }
        return data.dropLast()
    }
}
