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

/// Represents possible errors when creating a `TranslationUnit` from a clang
/// source code.
enum TranslationUnitFromSourceError: Error {
  /// Temporary file could not be created error.
  case TemporaryFileCouldNotBeCreated(path: String)
}

/// Represents a Clang token.
public typealias ClangToken = Clang.Token

/// Returns generic token type name (e.g., comment, literal, punctuation ...).
/// - Parameter token: A ClangToken.
/// - Returns: token type.
func clangTokenTypeName(_ token: Token) -> String {
  if token is LiteralToken {
    return "literal"
  } else if token is CommentToken {
    return "comment"
  } else if token is PunctuationToken {
    return "punctuation"
  } else if token is KeywordToken {
    return "keyword"
  } else if token is IdentifierToken {
    return "identifier"
  }

  assertionFailure("\(token)'s type not deduced")

  return ""
}

/// Represents a Kgram of Clang tokens.
public struct ClangKGram: Hashable {
  /// A Kgram of (consecutive) Clang tokens.
  public let tokens: [ClangToken]

  /// The translation unit of where the tokens are present.
  let unit: TranslationUnit

  /// The start location of the kgram in the translation unit.
  public var start: SourceLocation? {
    guard let firstToken = tokens.first else {
      return nil
    }
    return firstToken.range(in: unit).start
  }

  /// The end location of the kgram in the translation unit.
  public var end: SourceLocation? {
    guard let lastToken = tokens.last else {
      return nil
    }
    return lastToken.range(in: unit).end
  }

  /// The number of elements in the kgram.
  public var count: Int {
    return tokens.count
  }

  /// Hash value of the kgram of tokens.
  public var hashValue: Int {
    return tokens.map { clangTokenTypeName($0) }.hashValue
  }

  /// Two kgrams are equal iff ...
  /// TODO: Think about kgram equality.
  public static func ==(lhs: ClangKGram, rhs: ClangKGram) -> Bool {
    let lhsTokenSpellings = lhs.tokens.map{$0.spelling(in: lhs.unit)}
    let rhsTokenSpellings = rhs.tokens.map{$0.spelling(in: rhs.unit)}
    return  lhsTokenSpellings == rhsTokenSpellings
  }

  /// Create a kgram from clang tokens and the translation uni where they
  /// reside.
  /// - Parameter tokens: The clang tokens.
  /// - Parameter in: The translation unit where they reside.
  public init(tokens: [ClangToken], in unit: TranslationUnit) {
    self.tokens = tokens
    self.unit = unit
  }
}

/// Provides a processing unit for ClangFiles.
public class ClangProcessor {
  /// The translation unit from the source url provided.
  public let unit: TranslationUnit

  /// Creates a clang processor from a source url.
  /// - Parameter fileURL: Url of the source code.
  public init(fileURL url: URL) throws {
    self.unit = try TranslationUnit(filename: url.path)
  }

  /// Creates a clang processor from a string.
  /// - Parameter src: The source code.
  /// - Parameter language: The sources code's language.
  public init(src: String, language: Language) throws {
    self.unit = try TranslationUnit(clangSource: src, language: language)
  }

  /// Tells whether a token should be included or not.
  public typealias ClangTokenPredicate = (ClangToken) -> Bool

  /// - Parameter isIncluded: A function that takes a token and says if it
  ///     should be included or not.
  /// - Returns: An array of Clang tokens.
  public func tokens(isIncluded f: ClangTokenPredicate = {_ in true}) -> [ClangToken] {
    return self.unit.tokens(in: self.unit.cursor.range).filter(f)
  }

  /// Extracts all kgrams from an array of tokens.
  /// - Parameter tokens: An array of Clang tokens.
  /// - Parameter windowSize: The length of the kgram.
  /// - Returns: An array of ClangKgrams.
  public func kgrams(tokens: [ClangToken], windowSize w: Int) -> [ClangKGram] {
    if tokens.isEmpty {
      return []
    }

    return tokens.slices(ofSize: w).map { slice in
      ClangKGram(tokens: Array(slice), in: self.unit)
    }
  }

  /// Declarations that are part of the original source file before the first
  /// pass of the Preprocessor.
  /// TODO: This fails when translation unit was created from a source file.
  private lazy var inSourceDeclarations: Set<String> = {
    let file = unit.spelling
    let trimmedSrc = removeIncludes(source:
      try! String(contentsOfFile: file, encoding: .utf8))
    let tmpUnit = try! TranslationUnit(clangSource: trimmedSrc, language: .c)

    // Allowed top declaration.
    let allowedDeclarations = [
      CXCursor_FunctionDecl,
      CXCursor_VarDecl,
      CXCursor_TypedefDecl,
      CXCursor_EnumConstantDecl,
      CXCursor_StructDecl,
      CXCursor_UnionDecl,
    ]

    var declarations = Set<String>()
    tmpUnit.visitChildren { cursor in
      let cursorKind = clang_getCursorKind(cursor.asClang())
      if allowedDeclarations.contains(cursorKind) {
        declarations.insert(cursor.displayName)
      }
      return ChildVisitResult.recurse
    }

    return declarations
  }()

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
  public static let defaultCursorPredicate: CursorPredicate = { cursor in
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
  public func flattenAst(
    isIncluded: CursorPredicate = defaultCursorPredicate) -> [Cursor] {

    var ast = [Cursor]()
    self.unit.visitChildren { cursor in
      // Ignore declarations that are not part of the source code.
      // When a code includes a library (e.g., #include <stdio.h>) lot of
      // declarations are brought by the preprocesor which is noise when
      // checking for plagiarism.
      if let parent = cursor.lexicalParent, parent == unit.cursor {
        if !inSourceDeclarations.contains(cursor.displayName) {
          return ChildVisitResult.continue
        }
      }

      if isIncluded(cursor) {
        ast.append(cursor)
      }

      return ChildVisitResult.recurse
    }

    return ast
  }

  /// Flattens and describe the AST using a preorder traversal.
  /// Descriptions of the AST is based on the node's kind.
  ///
  /// - Returns: An array of strings.
  /// - Note: Declaratations that are imported using #include directives are
  ///     excluded.
  public func describeAst(ast: [Cursor]) -> [String] {
    return ast.map { cursor in
      clang_getCursorKindSpelling(
        clang_getCursorKind(cursor.asClang())
      ).asSwift()
    }
  }


  /// Removes include directives from the file (e.g., #include <stdio.h>).
  /// Includes are replaced by an empty string.
  ///
  /// ### Example: ###
  /// ````
  /// 1. #include <stdio.h>
  /// 2. #include <string.h>
  /// 3. void main(void) {}
  /// ````
  /// Will be converted to:
  /// ````
  /// 1.
  /// 2.
  /// 3. void main(void) {}
  /// ````
  ///
  ///  - Parameter source: Source code to preprocess.
  /// - Returns: Source code without include directives.
  ///
  /// - Remark: The count of the line numbers will not change.
  private func removeIncludes(source: String) -> String {
    // Regex definitions.
    let whitespaces = "[ \t]*"                   // Matches zero of more whitespaces.
    let libraryName = "(<.*>" + "|" + "\".*\")"  // Matches <.*> or ".*"

    // Matches include directives.
    let pattern = "#include\(whitespaces)\(libraryName)"

    let regex = try! NSRegularExpression(pattern: pattern)
    return regex.stringByReplacingMatches(in: source,
                                          options: [],
                                          range: self.fullTextRange(in: source),
                                          withTemplate: "")
  }

  private func fullTextRange(in s: String) -> NSRange {
    return NSRange(location: 0, length: s.utf8.count)
  }
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
