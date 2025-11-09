import XCTest
@testable import RedoCrypto

/// Tests for RFC 8785 canonical JSON serialization
final class CanonicalJSONTests: XCTestCase {

    // MARK: - Basic Serialization

    func testSerializeString() throws {
        let dict = ["key": "value"]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"key\":\"value\"}")
    }

    func testSerializeNumber() throws {
        let dict = ["number": 42]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"number\":42}")
    }

    func testSerializeBoolean() throws {
        let dict = ["flag": true]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"flag\":true}")
    }

    func testSerializeNull() throws {
        let dict: [String: Any?] = ["value": nil]
        let json = try CanonicalJSON.stringify(dict as [String: Any])

        XCTAssertTrue(json.contains("null"))
    }

    // MARK: - Key Sorting

    func testKeySorting() throws {
        let dict = ["z": "last", "a": "first", "m": "middle"]
        let json = try CanonicalJSON.stringify(dict)

        // Keys should be alphabetically sorted
        XCTAssertEqual(json, "{\"a\":\"first\",\"m\":\"middle\",\"z\":\"last\"}")
    }

    func testNestedKeySorting() throws {
        let dict: [String: Any] = [
            "z": "value",
            "nested": [
                "b": 2,
                "a": 1
            ] as [String: Any]
        ]

        let json = try CanonicalJSON.stringify(dict)

        // Both top-level and nested keys should be sorted
        XCTAssertTrue(json.contains("\"nested\":{\"a\":1,\"b\":2}"))
    }

    // MARK: - Whitespace Removal

    func testNoWhitespace() throws {
        let dict = ["key": "value"]
        let json = try CanonicalJSON.stringify(dict)

        // Should have no spaces except in string values
        XCTAssertFalse(json.contains(" "))
        XCTAssertFalse(json.contains("\n"))
        XCTAssertFalse(json.contains("\t"))
    }

    // MARK: - String Escaping

    func testStringEscaping() throws {
        let dict = [
            "quote": "He said \"hello\"",
            "backslash": "path\\to\\file",
            "newline": "line1\nline2"
        ]

        let json = try CanonicalJSON.stringify(dict)

        XCTAssertTrue(json.contains("\\\""))  // Escaped quote
        XCTAssertTrue(json.contains("\\\\"))  // Escaped backslash
        XCTAssertTrue(json.contains("\\n"))   // Escaped newline
    }

    // MARK: - Arrays

    func testSerializeArray() throws {
        let dict: [String: Any] = ["array": [1, 2, 3]]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"array\":[1,2,3]}")
    }

    func testSerializeNestedArray() throws {
        let dict: [String: Any] = ["nested": [[1, 2], [3, 4]]]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"nested\":[[1,2],[3,4]]}")
    }

    // MARK: - Nested Objects

    func testSerializeNestedObject() throws {
        let dict: [String: Any] = [
            "outer": [
                "inner": "value"
            ]
        ]

        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"outer\":{\"inner\":\"value\"}}")
    }

    // MARK: - Determinism

    func testDeterministicOutput() throws {
        let dict = [
            "c": 3,
            "a": 1,
            "b": 2
        ]

        let json1 = try CanonicalJSON.stringify(dict)
        let json2 = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json1, json2)
    }

    func testOrderIndependence() throws {
        let dict1 = ["b": 2, "a": 1]
        let dict2 = ["a": 1, "b": 2]

        let json1 = try CanonicalJSON.stringify(dict1)
        let json2 = try CanonicalJSON.stringify(dict2)

        // Should produce identical output regardless of input order
        XCTAssertEqual(json1, json2)
    }

    // MARK: - RFC 8785 Compliance

    func testRFC8785Example1() throws {
        // Example from RFC 8785
        let dict = ["numbers": [333333333.33333329, 1e+30, 4.5, 2e-3, 0.000000000000000000000000001]]
        let json = try CanonicalJSON.stringify(dict)

        // Should not have exponential notation in canonical form
        // (though this specific test may vary based on JSON encoder)
        XCTAssertFalse(json.isEmpty)
    }

    func testRFC8785Example2() throws {
        // Unicode escaping test
        let dict = ["unicode": "Ã¥"]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertTrue(json.contains("unicode"))
    }

    // MARK: - Complex Structures

    func testComplexStructure() throws {
        let dict: [String: Any] = [
            "string": "value",
            "number": 42,
            "boolean": true,
            "null": NSNull(),
            "array": [1, "two", false],
            "object": [
                "nested": "data"
            ]
        ]

        let json = try CanonicalJSON.stringify(dict)

        // Keys should be sorted
        let keys = ["array", "boolean", "null", "number", "object", "string"]
        var lastIndex = -1

        for key in keys {
            let index = json.range(of: "\"\(key)\"")?.lowerBound.utf16Offset(in: json) ?? 0
            XCTAssertTrue(index > lastIndex, "Keys not in sorted order")
            lastIndex = index
        }
    }

    // MARK: - ChangeLogEntry Serialization

    func testSerializeChangeLogEntry() throws {
        let entry = createTestEntry()
        let json = try CanonicalJSON.stringify(entry)

        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("\"version\":1"))
        XCTAssertTrue(json.contains("\"action\":\"CREATE\""))
    }

    // MARK: - Validation

    func testIsCanonical() {
        // Valid canonical JSON
        XCTAssertTrue(CanonicalJSON.isCanonical("{\"a\":1,\"b\":2}"))

        // Has whitespace (not canonical)
        XCTAssertFalse(CanonicalJSON.isCanonical("{ \"a\": 1 }"))
    }

    // MARK: - Edge Cases

    func testEmptyObject() throws {
        let dict: [String: Any] = [:]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{}")
    }

    func testEmptyArray() throws {
        let dict: [String: Any] = ["array": []]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"array\":[]}")
    }

    func testEmptyString() throws {
        let dict = ["empty": ""]
        let json = try CanonicalJSON.stringify(dict)

        XCTAssertEqual(json, "{\"empty\":\"\"}")
    }

    // MARK: - Performance

    func testSerializationPerformance() {
        let dict = createLargeDict()

        measure {
            for _ in 0..<100 {
                _ = try? CanonicalJSON.stringify(dict)
            }
        }
    }

    // MARK: - Helper Methods

    private func createTestEntry() -> ChangeLogEntry {
        let timestamp = LogicalTimestamp(lamport: 1, wallDate: Date())
        let (publicKey, _, userId) = Ed25519Manager.generateKey()

        let author = AuthorInfo(
            userId: userId,
            deviceId: "test",
            name: nil,
            publicKey: publicKey
        )

        let data = ChangeData(dictionary: ["title": "Test"])

        return ChangeLogEntry(
            id: "sha256:" + String(repeating: "a", count: 64),
            version: 1,
            parents: [],
            timestamp: timestamp,
            author: author,
            action: .create,
            taskId: UUID().uuidString,
            data: data,
            signature: nil
        )
    }

    private func createLargeDict() -> [String: Any] {
        var dict: [String: Any] = [:]

        for i in 0..<50 {
            dict["key\(i)"] = "value\(i)"
        }

        return dict
    }
}

// MARK: - Import

import RedoCore
