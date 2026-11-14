import XCTest
@testable import ComposeKit

final class ComposeKitTests: XCTestCase {
    func testAllComposeActionCases() {
        let actions: [ComposeAction] = [
            .rotate(deg: 3.5, clockwise: false),
            .holdVertical,
            .lowerPhone,
            .stepBack(steps: 1),
            .stepForward(steps: 2),
            .panLeft,
            .panRight,
            .tiltUp,
            .tiltDown,
            .switchZoom(factor: 2.0),
            .enableFill,
            .cleanLens,
            .moveToShade,
            .turnSubject(deg: 45.0),
            .useNightMode,
            .good
        ]
        XCTAssertEqual(actions.count, 16)

        // FFI mapping parity for all 16 cases
        XCTAssertEqual(ComposeAction(ffi: .rotate(deg: 3.5, clockwise: false)), .rotate(deg: 3.5, clockwise: false))
        XCTAssertEqual(ComposeAction(ffi: .holdVertical), .holdVertical)
        XCTAssertEqual(ComposeAction(ffi: .lowerPhone), .lowerPhone)
        XCTAssertEqual(ComposeAction(ffi: .stepBack(steps: 1)), .stepBack(steps: 1))
        XCTAssertEqual(ComposeAction(ffi: .stepForward(steps: 2)), .stepForward(steps: 2))
        XCTAssertEqual(ComposeAction(ffi: .panLeft), .panLeft)
        XCTAssertEqual(ComposeAction(ffi: .panRight), .panRight)
        XCTAssertEqual(ComposeAction(ffi: .tiltUp), .tiltUp)
        XCTAssertEqual(ComposeAction(ffi: .tiltDown), .tiltDown)
        XCTAssertEqual(ComposeAction(ffi: .switchZoom(factor: 2.0)), .switchZoom(factor: 2.0))
        XCTAssertEqual(ComposeAction(ffi: .enableFill), .enableFill)
        XCTAssertEqual(ComposeAction(ffi: .cleanLens), .cleanLens)
        XCTAssertEqual(ComposeAction(ffi: .moveToShade), .moveToShade)
        XCTAssertEqual(ComposeAction(ffi: .turnSubject(deg: 45.0)), .turnSubject(deg: 45.0))
        XCTAssertEqual(ComposeAction(ffi: .useNightMode), .useNightMode)
        XCTAssertEqual(ComposeAction(ffi: .good), .good)
    }

    func testComposeSeverityAndAudience() {
        XCTAssertEqual(ComposeSeverity(ffi: .good), .good)
        XCTAssertEqual(ComposeSeverity(ffi: .minor), .minor)
        XCTAssertEqual(ComposeSeverity(ffi: .major), .major)
        XCTAssertEqual(ComposeSeverity(ffi: .critical), .critical)
        XCTAssertTrue(ComposeSeverity.minor < ComposeSeverity.major)

        XCTAssertEqual(ComposeAudience(ffi: .photographer), .photographer)
        XCTAssertEqual(ComposeAudience(ffi: .subject), .subject)
    }

    func testComposeHintAndTypealias() {
        let hint = ComposeHint(primary: "Primary", secondary: "Secondary", spoken: "Spoken")
        XCTAssertEqual(hint.primary, "Primary")
        XCTAssertEqual(hint.secondary, "Secondary")
        XCTAssertEqual(hint.spoken, "Spoken")

        let alias: HintItem = hint
        XCTAssertEqual(alias.primary, "Primary")

        let ffiHint = HintItemFfi(primary: "P", secondary: "S", spoken: "Spk")
        let fromFfi = ComposeHint(ffi: ffiHint)
        XCTAssertEqual(fromFfi.primary, "P")
        XCTAssertEqual(fromFfi.secondary, "S")
        XCTAssertEqual(fromFfi.spoken, "Spk")
    }

    func testComposeFindingAndOutputExpandedFields() {
        let finding = ComposeFinding(
            id: "tilt.level",
            severity: .major,
            audience: .photographer,
            primaryAction: .rotate(deg: 2.5, clockwise: true),
            secondaryAction: nil,
            hintKey: "rotate_cw",
            hint: ComposeHint(primary: "Rotate", secondary: "", spoken: "Rotate"),
            hintText: "Rotate",
            value: 2.5,
            target: 0.0
        )
        XCTAssertEqual(finding.id, "tilt.level")
        XCTAssertEqual(finding.value, 2.5)
        XCTAssertEqual(finding.target, 0.0)

        // Backwards-compatible init
        let compatFinding = ComposeFinding(id: "tilt.level", severity: .major, hintKey: "rotate_cw")
        XCTAssertEqual(compatFinding.id, "tilt.level")
        XCTAssertEqual(compatFinding.severity, .major)

        // Expanded ComposeOutput
        let output = ComposeOutput(
            activeFindingId: "tilt.level",
            severity: .major,
            audience: .photographer,
            primaryAction: .rotate(deg: 2.5, clockwise: true),
            secondaryAction: nil,
            value: 2.5,
            target: 0.0,
            hintKey: "rotate_cw",
            hint: ComposeHint(primary: "Rotate", secondary: "", spoken: "Rotate"),
            hintText: "Rotate",
            isGoodToShoot: false,
            rawFindingsCount: 1
        )
        XCTAssertEqual(output.activeFindingId, "tilt.level")
        XCTAssertEqual(output.severity, .major)
        XCTAssertEqual(output.value, 2.5)
        XCTAssertEqual(output.target, 0.0)
        XCTAssertFalse(output.isGoodToShoot)

        // Backwards-compatible output init
        let compatOutput = ComposeOutput(
            activeFindingId: "test",
            hintKey: "test",
            isGoodToShoot: true,
            rawFindingsCount: 0
        )
        XCTAssertEqual(compatOutput.activeFindingId, "test")
        XCTAssertTrue(compatOutput.isGoodToShoot)
    }
}
