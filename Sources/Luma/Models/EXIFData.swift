import Foundation

struct EXIFData: Codable, Hashable {
    let captureDate: Date
    let gpsCoordinate: Coordinate?
    let focalLength: Double?
    let aperture: Double?
    let shutterSpeed: String?
    let iso: Int?
    let cameraModel: String?
    let lensModel: String?
    let imageWidth: Int
    let imageHeight: Int

    static let empty = EXIFData(
        captureDate: .distantPast,
        gpsCoordinate: nil,
        focalLength: nil,
        aperture: nil,
        shutterSpeed: nil,
        iso: nil,
        cameraModel: nil,
        lensModel: nil,
        imageWidth: 0,
        imageHeight: 0
    )
}
