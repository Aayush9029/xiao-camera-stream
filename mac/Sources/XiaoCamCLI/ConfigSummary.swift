struct ConfigSummary: Encodable {
    var mode: String
    var width: Int
    var height: Int
    var settings: [String: Int]
}
