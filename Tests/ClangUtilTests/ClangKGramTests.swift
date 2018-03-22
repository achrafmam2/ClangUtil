import Foundation
import Clang
import XCTest
import MongoKitten
@testable import ClangUtil


class ClangKgramTests: XCTestCase {
  func testDocumentConversion() {
    do {
      let unit = try TranslationUnit(clangSource: "int main() {}", language: .c)
      let tokens = unit.tokens(in: unit.cursor.range)
      let kgrams = getNgrams(in: unit, tokens: tokens, windowSize: 6)
      XCTAssertEqual(kgrams.count, 1)
      XCTAssertNotNil(kgrams[0].document)
      XCTAssertEqual(
        kgrams[0].document!["tokens"] as! String,
        "keyword identifier punctuation punctuation punctuation punctuation")
    } catch {
      XCTFail("\(error)")
    }
  }
}
