// swiftc VoidLink/Utility/NativeStreamResolution.swift \
//   BuildScripts/check-native-resolution.swift -o /path/to/check-native-resolution
// /path/to/check-native-resolution
import Foundation
import CoreGraphics

@main
enum NativeStreamResolutionTests {
    static func main() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 2669, height: 1878), CGSize(width: 2668, height: 1878)),
            (CGSize(width: 2853, height: 2007), CGSize(width: 2852, height: 2006)),
            (CGSize(width: 1398, height: 2034), CGSize(width: 1398, height: 2034)),
            (CGSize(width: 1920, height: 1080), CGSize(width: 1920, height: 1080)),
            (CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1920)),
            (CGSize(width: 2669.9, height: 1878.8), CGSize(width: 2668, height: 1878)),
            (.zero, .zero),
            (CGSize(width: -1, height: 1080), .zero),
            (CGSize(width: CGFloat.nan, height: 1080), .zero),
            (CGSize(width: CGFloat.infinity, height: 1080), .zero)
        ]
        for (input, expected) in cases {
            let actual = NativeStreamResolution.alignedSize(input)
            precondition(actual == expected, "\(input) → \(actual), expected \(expected)")
        }
        print("PASS: \(cases.count) native-resolution alignment cases")
    }
}
