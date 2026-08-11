import Testing

@testable import Vega

struct ProductBarcodeTests {
    @Test(arguments: [
        ("96385074", ProductBarcode.Format.ean8),
        ("012345678905", ProductBarcode.Format.upcA),
        ("5901234123457", ProductBarcode.Format.ean13),
        ("10012345000017", ProductBarcode.Format.gtin14),
    ])
    func acceptsServerSupportedBarcodeLengths(
        _ candidate: String,
        _ expectedFormat: ProductBarcode.Format
    ) throws {
        let barcode = try #require(ProductBarcode("  \(candidate)\n"))

        #expect(barcode.value == candidate)
        #expect(barcode.format == expectedFormat)
    }

    @Test(arguments: [
        "1234567",
        "123456789",
        "12345678901",
        "123456789012345",
        "590123412345x",
        "",
    ])
    func rejectsValuesTheServerDoesNotTreatAsBarcodes(_ candidate: String) {
        #expect(ProductBarcode(candidate) == nil)
    }

    @Test
    func scanGateAcceptsOnlyTheFirstValidRecognition() throws {
        var gate = BarcodeScanGate()
        let acceptedBarcode = gate.accept("5901234123457")

        #expect(try #require(acceptedBarcode).value == "5901234123457")
        #expect(gate.accept("10012345000017") == nil)
        #expect(gate.acceptedBarcode?.value == "5901234123457")
    }
}
