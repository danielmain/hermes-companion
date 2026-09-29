import Foundation
import CloudKit

// MARK: - Models
struct LocationPayload: Codable {
    let id: String
    let timestamp: String
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speedMps: Double
    let course: Double
    let source: String
    let batteryLevel: Double
    let batteryState: String
    let appState: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy = "horizontal_accuracy"
        case verticalAccuracy = "vertical_accuracy"
        case speedMps = "speed_mps"
        case course
        case source
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case appState = "app_state"
        case deviceName = "device_name"
    }

    static func from(record: CKRecord) -> LocationPayload? {
        guard let latNum = record["latitude"] as? NSNumber,
              let lonNum = record["longitude"] as? NSNumber else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        let date = (record["timestamp"] as? Date) ?? record.creationDate ?? Date()

        return LocationPayload(
            id: record.recordID.recordName,
            timestamp: isoFormatter.string(from: date),
            latitude: latNum.doubleValue,
            longitude: lonNum.doubleValue,
            altitude: (record["altitude"] as? NSNumber)?.doubleValue ?? 0.0,
            horizontalAccuracy: (record["horizontalAccuracy"] as? NSNumber)?.doubleValue ?? 0.0,
            verticalAccuracy: (record["verticalAccuracy"] as? NSNumber)?.doubleValue ?? 0.0,
            speedMps: (record["speed"] as? NSNumber)?.doubleValue ?? -1.0,
            course: (record["course"] as? NSNumber)?.doubleValue ?? -1.0,
            source: (record["source"] as? String) ?? "CloudKit",
            batteryLevel: (record["batteryLevel"] as? NSNumber)?.doubleValue ?? -1.0,
            batteryState: (record["batteryState"] as? String) ?? "unknown",
            appState: (record["appState"] as? String) ?? "unknown",
            deviceName: (record["deviceName"] as? String) ?? "iPhone"
        )
    }
}

// MARK: - CloudKit Helper
class CloudKitBridge {
    let container: CKContainer
    let privateDB: CKDatabase

    init(containerIdentifier: String) {
        if containerIdentifier.isEmpty {
            self.container = CKContainer.default()
        } else {
            self.container = CKContainer(identifier: containerIdentifier)
        }
        self.privateDB = self.container.privateCloudDatabase
    }

    func checkStatus(completion: @escaping (Bool, String) -> Void) {
        container.accountStatus { status, error in
            if let error = error {
                completion(false, "CloudKit Error: \(error.localizedDescription)")
                return
            }
            switch status {
            case .available:
                completion(true, "iCloud Active (Available)")
            case .noAccount:
                completion(false, "No iCloud Account Signed In on this Mac")
            case .restricted:
                completion(false, "iCloud Restricted")
            case .couldNotDetermine:
                completion(false, "Could not determine account status")
            case .temporarilyUnavailable:
                completion(false, "iCloud Temporarily Unavailable")
            @unknown default:
                completion(false, "Unknown status")
            }
        }
    }

    func fetchLatest(completion: @escaping (Result<LocationPayload, Error>) -> Void) {
        // 1. First try fetching the singleton latest record
        let latestID = CKRecord.ID(recordName: "latest_user_location")
        privateDB.fetch(withRecordID: latestID) { record, error in
            if let record = record, let payload = LocationPayload.from(record: record) {
                completion(.success(payload))
                return
            }

            // 2. Fallback: Query newest LocationRecord
            let query = CKQuery(recordType: "LocationRecord", predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = 1

            var foundRecord: CKRecord?

            operation.recordMatchedBlock = { _, result in
                if case .success(let rec) = result {
                    foundRecord = rec
                }
            }

            operation.queryResultBlock = { result in
                if let found = foundRecord, let payload = LocationPayload.from(record: found) {
                    completion(.success(payload))
                } else if case .failure(let queryError) = result {
                    completion(.failure(queryError))
                } else {
                    let err = NSError(domain: "HermesCloudKit", code: 404, userInfo: [NSLocalizedDescriptionKey: "No location records found in CloudKit Private DB"])
                    completion(.failure(err))
                }
            }

            self.privateDB.add(operation)
        }
    }

    func fetchHistory(limit: Int, completion: @escaping (Result<[LocationPayload], Error>) -> Void) {
        let query = CKQuery(recordType: "LocationRecord", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = limit

        var records: [LocationPayload] = []

        operation.recordMatchedBlock = { _, result in
            if case .success(let rec) = result, let payload = LocationPayload.from(record: rec) {
                records.append(payload)
            }
        }

        operation.queryResultBlock = { result in
            switch result {
            case .success:
                completion(.success(records))
            case .failure(let error):
                completion(.failure(error))
            }
        }

        privateDB.add(operation)
    }

    func saveTestPing(completion: @escaping (Bool, String) -> Void) {
        let testID = CKRecord.ID(recordName: "test_ping_\(UUID().uuidString)")
        let testRecord = CKRecord(recordType: "DiagnosticPing", recordID: testID)
        testRecord["timestamp"] = Date() as NSDate
        testRecord["deviceName"] = "macOS Hermes" as NSString

        privateDB.save(testRecord) { savedRecord, error in
            if let error = error {
                completion(false, "Failed to save: \(error.localizedDescription)")
                return
            }
            if let saved = savedRecord {
                self.privateDB.delete(withRecordID: saved.recordID) { _, _ in }
                completion(true, "CloudKit Private DB read/write verified successfully")
            } else {
                completion(false, "No record returned")
            }
        }
    }
}

// MARK: - CLI Entrypoint
func printUsage() {
    let usage = """
    Hermes CloudKit Bridge (macOS)
    Usage: hermes-cloudkit-bridge <command> [options]

    Commands:
      status             Check iCloud account and CloudKit availability
      latest             Fetch the latest user location from CloudKit Private DB
      history            Fetch recent location history
      test-ping          Verify read/write access to CloudKit Private DB
      daemon             Continuously poll and cache latest location to local file

    Options:
      --container <id>   CloudKit container ID (default: iCloud.com.hermes.HermesCompanion)
      --limit <n>        Limit number of history records (default: 20)
      --interval <s>     Daemon polling interval in seconds (default: 10)
      --output <path>    Daemon output JSON file path (default: /tmp/hermes_latest_location.json)
      --pretty           Format JSON output with indentation
    """
    print(usage)
}

let args = CommandLine.arguments

guard args.count > 1 else {
    printUsage()
    exit(1)
}

let command = args[1]
var containerID = "iCloud.com.hermes.HermesCompanion"
var limit = 20
var interval: TimeInterval = 10.0
var outputPath = "/tmp/hermes_latest_location.json"
var prettyPrint = false

var i = 2
while i < args.count {
    switch args[i] {
    case "--container":
        if i + 1 < args.count { containerID = args[i + 1]; i += 1 }
    case "--limit":
        if i + 1 < args.count { limit = Int(args[i + 1]) ?? 20; i += 1 }
    case "--interval":
        if i + 1 < args.count { interval = Double(args[i + 1]) ?? 10.0; i += 1 }
    case "--output":
        if i + 1 < args.count { outputPath = args[i + 1]; i += 1 }
    case "--pretty":
        prettyPrint = true
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        break
    }
    i += 1
}

let bridge = CloudKitBridge(containerIdentifier: containerID)
let semaphore = DispatchSemaphore(value: 0)

switch command {
case "status":
    bridge.checkStatus { success, message in
        let output: [String: Any] = [
            "success": success,
            "container": containerID,
            "status": message
        ]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: prettyPrint ? [.prettyPrinted] : []) {
            print(String(data: data, encoding: .utf8) ?? message)
        } else {
            print(message)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 15)

case "latest":
    bridge.fetchLatest { result in
        switch result {
        case .success(let payload):
            let encoder = JSONEncoder()
            if prettyPrint { encoder.outputFormatting = .prettyPrinted }
            if let data = try? encoder.encode(payload), let jsonStr = String(data: data, encoding: .utf8) {
                print(jsonStr)
            }
        case .failure(let error):
            let errDict: [String: Any] = [
                "error": error.localizedDescription,
                "code": (error as NSError).code
            ]
            if let data = try? JSONSerialization.data(withJSONObject: errDict, options: []) {
                print(String(data: data, encoding: .utf8) ?? "{\"error\": \"\(error.localizedDescription)\"}")
            }
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 20)

case "history":
    bridge.fetchHistory(limit: limit) { result in
        switch result {
        case .success(let records):
            let encoder = JSONEncoder()
            if prettyPrint { encoder.outputFormatting = .prettyPrinted }
            if let data = try? encoder.encode(records), let jsonStr = String(data: data, encoding: .utf8) {
                print(jsonStr)
            }
        case .failure(let error):
            print("{\"error\": \"\(error.localizedDescription)\"}")
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 25)

case "test-ping":
    bridge.saveTestPing { success, message in
        let output: [String: Any] = ["success": success, "message": message]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: prettyPrint ? [.prettyPrinted] : []) {
            print(String(data: data, encoding: .utf8) ?? message)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 20)

case "daemon":
    print("Hermes CloudKit Daemon started. Polling container '\(containerID)' every \(interval)s...")
    print("Writing latest location to \(outputPath)")
    let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
        bridge.fetchLatest { result in
            if case .success(let payload) = result {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(payload) {
                    try? data.write(to: URL(fileURLWithPath: outputPath))
                }
            }
        }
    }
    RunLoop.current.add(timer, forMode: .default)
    RunLoop.current.run()

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
