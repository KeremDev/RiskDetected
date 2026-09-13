import Foundation

@main struct NovaWorkspaceCapabilityCheck {
    static func main() throws {
        let owner = UUID(), company = UUID()
        var count = 0
        let base: [String: Any] = ["schema_version": 1, "owner_id": owner.uuidString, "company_id": company.uuidString, "company_name": "Firma", "is_archived": false, "can_read": true, "can_write": true]
        func decode(_ body: [String: Any], selected: UUID?) throws -> NovaWorkspaceCapability {
            try .decode(JSONSerialization.data(withJSONObject: body), owner: owner, company: selected)
        }
        let paid = try decode(base, selected: company); assert(paid.can_write); count += 1
        for (key, value) in [("schema_version", 2 as Any), ("owner_id", UUID().uuidString), ("company_id", NSNull()), ("company_name", NSNull()), ("company_name", "  "), ("is_archived", NSNull()), ("is_archived", true), ("can_read", false), ("can_write", "true"), ("can_read", 1)] {
            var body = base; body[key] = value
            do { _ = try decode(body, selected: company); fatalError("Accepted invalid \(key)") } catch { count += 1 }
        }
        var archived = base; archived["is_archived"] = true; archived["can_write"] = false
        let readOnly = try decode(archived, selected: company); assert(readOnly.can_read); count += 1
        var global = base; global["company_id"] = NSNull(); global["company_name"] = NSNull(); global["is_archived"] = NSNull(); global["can_write"] = false
        let all = try decode(global, selected: nil); assert(!all.can_write); count += 1
        global["company_name"] = "Firma"
        do { _ = try decode(global, selected: nil); fatalError("Global leaked company") } catch { count += 1 }
        print("NOVA workspace capability: \(count) checks PASS")
    }
}
