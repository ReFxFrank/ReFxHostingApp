import XCTest
@testable import ReFxApp

/// Encoding contract for `AdminCreateServerBody` (POST /admin/servers) and
/// permissive decoding for the catalog models the admin create-server wizard
/// depends on (game templates + nodes). The encoder mirrors the app's: default
/// (camelCase) keys, ISO-8601 dates — so the request keys must match the panel's
/// AdminCreateServerDto exactly.
final class AdminProvisioningTests: XCTestCase {

    /// Same configuration as `APIClient`'s private encoder.
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: AdminCreateServerBody

    func testResourceSizedBodyEncodesExpectedKeys() throws {
        var body = AdminCreateServerBody(name: "My SMP", ownerId: "u_1", nodeId: "n_2", templateId: "t_3")
        body.cpuCores = 2
        body.memoryMb = 4096
        body.diskMb = 20480
        body.environment = ["MINECRAFT_VERSION": "1.20.4"]

        let json = try encode(body)
        XCTAssertEqual(json["name"] as? String, "My SMP")
        XCTAssertEqual(json["ownerId"] as? String, "u_1")
        XCTAssertEqual(json["nodeId"] as? String, "n_2")
        XCTAssertEqual(json["templateId"] as? String, "t_3")
        XCTAssertEqual(json["cpuCores"] as? Double, 2)
        XCTAssertEqual(json["memoryMb"] as? Int, 4096)
        XCTAssertEqual(json["diskMb"] as? Int, 20480)
        XCTAssertEqual((json["environment"] as? [String: Any])?["MINECRAFT_VERSION"] as? String, "1.20.4")
        // Slot/swap fields are omitted when nil (default JSONEncoder drops nil optionals).
        XCTAssertNil(json["slots"])
        XCTAssertNil(json["swapMb"])
    }

    func testSlotSizedBodyOmitsResourceKeys() throws {
        var body = AdminCreateServerBody(name: "Voice", ownerId: "u_9", nodeId: "n_1", templateId: "t_ts")
        body.slots = 32

        let json = try encode(body)
        XCTAssertEqual(json["slots"] as? Int, 32)
        XCTAssertNil(json["cpuCores"])
        XCTAssertNil(json["memoryMb"])
        XCTAssertNil(json["diskMb"])
        XCTAssertNil(json["environment"])
    }

    func testMinimalBodyOnlyRequiredKeys() throws {
        let body = AdminCreateServerBody(name: "Bare", ownerId: "u_1", nodeId: "n_1", templateId: "t_1")
        let json = try encode(body)
        XCTAssertEqual(Set(json.keys), ["name", "ownerId", "nodeId", "templateId"])
    }

    // MARK: AdminGameTemplate (drives the game picker + recommended-spec prefill)

    func testGameTemplateDecodesWithCategoryAndVariables() throws {
        let json = """
        {
          "id": "t_mc", "categoryId": "c_1",
          "category": { "id": "c_1", "name": "Sandbox", "slug": "sandbox", "iconUrl": null },
          "name": "Minecraft Java", "slug": "minecraft", "author": "ReFx",
          "description": "Vanilla + modded", "version": 3,
          "deployMethods": ["DOCKER"], "supportsLinux": true, "supportsWindows": false,
          "dockerImages": null, "steamAppId": null,
          "startupCommand": "java -jar server.jar",
          "recCpuCores": 2.0, "recMemoryMb": 4096, "recDiskMb": 20480,
          "isPublished": true, "featured": true, "sortOrder": 1, "tags": ["popular"],
          "variables": [
            { "id": "v_1", "templateId": "t_mc", "envName": "MINECRAFT_VERSION",
              "displayName": "Version", "description": "MC version", "type": "STRING",
              "defaultValue": "latest", "userEditable": true, "userViewable": true, "sortOrder": 0 }
          ]
        }
        """
        let template = try TestJSON.decode(AdminGameTemplate.self, json)
        XCTAssertEqual(template.id, "t_mc")
        XCTAssertEqual(template.category?.name, "Sandbox")
        XCTAssertEqual(template.recCpuCores, 2.0)
        XCTAssertEqual(template.recMemoryMb, 4096)
        XCTAssertEqual(template.variables?.count, 1)
        XCTAssertEqual(template.variables?.first?.envName, "MINECRAFT_VERSION")
        XCTAssertTrue(template.variables?.first?.userEditable ?? false)
    }

    func testGameTemplateDecodesWithoutOptionalsAndUnknownDeployMethod() throws {
        let json = """
        {
          "id": "t_x", "categoryId": null, "category": null,
          "name": "Custom", "slug": "custom", "author": "ReFx", "description": null,
          "version": 1, "deployMethods": ["WARP_DRIVE"],
          "supportsLinux": true, "supportsWindows": true,
          "dockerImages": null, "steamAppId": 730,
          "startupCommand": "./run", "recCpuCores": 1.0, "recMemoryMb": 1024, "recDiskMb": 5120,
          "isPublished": false, "featured": false, "sortOrder": 0, "tags": null, "variables": null
        }
        """
        let template = try TestJSON.decode(AdminGameTemplate.self, json)
        XCTAssertNil(template.category)
        XCTAssertNil(template.variables)
        // Unknown deploy method falls back rather than failing the whole decode.
        XCTAssertEqual(template.deployMethods, [.unknown])
        XCTAssertEqual(template.steamAppId, 730)
    }

    // MARK: NodeAdmin (drives the node picker)

    func testNodeDecodesWithRegion() throws {
        let json = """
        {
          "id": "n_1", "name": "fsn-1", "fqdn": "fsn-1.refx.gg",
          "state": "ONLINE", "agentVersion": "1.4.0", "maintenance": false,
          "region": { "name": "Falkenstein", "code": "EU" },
          "memoryMb": 65536, "diskMb": 512000
        }
        """
        let node = try TestJSON.decode(NodeAdmin.self, json)
        XCTAssertEqual(node.id, "n_1")
        XCTAssertEqual(node.name, "fsn-1")
        XCTAssertEqual(node.region?.name, "Falkenstein")
    }

    func testNodeDecodesPermissivelyWithoutOptionals() throws {
        let json = """
        { "id": "n_2", "name": "bare-node", "state": "OFFLINE" }
        """
        let node = try TestJSON.decode(NodeAdmin.self, json)
        XCTAssertEqual(node.name, "bare-node")
        XCTAssertNil(node.region)
        XCTAssertNil(node.memoryMb)
    }

    // MARK: CreateNodeBody / CreateNodeResult (POST /admin/nodes)

    func testCreateNodeBodyEncodesExpectedKeys() throws {
        let body = CreateNodeBody(
            name: "node-eu-01", fqdn: "node-eu-01.example.com", regionId: "r_1", os: "LINUX",
            cpuCores: 8, memoryMb: 16384, diskMb: 512000,
            allocationPortStart: 25565, allocationPortEnd: 25999)
        let json = try encode(body)
        XCTAssertEqual(json["name"] as? String, "node-eu-01")
        XCTAssertEqual(json["fqdn"] as? String, "node-eu-01.example.com")
        XCTAssertEqual(json["regionId"] as? String, "r_1")
        XCTAssertEqual(json["os"] as? String, "LINUX")
        XCTAssertEqual(json["cpuCores"] as? Int, 8)
        XCTAssertEqual(json["memoryMb"] as? Int, 16384)
        XCTAssertEqual(json["diskMb"] as? Int, 512000)
        XCTAssertEqual(json["allocationPortStart"] as? Int, 25565)
        XCTAssertEqual(json["allocationPortEnd"] as? Int, 25999)
    }

    func testCreateNodeResultDecodesTokenFromFullNodePayload() throws {
        // The response is the whole Node plus bootstrapToken — decode permissively,
        // ignoring node fields we don't need.
        let json = """
        {
          "id": "n_new", "name": "node-eu-01", "fqdn": "node-eu-01.example.com",
          "state": "PROVISIONING", "agentVersion": null, "maintenance": false,
          "region": { "name": "Falkenstein", "code": "EU" },
          "memoryMb": 16384, "diskMb": 512000,
          "bootstrapToken": "bt_abc123"
        }
        """
        let result = try TestJSON.decode(CreateNodeResult.self, json)
        XCTAssertEqual(result.id, "n_new")
        XCTAssertEqual(result.name, "node-eu-01")
        XCTAssertEqual(result.bootstrapToken, "bt_abc123")
    }

    // MARK: CreditReason (store-credit adjust sheet)

    private struct ReasonWrapper: Decodable { let reason: CreditReason }

    func testCreditReasonKnownAndUnknown() throws {
        XCTAssertEqual(try TestJSON.decode(ReasonWrapper.self, #"{ "reason": "ADMIN_GRANT" }"#).reason, .adminGrant)
        XCTAssertEqual(try TestJSON.decode(ReasonWrapper.self, #"{ "reason": "REFUND" }"#).reason, .refund)
        // Server adds a new reason the app doesn't know → unknown, never a crash.
        XCTAssertEqual(try TestJSON.decode(ReasonWrapper.self, #"{ "reason": "LOYALTY_BONUS" }"#).reason, .unknown)
    }
}
