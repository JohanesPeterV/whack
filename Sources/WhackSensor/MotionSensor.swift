import Foundation
import IOKit
import IOKit.hid
import WhackCore

public enum SensorError: LocalizedError {
    case unavailable, accessDenied(Int32), failed(Int32), noSamples
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "No compatible motion sensor was found. Sound previews still work. Try again on a supported MacBook."
        case .accessDenied: return "macOS denied access to the motion sensor. This build supports direct sensor access only. You can still preview and manage sounds."
        case .failed(let code): return String(format: "The motion sensor couldn’t start (0x%08x). Try again, or reopen Whack after waking your Mac.", code)
        case .noSamples: return "The motion sensor isn’t sending data. Try again, or reopen Whack after waking your Mac."
        }
    }
}

/// All methods and callbacks run on the main run loop. Opens only the accelerometer;
/// no microphone, keyboard monitoring, private framework, or elevated process.
public final class MotionSensor {
    public var onSample: ((MotionSample) -> Void)?
    public var onError: ((Error) -> Void)?
    public private(set) var sampleCount = 0
    private var device: IOHIDDevice?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var driver: io_service_t = 0
    private var savedProperties: [String: CFTypeRef] = [:]

    public init() {}

    public func start() throws {
        precondition(Thread.isMainThread)
        stop()
        sampleCount = 0
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator)
        guard result == KERN_SUCCESS else { throw SensorError.failed(result) }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard isAccelerometer(service), let candidate = IOHIDDeviceCreate(nil, service) else { continue }
            let status = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else { throw sensorError(status) }
            device = candidate
            do { try enableReporting() }
            catch { stop(); throw error }
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            buffer = bytes
            IOHIDDeviceRegisterInputReportCallback(candidate, bytes, 4096, { context, result, _, _, _, bytes, count in
                guard let context else { return }
                let sensor = Unmanaged<MotionSensor>.fromOpaque(context).takeUnretainedValue()
                guard result == kIOReturnSuccess else {
                    sensor.onError?(SensorError.failed(result)); return
                }
                guard count == 22, let sample = MotionSample.decode(Array(UnsafeBufferPointer(start: bytes, count: count)),
                                                                    time: ProcessInfo.processInfo.systemUptime) else { return }
                sensor.sampleCount += 1
                sensor.onSample?(sample)
            }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        throw SensorError.unavailable
    }

    public func stop() {
        precondition(Thread.isMainThread)
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
        buffer?.deallocate(); buffer = nil
        if driver != 0 {
            for (key, value) in savedProperties { IORegistryEntrySetCFProperty(driver, key as CFString, value) }
            IOObjectRelease(driver)
        }
        driver = 0; savedProperties.removeAll()
    }

    private func isAccelerometer(_ service: io_service_t) -> Bool {
        let page = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, nil, 0)?.takeRetainedValue() as? Int
        let usage = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, nil, 0)?.takeRetainedValue() as? Int
        return page == 0xff00 && usage == 3
    }

    private func enableReporting() throws {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator)
        guard result == KERN_SUCCESS else { throw SensorError.failed(result) }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            guard isAccelerometer(service) else { IOObjectRelease(service); continue }
            driver = service
            for (key, value) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
                if let existing = IORegistryEntryCreateCFProperty(service, key as CFString, nil, 0)?.takeRetainedValue() {
                    savedProperties[key] = existing
                } else {
                    savedProperties[key] = 0 as CFNumber
                }
                let status = IORegistryEntrySetCFProperty(service, key as CFString, value as CFNumber)
                guard status == kIOReturnSuccess else { throw sensorError(status) }
            }
            return
        }
        throw SensorError.unavailable
    }

    private func sensorError(_ status: IOReturn) -> SensorError {
        if status == kIOReturnNotPrivileged || status == kIOReturnNotPermitted { return .accessDenied(status) }
        return .failed(status)
    }
}
