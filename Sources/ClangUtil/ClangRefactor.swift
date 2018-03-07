import Clang
import cclang

func renameIdentifier(_ identifier: IdentifierToken,
                      in unit: TranslationUnit,
                      with name: String) -> [String] {
  let identifierSpelling = identifier.spelling(in: unit)
  let identifierCursorReferenced = clang_getCursorReferenced(
    clang_getCursor(unit.asClang(), identifier.location(in: unit).asClang()))

  let tokens = unit.tokens(in: unit.cursor.range)
  return tokens.map { token in
    let tokenSpelling = token.spelling(in: unit)
    let cursorReferenced = clang_getCursorReferenced(
      clang_getCursor(unit.asClang(), token.location(in: unit).asClang()))

    // Return new name if same spelling, and both the referenced cursors are
    // equal.
    if identifierSpelling == tokenSpelling &&
      clang_equalCursors(identifierCursorReferenced, cursorReferenced) != 0 {
      return name
    }

    return tokenSpelling
  }
}


