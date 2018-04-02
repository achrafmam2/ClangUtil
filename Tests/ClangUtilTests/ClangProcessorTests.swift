import Clang
import Foundation
import XCTest
//import MongoKitten
import cclang
@testable import ClangUtil


class ArraySlicingTests: XCTestCase {
  func testSlicing() {
    // The array [1, 2, 3] and window size of 2 should give [[1, 2], [2, 3]].
    XCTAssertTrue([1, 2, 3].slices(ofSize: 2)
      .elementsEqual([[1, 2], [2, 3]]) {$0 == $1})

    // Size of the window bigger than actual array.
    XCTAssertTrue([1, 2, 3].slices(ofSize: 5)
      .elementsEqual([[1, 2, 3]], by: {$0 == $1}))
  }
}

class ClangProcessorTests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testNGrams() {
    do {
      let unit = try TranslationUnit(clangSource: "int main() {}", language: .c)
      let tokens = unit.tokens(in: unit.cursor.range)
      let kgrams = getNgrams(in: unit, tokens: tokens, windowSize: 5)
      XCTAssertEqual(kgrams.count, 2)
      XCTAssertEqual(
        kgrams[0].tokens.map {$0.spelling(in: kgrams[0].unit)},
        ["int", "main", "(", ")", "{",]
      )
      XCTAssertEqual(
        kgrams[1].tokens.map {$0.spelling(in: kgrams[0].unit)},
        ["main", "(", ")", "{", "}"]
      )
    } catch {
      XCTFail("\(error)")
    }
  }

  func testReduce() {
    do {
      let src = "int main(void) {int a;}"
      let unit = try TranslationUnit(clangSource: src, language: .c)
      let tokens = unit.tokens(in: unit.cursor.range)
      let kgrams = getNgrams(in: unit, tokens: tokens, windowSize: 5)
      XCTAssertEqual(kgrams.count, 6)
      let fingerprints = kgrams.winnow(using: 3)
      XCTAssertEqual(fingerprints.count, 4)
    } catch {
      XCTFail("\(error)")
    }
  }

  func testFlattenAst() {
    // Test will fail if run from Xcode. Use swift test command from the root
    // project folder.
    do {
      let unit = try TranslationUnit(filename: "testFiles/prog-0.c")
      XCTAssertEqual(
        describeAst(root: unit.cursor),
        ["FunctionDecl", "CompoundStmt", "CallExpr", "StringLiteral",
         "ReturnStmt", "IntegerLiteral"])
    } catch {
      XCTFail("\(error)")
    }
  }

  func testPrintAst() {
    // Test will fail if run from Xcode. Use swift test command from the root
    // project folder.
    do {
      let unit = try TranslationUnit(filename: "testFiles/prog-0.c")
      XCTAssertEqual(
        astDump(root: unit.cursor),
        try! String(contentsOfFile: "testFiles/prog-0-ast-dump.in")
      )
    } catch {
      XCTFail("\(error)")
    }
  }
}
