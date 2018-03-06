import Foundation
import XCTest
import MongoKitten
@testable import ClangUtil


class ClangKgramTests: XCTestCase {
  func testDocumentConversion() {
    let processor = try! ClangProcessor(src: "int main() {}", language: .c)
    let kgrams = processor.kgrams(tokens: processor.tokens(), windowSize: 6)
    XCTAssertEqual(kgrams.count, 1)
    XCTAssertNotNil(kgrams[0].document)
    XCTAssertEqual(
      kgrams[0].document!["tokens"] as! String,
      "keyword identifier punctuation punctuation punctuation punctuation")
  }
}
