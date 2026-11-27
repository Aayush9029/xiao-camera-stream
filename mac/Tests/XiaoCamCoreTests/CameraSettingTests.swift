import CustomDump
import Testing
import XiaoCamCore

struct CameraSettingTests {
    @Test func parsesAssignments() throws {
        let values = try CameraSetting.parse(assignments: ["brightness=1", "contrast=-2", "ae_level=0", "vflip=off"])
        expectNoDifference(values, [
            CameraSettingValue(setting: .brightness, value: 1),
            CameraSettingValue(setting: .contrast, value: -2),
            CameraSettingValue(setting: .aeLevel, value: 0),
            CameraSettingValue(setting: .vflip, value: 0),
        ])
    }

    @Test func rejectsValuesOutsideTheFirmwareRange() {
        #expect(throws: CameraSettingError.outOfRange(setting: .brightness, value: 4)) {
            try CameraSetting.parse(assignment: "brightness=4")
        }
        #expect(throws: CameraSettingError.outOfRange(setting: .saturation, value: -5)) {
            try CameraSetting.parse(assignment: "saturation=-5")
        }
        #expect(throws: CameraSettingError.outOfRange(setting: .denoise, value: 9)) {
            try CameraSetting.parse(assignment: "denoise=9")
        }
        #expect(throws: CameraSettingError.outOfRange(setting: .framesize, value: 20)) {
            try CameraSetting.parse(assignment: "framesize=20")
        }
    }

    @Test func acceptsTheRangeEnds() throws {
        for setting in CameraSetting.allCases {
            #expect(try setting.validate(setting.range.lowerBound).value == setting.range.lowerBound)
            #expect(try setting.validate(setting.range.upperBound).value == setting.range.upperBound)
        }
    }

    @Test func rejectsBadInput() {
        #expect(throws: CameraSettingError.unknownKey("iso")) { try CameraSetting.parse(assignment: "iso=100") }
        #expect(throws: CameraSettingError.malformed("brightness")) { try CameraSetting.parse(assignment: "brightness") }
        #expect(throws: CameraSettingError.notANumber(key: "contrast", value: "high")) {
            try CameraSetting.parse(assignment: "contrast=high")
        }
        #expect(throws: CameraSettingError.notANumber(key: "brightness", value: "on")) {
            try CameraSetting.parse(assignment: "brightness=on")
        }
        #expect(throws: CameraSettingError.duplicate(.contrast)) {
            try CameraSetting.parse(assignments: ["contrast=1", "contrast=2"])
        }
        #expect(throws: CameraSettingError.empty) { try CameraSetting.parse(assignments: []) }
    }

    @Test func readsToggleWords() throws {
        #expect(try CameraSetting.parse(assignment: "night_mode=on").value == 1)
        #expect(try CameraSetting.parse(assignment: "hmirror=TRUE").value == 1)
        #expect(try CameraSetting.parse(assignment: "aec2=0").value == 0)
    }
}
