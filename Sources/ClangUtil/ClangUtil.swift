import Clang
import Foundation
import cclang

extension Array {
  /// Returns all slices of size `w`.
  /// - Parameter w: The size of the slices.
  /// - Returns: An array of slices.
  /// - Note: If the size `w` is bigger than the count of the array, then
  ///           returns the whole array.
  public func slices(ofSize w: Int) -> [ArraySlice<Element>] {
    if self.count < w {
      return [self[...]]
    }
    // `lastIdx` is the last index where it is still possible to have a window
    // of size `w` (e.g., `lastIdx` + `w` - 1 <= self.count).
    let lastIdx = self.count - w
    return (0...lastIdx).map { idx in self[idx..<(idx + w)] }
  }
}

// Make Arrays conform to Hashable protocol.
// Only Arrays whose Elements can be transformed to String.
extension Array where Element: CustomStringConvertible {
  /// Returns hash value for an array.
  /// - Requires: elements of the array has to conform to the `CustomStringConvertible`
  ///             protocol.
  var hashValue: Int {
    // djb2hash
    return self.reduce("") {
      $0 + "\($1)"
      }.djb2hash
  }
}

extension String {
  /// hash(0) = 5381
  /// hash(i) = hash(i - 1) * 33 ^ str[i];
  var djb2hash: Int {
    let unicodeScalars = self.unicodeScalars.map { $0.value }
    return unicodeScalars.reduce(5381) {
      ($0 << 5) &+ $0 &+ Int($1)
    }
  }
}

/// Tells if translation unit has a errors.
/// - parameter unit: The translation to check errors in.
/// - returns: `True` if `unit` has errors, `False` otherwise.
public func hasCompilationError(in unit: TranslationUnit) -> Bool {
  for diagnostic in unit.diagnostics {
    if diagnostic.severity == .error {
      return true
    }
  }
  return false
}

/// Function type for cursor filtering.
/// - Parameter cursor: A Cursor type.
/// - Returns: True or False.
public typealias CursorPredicate = (_ cursor: Cursor) -> Bool

/// Default Cursor Predicate function. Filters unimportant cursors for
/// plagiarism checking.
/// Undesired Cursor kinds are:
///   - CXCursor_TypeRef
///   - CXCursor_UnexposedExpr
///   - CXCursor_UnexposedStmt
///   - CXCursor_UnexposedDecl
///   - CXCursor_DeclRefExpr
public let defaultCursorPredicate: CursorPredicate = { cursor in
  let undesiredCursorKinds = [
    CXCursor_TypeRef,
    CXCursor_UnexposedExpr,
    CXCursor_UnexposedStmt,
    CXCursor_UnexposedDecl,
    CXCursor_DeclRefExpr,
    ]

  let cursorKind = clang_getCursorKind(cursor.asClang())
  return !undesiredCursorKinds.contains(cursorKind)
}

/// Flattens the AST using a preorder traversal.
/// - Parameter isIncluded: A function that says wether to include a cursor or
///     not in the final result. Default is `defaultCursorPredicate` function.
/// - Returns: An array of cursors.
/// - Note: Declaratations that are imported using #include directives are
///     excluded.
public func flattenAst(in unit: TranslationUnit,
                       isIncluded: CursorPredicate = defaultCursorPredicate) -> [Cursor] {
  var ast = [Cursor]()
  unit.visitChildren { cursor in
    // Ignore declarations that are not part of the source code.
    // When a code includes a library (e.g., #include <stdio.h>) lot of
    // declarations are brought by the preprocesor which is noise when
    // checking for plagiarism.
    let location = cursor.range.start.asClang()
    if clang_Location_isFromMainFile(location) == 0 {
      return ChildVisitResult.continue
    }

    if isIncluded(cursor) {
      ast.append(cursor)
    }

    return ChildVisitResult.recurse
  }

  return ast
}

/// Extracts all kgrams from an array of tokens.
/// - Parameter tokens: An array of Clang tokens.
/// - Parameter windowSize: The length of the kgram.
/// - Returns: An array of ClangKgrams.
public func getNgrams(in unit: TranslationUnit,
                      tokens: [Token], windowSize w: Int) -> [ClangKGram] {
  if tokens.isEmpty {
    return []
  }

  return tokens.slices(ofSize: w).map { slice in
    ClangKGram(tokens: Array(slice), in: unit)
  }
}

/// Flattens and describe the AST using a preorder traversal.
/// Descriptions of the AST is based on the node's kind.
///
/// - Returns: An array of strings.
/// - Note: Declaratations that are imported using #include directives are
///     excluded.
public func describeAst(in unit: TranslationUnit) -> [String] {
  return flattenAst(in: unit).map { cursor in
    clang_getCursorKindSpelling(
      clang_getCursorKind(cursor.asClang())
      ).asSwift()
  }
}

func describeCursor(_ cursor: Cursor) -> String {
  let cursorKindSpelling = clang_getCursorKindSpelling(
    clang_getCursorKind(cursor.asClang())).asSwift()
  let type = cursor.type?.description ?? ""
  let line = cursor.range.start.line

  return "\(cursorKindSpelling) \(type) [\(line)]"
}

public func astDump(in unit: TranslationUnit,
                    isIncluded: @escaping CursorPredicate = defaultCursorPredicate) -> String {
  var astTree = ""

  func stringify(_ cursor: Cursor, forLevel level: Int) -> String {
    let dashes = [String](repeating: "-", count: level).reduce(""){$0 + $1}
    return "\(dashes)\(describeCursor(cursor))\n"
  }

  func dfs(_ cursor: Cursor, _ level: Int = 0) {
    let location = cursor.range.start.asClang()
    if clang_Location_isFromMainFile(location) == 0 {
      return
    }

    var adjust = 0
    if isIncluded(cursor) {
      astTree += stringify(cursor, forLevel: level)
      adjust = 1
    }

    for child in cursor.children() {
      dfs(child, level + adjust)
    }
  }

  dfs(unit.cursor)

  return astTree
}

extension Array where Element: Hashable {
  /// Reduces an array of ClangKgrams using the winnowing algorithm.
  /// See [paper](https://theory.stanford.edu/~aiken/publications/papers/sigmod03.pdf)
  /// for more details.
  /// - Parameter kgrams: An array of ClangKgrams.
  /// - Parameter windowSize: Length of the window used in the winnowing
  ///     algorithm.
  /// - Returns: An array of ClangKgrams.
  public func winnow(using w: Int) -> [Element] {
    if self.isEmpty {
      return []
    }

    var reduced = [Element]()
    self.slices(ofSize: w).forEach { slice in
      let smallest = slice.min { lhs, rhs in
        lhs.hashValue < rhs.hashValue
        }!
      if reduced.isEmpty || reduced.last! != smallest {
        reduced.append(smallest)
      }
    }

    return reduced
  }
}

extension CXString {
  /// Returns a string representation for the current CXString without disposing
  /// it.
  /// - Returns: A String or nil in case the current CXString is not valid.
  func asSwiftOptionalNoDispose() -> String? {
    guard self.data != nil else { return nil }
    guard let cStr = clang_getCString(self) else { return nil }
    let swiftStr = String(cString: cStr)
    return swiftStr.isEmpty ? nil : swiftStr
  }

  /// Returns a string representation for the current CXString, and disposes it.
  /// - Returns: A String or nil in case the current CXString is not valid.
  func asSwiftOptional() -> String? {
    defer { clang_disposeString(self) }
    return asSwiftOptionalNoDispose()
  }

  /// Returns a string representation for the current CXString.
  /// - Returns: A String.
  func asSwiftNoDispose() -> String {
    return asSwiftOptionalNoDispose() ?? ""
  }

  /// Returns a string representation for the current CXString.
  /// - Note: The current CXString will be disposed after this operation, use
  ///     `asSwiftNoDispose` if you still want to use the current CXString.
  /// - Returns: A String.
  public func asSwift() -> String {
    return asSwiftOptional() ?? ""
  }
}
