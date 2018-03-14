import Clang
import Foundation
import XCTest
import MongoKitten
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

  func testInit() {
    XCTAssertNoThrow(try ClangProcessor(src: "int main() {}", language: .c))
    XCTAssertThrowsError(
      try ClangProcessor(src: "int main() {return 0}", language: .c)) { error in
        XCTAssertTrue(error is CompilationError)
    }
  }

  func testTokenization() {
    do {
      let processor = try ClangProcessor(src: "int main() {}", language: .c)
      XCTAssertEqual(
        processor.tokens().map {$0.spelling(in: processor.unit)},
        ["int", "main", "(", ")", "{", "}"]
      )
      XCTAssertEqual(
        processor.tokens {!($0 is PunctuationToken)}
                 .map {$0.spelling(in: processor.unit)},
        ["int", "main"]
      )
    } catch {
      XCTFail("\(error)")
    }
  }

  func testKGrams() {
    do {
      let processor = try ClangProcessor(src: "int main() {}", language: .c)
      let tokens = processor.tokens()
      let kgrams = processor.kgrams(tokens: tokens, windowSize: 5)
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
      let processor = try ClangProcessor(src: src, language: .c)
      let tokens = processor.tokens()
      let kgrams = processor.kgrams(tokens: tokens, windowSize: 5)
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
      let processor = try ClangProcessor(fileURL:
        URL(fileURLWithPath: "testFiles/prog-0.c"))
      let ast = processor.flattenAst()
      XCTAssertEqual(
        processor.describeAst(ast: ast),
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
      let processor = try ClangProcessor(fileURL:
        URL(fileURLWithPath: "testFiles/prog-0.c"))
      XCTAssertEqual(
        processor.astDump(),
        try! String(contentsOfFile: "testFiles/prog-0-ast-dump.in")
      )
    } catch {
      XCTFail("\(error)")
    }
  }
}
