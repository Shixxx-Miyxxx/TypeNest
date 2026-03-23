import Foundation
import XCTest
@testable import TypeNestCore

private func writeFile(_ url: URL, content: String = "test") throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(content.utf8).write(to: url)
}

final class PlannerTests: XCTestCase {
    private final class StopCounter: @unchecked Sendable {
        var value = 0
    }

    func testRawJpegPresetMovesRawAndJpeg() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.jpeg"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .skip
        )

        let planResult = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        let rawOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.pathExtension.lowercased() == "raw" })
        let jpegOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.pathExtension.lowercased() == "jpeg" })

        XCTAssertEqual(rawOp.action, .move)
        XCTAssertEqual(rawOp.destinationURL, day.appendingPathComponent("raw").appendingPathComponent("000001.raw").standardizedFileURL)
        XCTAssertEqual(jpegOp.action, .move)
        XCTAssertEqual(jpegOp.destinationURL, day.appendingPathComponent("jpeg").appendingPathComponent("000001.jpeg").standardizedFileURL)

        let applyResult = apply(operations: planResult.operations, collisionPolicy: .skip)
        XCTAssertEqual(applyResult.summary.executed, 2)
        XCTAssertEqual(applyResult.summary.errors, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: day.appendingPathComponent("raw/000001.raw").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: day.appendingPathComponent("jpeg/000001.jpeg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: day.appendingPathComponent("000001.raw").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: day.appendingPathComponent("000001.jpeg").path))
    }

    func testUppercaseJpgIsTreatedAsJpeg() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.JPG"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .skip
        )

        let planResult = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        let jpgOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.lastPathComponent == "000001.JPG" })
        XCTAssertEqual(jpgOp.action, .move)
        XCTAssertEqual(jpgOp.destinationURL, day.appendingPathComponent("jpeg").appendingPathComponent("000001.JPG").standardizedFileURL)
    }

    func testArwIsTreatedAsRaw() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.ARW"))
        try writeFile(day.appendingPathComponent("000001.jpeg"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .skip
        )

        let planResult = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        let arwOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.lastPathComponent == "000001.ARW" })
        XCTAssertEqual(arwOp.action, .move)
        XCTAssertEqual(arwOp.destinationURL, day.appendingPathComponent("raw").appendingPathComponent("000001.ARW").standardizedFileURL)
    }

    func testSecondRunIsIdempotentWhenTargetFoldersAreExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.jpeg"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .skip
        )

        let firstPlan = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        _ = apply(operations: firstPlan.operations, collisionPolicy: .skip)

        let secondPlan = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        XCTAssertEqual(secondPlan.summary.plannedOperations, 0)
    }

    func testSecondRunIsIdempotentWithoutFolderNameExclusionsInSubfolderMode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.jpeg"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: [],
            runMode: .move,
            collisionPolicy: .skip
        )

        let firstPlan = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        _ = apply(operations: firstPlan.operations, collisionPolicy: .skip)

        let secondPlan = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        XCTAssertEqual(secondPlan.summary.plannedOperations, 0)
    }

    func testAggregateModeSecondRunSkipsManagedOutputRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("report.json"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: [],
            runMode: .move,
            collisionPolicy: .skip
        )
        let ruleSet = try customExtensionsPreset(
            extensions: ["json"],
            destinationMode: .aggregate,
            aggregateRoot: "_sorted"
        )

        let firstPlan = try createPlan(options: options, ruleSet: ruleSet)
        _ = apply(operations: firstPlan.operations, collisionPolicy: .skip)

        let secondPlan = try createPlan(options: options, ruleSet: ruleSet)
        XCTAssertEqual(secondPlan.summary.scannedFiles, 0)
        XCTAssertEqual(secondPlan.summary.plannedOperations, 0)
    }

    func testCollisionRenameCreatesNumberedFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.jpeg"))
        try writeFile(day.appendingPathComponent("jpeg/000001.jpeg"), content: "existing")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .rename
        )

        let planResult = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        let jpegOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.pathExtension.lowercased() == "jpeg" })
        XCTAssertEqual(jpegOp.destinationURL, day.appendingPathComponent("jpeg/000001_1.jpeg").standardizedFileURL)

        let applyResult = apply(operations: planResult.operations, collisionPolicy: .rename)
        XCTAssertEqual(applyResult.summary.executed, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: day.appendingPathComponent("jpeg/000001_1.jpeg").path))
    }

    func testXmpSidecarIsIgnoredWhenRawPairExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("import_root")
        let day = root.appendingPathComponent("260228")
        try writeFile(day.appendingPathComponent("000001.raw"))
        try writeFile(day.appendingPathComponent("000001.xmp"))
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let options = PlannerOptions(
            rootURL: root,
            recursive: true,
            excludeDirectories: ["jpeg", "raw"],
            runMode: .move,
            collisionPolicy: .skip
        )

        let planResult = try createPlan(options: options, ruleSet: rawJpegCleanupPreset())
        let xmpOp = try XCTUnwrap(planResult.operations.first { $0.sourceURL.pathExtension.lowercased() == "xmp" })
        XCTAssertEqual(xmpOp.action, .ignore)
        XCTAssertTrue(xmpOp.reason.contains("sidecar_for="))
        XCTAssertTrue(xmpOp.reason.contains("raw"))
    }

    func testScanFilesCanBeCancelled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try writeFile(root.appendingPathComponent("one.txt"))
        try writeFile(root.appendingPathComponent("two.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let shouldStopChecks = StopCounter()
        XCTAssertThrowsError(
            try scanFiles(
                rootURL: root,
                recursive: false,
                shouldStop: {
                    shouldStopChecks.value += 1
                    return shouldStopChecks.value > 1
                }
            )
        ) { error in
            XCTAssertEqual(error as? TypeNestError, .cancelled)
        }
    }

    func testApplyCancellationMarksRemainingOperationsAsSkipped() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let operations = [
            Operation(
                sourceURL: root.appendingPathComponent("a.raw"),
                destinationURL: root.appendingPathComponent("raw/a.raw"),
                action: .move,
                reason: "move raw"
            ),
            Operation(
                sourceURL: root.appendingPathComponent("a.xmp"),
                destinationURL: nil,
                action: .ignore,
                reason: "ignore sidecar"
            ),
            Operation(
                sourceURL: root.appendingPathComponent("a.jpeg"),
                destinationURL: root.appendingPathComponent("jpeg/a.jpeg"),
                action: .move,
                reason: "move jpeg"
            ),
        ]

        let result = apply(
            operations: operations,
            collisionPolicy: .skip,
            shouldStop: { true }
        )

        XCTAssertTrue(result.summary.cancelled)
        XCTAssertEqual(result.summary.skipped, operations.count)
        XCTAssertTrue(result.operations.allSatisfy { $0.status == .skipped })
    }
}
