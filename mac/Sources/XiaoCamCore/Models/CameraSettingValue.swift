public struct CameraSettingValue: Codable, Equatable, Hashable, Sendable {
    public var setting: CameraSetting
    public var value: Int

    public init(setting: CameraSetting, value: Int) {
        self.setting = setting
        self.value = value
    }
}
