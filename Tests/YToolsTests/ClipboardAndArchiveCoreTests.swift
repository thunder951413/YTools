import Compression
import Foundation
import XCTest
import YToolsCore

final class SensitiveTextDetectorTests: XCTestCase {
    func testFlagsCodesAndTokens() {
        XCTAssertTrue(SensitiveTextDetector.looksSensitive("482913"))
        XCTAssertTrue(SensitiveTextDetector.looksSensitive("482-913"))
        XCTAssertTrue(SensitiveTextDetector.looksSensitive("sk-proj-abcdefghijklmnop1234"))
        XCTAssertTrue(SensitiveTextDetector.looksSensitive("ghp_aB3dE6gH9jK2mN5pQ8sT1vW4yZ7"))
        XCTAssertTrue(SensitiveTextDetector.looksSensitive("Zx9Kq2Lm8Np4Rt6Vw1Yb3Cd5Fg7Hj0"))
    }

    func testIgnoresOrdinaryText() {
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("2026"))
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("13800138000"), "Phone numbers are not codes")
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("550e8400-e29b-41d4-a716-446655440000"), "UUIDs stay")
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"))
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("https://example.com/Path/To/Resource123ABC"))
        XCTAssertFalse(SensitiveTextDetector.looksSensitive("hello world 123456"))
    }
}

final class SequentialPasteRouterTests: XCTestCase {
    func testOptionReturnQueuesOnlyInClipboard() {
        let router = PanelCommandRouter()
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 36, modifiers: .option), mode: .clipboard), .queueClipboardItem)
        XCTAssertNotEqual(router.command(for: PanelKeyEvent(keyCode: 36, modifiers: .option), mode: .launcher), .queueClipboardItem)
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 36, modifiers: []), mode: .clipboard), .activateSelected)
    }
}

final class ZipArchiveWriterTests: XCTestCase {
    func testArchivesDirectoryWithValidHeadersAndRoundTripsDeflate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-zip-\(UUID())")
        let folder = root.appendingPathComponent("资料")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = Data(String(repeating: "YTools 压缩测试 line\n", count: 200).utf8)
        try text.write(to: folder.appendingPathComponent("说明.txt"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("子目录/small.bin"))

        let archive = try ZipArchiveWriter.archive(folder)
        XCTAssertEqual(archive.lastPathComponent, "资料.zip")
        XCTAssertEqual(try ZipArchiveWriter.archive(folder).lastPathComponent, "资料 2.zip", "Never overwrites")

        let data = try Data(contentsOf: archive)
        let eocd = data.suffix(22)
        XCTAssertEqual(eocd.prefix(4), Data([0x50, 0x4B, 0x05, 0x06]))
        let entryCount = Int(eocd[eocd.startIndex + 10]) | Int(eocd[eocd.startIndex + 11]) << 8
        XCTAssertEqual(entryCount, 4, "folder, subfolder and two files")

        // Walk local headers and verify the deflated text entry.
        var offset = 0
        var found = false
        while offset + 30 <= data.count, data[offset] == 0x50, data[offset + 1] == 0x4B, data[offset + 2] == 0x03 {
            func le16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
            func le32(_ at: Int) -> Int { le16(at) | le16(at + 2) << 16 }
            let method = le16(offset + 8)
            let crc = UInt32(le32(offset + 14))
            let compressed = le32(offset + 18)
            let uncompressed = le32(offset + 22)
            let nameLength = le16(offset + 26)
            let name = String(decoding: data[(offset + 30)..<(offset + 30 + nameLength)], as: UTF8.self)
            let payloadStart = offset + 30 + nameLength
            let payload = data[payloadStart..<(payloadStart + compressed)]
            if name == "资料/说明.txt" {
                XCTAssertEqual(method, 8)
                XCTAssertLessThan(compressed, uncompressed)
                var output = Data(count: uncompressed)
                let decoded = output.withUnsafeMutableBytes { destination in
                    Data(payload).withUnsafeBytes { source in
                        compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, uncompressed,
                                                  source.bindMemory(to: UInt8.self).baseAddress!, compressed, nil, COMPRESSION_ZLIB)
                    }
                }
                XCTAssertEqual(decoded, text.count)
                XCTAssertEqual(output, text)
                XCTAssertEqual(crc, CRC32.checksum(text))
                found = true
            }
            offset = payloadStart + compressed
        }
        XCTAssertTrue(found)
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".ytools-zip-") }
        XCTAssertTrue(leftovers.isEmpty, "Temporary archives are moved into place")
    }
}
