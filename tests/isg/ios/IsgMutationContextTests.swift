import XCTest

// Hostless target: only Foundation transport code, no main app, SDKs or network.
final class IsgMutationContextTests: XCTestCase {
    private func check(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "mutation-context", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 43, "Corpus count changed; add/update individual test cases", file: file, line: line)
        let entry = try XCTUnwrap(cases.first { $0["id"] as? String == id })
        let valid = try XCTUnwrap(entry["valid"] as? Bool)
        let input = try XCTUnwrap(entry["input"])
        let encoded = try JSONSerialization.data(withJSONObject: input, options: [.fragmentsAllowed, .sortedKeys])
        let parsed = try? JSONDecoder().decode(IsgMutationContext.self, from: encoded)
        XCTAssertEqual(parsed != nil, valid, id, file: file, line: line)
    }

    func test_ios_company_create() throws { try check("ios_company_create") }
    func test_android_company_update() throws { try check("android_company_update") }
    func test_company_with_workplace() throws { try check("company_with_workplace") }
    func test_personal_scope() throws { try check("personal_scope") }
    func test_upper_bound_build_and_version() throws { try check("upper_bound_build_and_version") }
    func test_invalid_schema_version_5() throws { try check("invalid_schema_version_5") }
    func test_invalid_schema_version_6() throws { try check("invalid_schema_version_6") }
    func test_invalid_platform_7() throws { try check("invalid_platform_7") }
    func test_invalid_platform_8() throws { try check("invalid_platform_8") }
    func test_invalid_client_build_9() throws { try check("invalid_client_build_9") }
    func test_invalid_client_build_10() throws { try check("invalid_client_build_10") }
    func test_invalid_client_build_11() throws { try check("invalid_client_build_11") }
    func test_invalid_client_build_12() throws { try check("invalid_client_build_12") }
    func test_invalid_client_build_13() throws { try check("invalid_client_build_13") }
    func test_invalid_expected_version_14() throws { try check("invalid_expected_version_14") }
    func test_invalid_expected_version_15() throws { try check("invalid_expected_version_15") }
    func test_invalid_expected_version_16() throws { try check("invalid_expected_version_16") }
    func test_invalid_expected_version_17() throws { try check("invalid_expected_version_17") }
    func test_invalid_operation_id_18() throws { try check("invalid_operation_id_18") }
    func test_invalid_operation_id_19() throws { try check("invalid_operation_id_19") }
    func test_invalid_operation_id_20() throws { try check("invalid_operation_id_20") }
    func test_invalid_client_mutation_id_21() throws { try check("invalid_client_mutation_id_21") }
    func test_missing_schema_version() throws { try check("missing_schema_version") }
    func test_missing_operation_id() throws { try check("missing_operation_id") }
    func test_missing_client_mutation_id() throws { try check("missing_client_mutation_id") }
    func test_missing_platform() throws { try check("missing_platform") }
    func test_missing_client_build() throws { try check("missing_client_build") }
    func test_missing_expected_version() throws { try check("missing_expected_version") }
    func test_missing_scope() throws { try check("missing_scope") }
    func test_unknown_owner_field() throws { try check("unknown_owner_field") }
    func test_unknown_role() throws { try check("unknown_role") }
    func test_unknown_secret_field() throws { try check("unknown_secret_field") }
    func test_personal_company_link() throws { try check("personal_company_link") }
    func test_personal_entity_link() throws { try check("personal_entity_link") }
    func test_null_workplace() throws { try check("null_workplace") }
    func test_invalid_company() throws { try check("invalid_company") }
    func test_missing_company() throws { try check("missing_company") }
    func test_scope_unknown_kind() throws { try check("scope_unknown_kind") }
    func test_scope_null() throws { try check("scope_null") }
    func test_scope_array() throws { try check("scope_array") }
    func test_input_null() throws { try check("input_null") }
    func test_input_array() throws { try check("input_array") }
    func test_input_string() throws { try check("input_string") }
}
