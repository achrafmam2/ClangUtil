import Clang
import Foundation

extension Array {
  /// Returns all slices of size `w`.
  /// - Parameter w: The size of the slices.
  /// - Returns: An array of slices.
  /// - Note: If the size `w` is bigger than the count of the array, then
  ///           returns the whole array.
  func slices(ofSize w: Int) -> [ArraySlice<Element>] {
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

/// Creates a `TranslationUnit` from a clang source code.
/// - Parameter src: Represents a clang source code.
/// - Parameter language: The source code language (e.g.,: c, cpp, objective-c).
/// - Returns: A `TranslationUnit` for the given source code.
func translationUnitFromSource(_ src: String,
                               language: Language) throws -> TranslationUnit {
  /// Returns URL for temporary directory.
  let temporaryDirectory = { () -> URL in
    if #available(OSX 10.12, *) {
      return FileManager.default.temporaryDirectory
    } else {
      return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
  }

  /// Returns correct extension depending on the language passed.
  let extensionFromLang = { (lang: Language) -> String in
    switch lang {
    case .c:
      return ".c"
    case .cPlusPlus:
      return ".cc"
    case .objectiveC:
      return ".m"
    }
  }

  // Create random file in temporary directory with `clangSource` as content.
  let randomFileName =
    UUID().uuidString.lowercased() + extensionFromLang(language)
  let temporaryClangFileURL =
    temporaryDirectory().appendingPathComponent(randomFileName)

  if !FileManager.default.createFile(atPath: temporaryClangFileURL.path,
                                     contents: src.data(using: .utf8)) {
    // Could not create a temporary file.
    throw TranslationUnitFromSourceError.TemporaryFileCouldNotBeCreated(
      path: temporaryClangFileURL.path)
  }

  defer {
    try? FileManager.default.removeItem(at: temporaryClangFileURL)
  }

  return try TranslationUnit(filename: temporaryClangFileURL.path)
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
public struct ClangProcessor {
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
    self.unit = try translationUnitFromSource(src, language: language)
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

  /// Reduces an array of ClangKgrams using the winnowing algorithm.
  /// See [paper](https://theory.stanford.edu/~aiken/publications/papers/sigmod03.pdf)
  /// for more details.
  /// - Parameter kgrams: An array of ClangKgrams.
  /// - Parameter windowSize: Length of the window used in the winnowing
  ///     algorithm.
  /// - Returns: An array of ClangKgrams.
  public func reduce(kgrams: [ClangKGram], windowSize w: Int) -> [ClangKGram] {
    if kgrams.isEmpty {
      return []
    }

    var reduced = [ClangKGram]()
    kgrams.slices(ofSize: w).forEach { slice in
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

