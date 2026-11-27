import CasePaths
import Foundation

@CasePathable
public enum PhotoCaptureState: Equatable, Sendable {
    case idle
    case capturing
    case saved(URL)
    case failed(String)
}
