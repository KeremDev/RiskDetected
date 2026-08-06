import Foundation

struct DeviceIntegrityAssessment: Equatable {
    enum Status: Equatable {
        case trusted
        case simulator
        case warning([String])
    }

    let status: Status

    var isWarning: Bool {
        if case .warning = status { return true }
        return false
    }

    var profileDetail: String {
        switch status {
        case .trusted:
            return RDLocalization.string("localizable.device.integrity.service.normal.6f420d9c", table: .localizable, fallback: "Normal")
        case .simulator:
            return RDLocalization.string("localizable.device.integrity.service.simulator.68f12768", table: .localizable, fallback: "Simülatör")
        case .warning:
            return RDLocalization.string("localizable.device.integrity.service.uyari.1a4db2ea", table: .localizable, fallback: "Uyarı")
        }
    }

    var userMessage: String {
        switch status {
        case .trusted:
            return RDLocalization.string("localizable.device.integrity.service.cihaz.butunlugu.kontrollerinde.olagan.disi.bir.b.69e3c877", table: .localizable, fallback: "Cihaz bütünlüğü kontrollerinde olağan dışı bir bulgu yok.")
        case .simulator:
            return RDLocalization.string("localizable.device.integrity.service.uygulama.simulatorde.calisiyor.cihaz.butunlugu.k.90b7dfa6", table: .localizable, fallback: "Uygulama simülatörde çalışıyor; cihaz bütünlüğü kontrolleri üretim cihazı gibi değerlendirilmez.")
        case .warning(let signals):
            return RDLocalization.format("localizable.device.integrity.service.bu.cihazda.guvenligi.etkileyebilecek.sistem.degi.45c28170", table: .localizable, fallback: "Bu cihazda güvenliği etkileyebilecek sistem değişikliği sinyalleri var: %1$@.", arguments: [String(describing: signals.joined(separator: ", "))])
        }
    }
}

enum DeviceIntegrityService {
    static func assess() -> DeviceIntegrityAssessment {
        #if DEBUG
        if isForcedWarningForUITests {
            return DeviceIntegrityAssessment(status: .warning(["UI test sinyali"]))
        }
        #endif

        #if targetEnvironment(simulator)
        return DeviceIntegrityAssessment(status: .simulator)
        #else
        var signals: [String] = []

        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt"
        ]
        if suspiciousPaths.contains(where: FileManager.default.fileExists(atPath:)) {
            signals.append(RDLocalization.string("localizable.device.integrity.service.jailbreak.dosya.izi.9b7f9c3c", table: .localizable, fallback: "jailbreak dosya izi"))
        }

        if canWriteOutsideSandbox() {
            signals.append(RDLocalization.string("localizable.device.integrity.service.sandbox.disi.yazma.ec3e1b78", table: .localizable, fallback: "sandbox dışı yazma"))
        }

        if getenv("DYLD_INSERT_LIBRARIES") != nil {
            signals.append(RDLocalization.string("localizable.device.integrity.service.dinamik.kutuphane.enjeksiyonu.08bfa91a", table: .localizable, fallback: "dinamik kütüphane enjeksiyonu"))
        }

        return signals.isEmpty
            ? DeviceIntegrityAssessment(status: .trusted)
            : DeviceIntegrityAssessment(status: .warning(signals))
        #endif
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/riskdetected_integrity_check.txt"
        do {
            try "riskdetected".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    #if DEBUG
    private static var isForcedWarningForUITests: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_DEVICE_INTEGRITY_WARNING")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"] == "1"
    }
    #endif
}
