import XCTest
@testable import DeepSeekAliasProxyCore

final class CoworkProbeResponseTests: XCTestCase {
    func testConnectivityProbeProducesLocalAnthropicMessageResponse() throws {
        let request: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [
                [
                    "role": "user",
                    "content": ".",
                ],
            ],
        ]

        let response = try XCTUnwrap(CoworkProbeResponse.payloadIfMatched(request, requestID: "ABC-123"))

        XCTAssertEqual(response["type"] as? String, "message")
        XCTAssertEqual(response["role"] as? String, "assistant")
        XCTAssertEqual(response["model"] as? String, "claude-haiku-4-5")
        let content = try XCTUnwrap(response["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, ".")
        let usage = try XCTUnwrap(response["usage"] as? [String: Any])
        XCTAssertEqual(usage["input_tokens"] as? Int, 1)
        XCTAssertEqual(usage["output_tokens"] as? Int, 1)
    }

    func testConnectivityProbeAcceptsSingleTextBlock() {
        let request: [String: Any] = [
            "max_tokens": 1,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": " .\n",
                        ],
                    ],
                ],
            ],
        ]

        XCTAssertTrue(CoworkProbeResponse.isConnectivityProbe(request))
    }

    func testConnectivityProbeDoesNotMatchRealToolOrStreamRequests() {
        let streamRequest: [String: Any] = [
            "max_tokens": 1,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": ".",
                ],
            ],
        ]
        let toolRequest: [String: Any] = [
            "max_tokens": 1,
            "tools": [
                [
                    "name": "example",
                    "input_schema": ["type": "object"],
                ],
            ],
            "messages": [
                [
                    "role": "user",
                    "content": ".",
                ],
            ],
        ]

        XCTAssertFalse(CoworkProbeResponse.isConnectivityProbe(streamRequest))
        XCTAssertFalse(CoworkProbeResponse.isConnectivityProbe(toolRequest))
    }
}
