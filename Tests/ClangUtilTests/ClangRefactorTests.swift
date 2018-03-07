import Clang
import Foundation
import XCTest
import cclang
@testable import ClangUtil

class ClangRefactorTests: XCTestCase {
  func testRename() {
    let src = """
      struct A {};
      struct B {};
      int main(void) {
        struct A {
          int data;
          struct A *next;
        };
        int a;
        a = 0;
        struct A my;
        struct B not;
        return 0;
      }
"""
    let unit = try! TranslationUnit(clangSource: src, language: .c)
    let tokens = unit.tokens(in: unit.cursor.range)
    XCTAssertEqual(
      renameIdentifier(tokens[17] as! IdentifierToken, in: unit, with: "List"),
      ["struct", "A", "{", "}", ";", "struct", "B", "{", "}", ";", "int",
       "main", "(", "void", ")", "{", "struct", "List", "{", "int", "data", ";",
       "struct", "List", "*", "next", ";", "}", ";", "int", "a", ";", "a", "=",
       "0", ";", "struct", "List", "my", ";", "struct", "B", "not", ";",
       "return", "0", ";", "}"]
    )
  }
}
