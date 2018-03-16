import Clang
import Foundation
import XCTest
import cclang
@testable import ClangUtil

class ClangRefactorTests: XCTestCase {
  func testRename() {
    let testCases = [
      ("testFiles/rename-0.c",
       "testFiles/rename-golden-0.c",
       17,
       "List"
      ),

      ("testFiles/rename-1.c",
       "testFiles/rename-golden-1.c",
       1,
       "List"
      ),

      ("testFiles/rename-2.c",
       "testFiles/rename-golden-2.c",
       21,
       "j"
      ),
    ]

    for testCase in testCases {
      let filename = testCase.0
      let golden = testCase.1
      let identifierIdx = testCase.2
      let new = testCase.3

      let unit = try! TranslationUnit(filename: filename)
      let tokens = unit.tokens(in: unit.cursor.range)
      let identifier = tokens[identifierIdx] as! IdentifierToken
      let unsavedFile = try! renameIdentifier(identifier, in: unit, with: new)
      XCTAssertEqual(
        unsavedFile.contents,
        try! String(contentsOfFile: golden)
      )
    }
  }

  func testWhileToFor() {
    let testCases = [
      ("testFiles/whileToFor-0.c",
       "testFiles/whileToFor-golden-0.c"
      ),
      ]

    for testCase in testCases {
      let filename = testCase.0
      let golden = testCase.1

      let unit = try! TranslationUnit(filename: filename)
      let unsavedFile = WhileToFor(in: unit)
      XCTAssertEqual(
        unsavedFile.contents,
        try! String(contentsOfFile: golden)
      )
    }
  }

  func testGetFunctionDeclarations() {
    let testCases = [
      ("testFiles/get-decls.c",
       ["int main(int, char *[])", "int add(int, int)", "int abs(int)",
        "void print()"]
      ),
      ]

    for testCase in testCases {
      let filename = testCase.0

      let unit = try! TranslationUnit(filename: filename)
      XCTAssertEqual(
        getFunctionDeclarations(in: unit).sorted(),
        testCase.1.sorted()
      )
    }
  }
}
