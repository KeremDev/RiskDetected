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
            return "Normal"
        case .simulator:
            return "Simülatör"
        case .warning:
            return "Uyarı"
        }
    }

    var userMessage: String {
        switch status {
        case .trusted:
            return "Cihaz bütünlüğü kontrollerinde olağan dışı bir bulgu yok."
        case .simulator:
            return "Uygulama simülatörde çalışıyor; cihaz bütünlüğü kontrolleri üretim cihazı gibi değerlendirilmez."
        case .warning(let signals):
            return "Bu cihazda güvenliği etkileyebilecek sistem değişikliği sinyalleri var: \(signals.joined(separator: ", "))."
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
            signals.append("jailbreak dosya izi")
        }

        if canWriteOutsideSandbox() {
            signals.append("sandbox dışı yazma")
        }

        if getenv("DYLD_INSERT_LIBRARIES") != nil {
            signals.append("dinamik kütüphane enjeksiyonu")
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
