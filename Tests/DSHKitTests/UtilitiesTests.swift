import XCTest
@testable import DSHKit

final class UtilitiesTests: XCTestCase {
    func testJSONValueRoundTrip() throws {
        let value: JSONValue = .object([
            "a": .int(1),
            "b": .array([.string("x"), .bool(true), .null]),
            "c": .double(1.5),
        ])
        let text = value.jsonString()
        let parsed = JSONValue.parse(text)
        XCTAssertEqual(parsed, value)
        XCTAssertTrue(text.contains("\"a\":1"))
    }

    func testJSONValueObjectSubscriptSet() {
        var value: JSONValue = .object([:])
        value["x"] = .string("y")
        XCTAssertEqual(value["x"]?.stringValue, "y")
    }

    func testGlobMatcher() {
        let matcher = GlobMatcher("**/*.swift")
        XCTAssertTrue(matcher.matches("Sources/DSHKit/Agent/Agent.swift"))
        XCTAssertTrue(matcher.matches("Package.swift"))
        XCTAssertFalse(matcher.matches("README.md"))

        let single = GlobMatcher("*.md")
        XCTAssertTrue(single.matches("README.md"))
        XCTAssertFalse(single.matches("docs/README.md"))

        let braces = GlobMatcher("*.{swift,md}")
        XCTAssertTrue(braces.matches("a.swift"))
        XCTAssertTrue(braces.matches("a.md"))
        XCTAssertFalse(braces.matches("a.txt"))
    }

    func testLLMFailureClassification() {
        XCTAssertEqual(LLMFailure.classify(status: 401, body: "").kind, .invalidCredential)
        XCTAssertEqual(LLMFailure.classify(status: 429, body: "").kind, .rateLimit)
        XCTAssertEqual(LLMFailure.classify(status: 503, body: "").kind, .overload)
        XCTAssertEqual(LLMFailure.classify(status: 400, body: "maximum context length exceeded").kind, .contextOverflow)
        XCTAssertEqual(LLMFailure.classify(status: 402, body: "Insufficient Balance").kind, .quota)
        XCTAssertTrue(LLMFailureKind.rateLimit.isRetryable)
        XCTAssertFalse(LLMFailureKind.invalidCredential.isRetryable)
    }

    func testHTMLSimplification() {
        let html = """
        <html><head><style>.x{color:red}</style><script>alert(1)</script></head>
        <body><h1>Title</h1><p>Hello &amp; welcome</p><p>Line</p></body></html>
        """
        let text = WebTools.simplifyHTML(html)
        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("Hello & welcome"))
        XCTAssertFalse(text.contains("alert(1)"))
        XCTAssertFalse(text.contains("<p>"))
    }

    func testPrivateHostGuard() {
        XCTAssertTrue(WebTools.isPrivateHost("localhost"))
        XCTAssertTrue(WebTools.isPrivateHost("127.0.0.1"))
        XCTAssertTrue(WebTools.isPrivateHost("192.168.1.10"))
        XCTAssertTrue(WebTools.isPrivateHost("10.0.0.1"))
        XCTAssertTrue(WebTools.isPrivateHost("172.20.0.1"))
        XCTAssertFalse(WebTools.isPrivateHost("api.deepseek.com"))
    }

    func testSandboxBlocksEscapes() throws {
        let root = TestSupport.tempDirectory("dsh-sandbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let guardValue = SandboxGuard(root: root, mode: .workspaceWrite)
        let inside = try guardValue.resolve("a/b.txt")
        XCTAssertTrue(inside.path.hasPrefix(root.path))
        XCTAssertThrowsError(try guardValue.resolve("../escape.txt"))
        XCTAssertThrowsError(try guardValue.resolve("/etc/passwd"))
    }

    func testReadFileTool() async throws {
        let root = TestSupport.tempDirectory("dsh-read")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "one\ntwo\nthree\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let tool = FileTools.readFile()
        let context = ToolContext(
            sessionID: "s",
            workspace: root,
            callID: "c",
            sandbox: SandboxGuard(root: root, mode: .readOnly),
            emit: { _ in }
        )
        let result = try await tool.execute(context, .object(["path": .string("a.txt")]))
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.output.contains("1\tone"))
        XCTAssertTrue(result.output.contains("3\tthree"))
    }

    func testWriteFileHonorsReadOnlySandbox() async throws {
        let root = TestSupport.tempDirectory("dsh-write")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = ToolContext(
            sessionID: "s",
            workspace: root,
            callID: "c",
            sandbox: SandboxGuard(root: root, mode: .readOnly),
            emit: { _ in }
        )
        do {
            _ = try await FileTools.writeFile().execute(context, .object(["path": .string("x.txt"), "content": .string("x")]))
            XCTFail("expected sandbox failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("read-only"))
        }
    }
}

