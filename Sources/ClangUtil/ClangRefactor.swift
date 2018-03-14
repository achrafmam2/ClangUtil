import Foundation
import Clang
import cclang

public enum RefactoringError: Error {
  case noReferenceFound
}

func renameIdentifier(_ identifier: IdentifierToken,
                      in unit: TranslationUnit,
                      with name: String) throws -> UnsavedFile {
  let identifierSpelling = identifier.spelling(in: unit)
  guard let identifierCursorReferenced =
    identifier.location(in: unit).cursor(in: unit)?.referenced else {
      throw RefactoringError.noReferenceFound
  }

  // TODO: Handle error instead of crashing.
  var contents = try! String(contentsOfFile: unit.spelling, encoding: .utf8)

  let tokens = unit.tokens(in: unit.cursor.range)
  tokens.flatMap { (token) -> SourceRange? in
    let tokenSpelling = token.spelling(in: unit)
    guard let cursorReferenced =
      token.location(in: unit).cursor(in: unit)?.referenced else {
        return nil
    }

    // Return range to update if same spelling, and both the referenced cursors
    // are equal.
    if identifierSpelling == tokenSpelling &&
      identifierCursorReferenced == cursorReferenced {
      return token.range(in: unit)
    }

    return nil
  }.enumerated().forEach { (idx, range) in
    // Each deletion incur a shift of original indexes.
    let delta = (name.count - identifierSpelling.count) * idx
    let first = contents.startIndex
    let start = contents.index(first, offsetBy: range.start.offset + delta)
    let end = contents.index(first, offsetBy: range.end.offset + delta)

    contents.replaceSubrange(start..<end, with: name)
  }

  return UnsavedFile(filename: unit.spelling, contents: contents)
}

func WhileToFor(in unit: TranslationUnit) -> UnsavedFile {
  let whitespaces = "[ \t]*"
  let whileStmt = "while" + whitespaces + "\\(([^\n]+)\\)"
  let whileStmtRegex = try! NSRegularExpression(pattern: whileStmt)

  // TODO: Handle error instead of crashing.
  var contents = try! String(contentsOfFile: unit.spelling, encoding: .utf8)

  let range = NSRange(location: 0, length: contents.utf8.count)
  contents =
    whileStmtRegex.stringByReplacingMatches(in: contents,
                                            options: [],
                                            range: range,
                                            withTemplate: "for (;$1;)")

  return UnsavedFile(filename: unit.spelling, contents: contents)
}


