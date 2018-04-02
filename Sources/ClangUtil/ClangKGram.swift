import Clang
//import MongoKitten

/// Represents a Kgram of Clang tokens.
public struct ClangKGram: Hashable {
  /// A Kgram of (consecutive) Clang tokens.
  public let tokens: [Token]

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
  public init(tokens: [Token], in unit: TranslationUnit) {
    self.tokens = tokens
    self.unit = unit
  }
}

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

//extension ClangKGram: DocumentRepresentable {
//  /// Returns a document that can be stored in a MongoDB collection.
//  public var document: Document? {
//    guard start != nil && end != nil else {
//      return nil
//    }
//
//    let tokenSpellings = self.tokens.map { token in
//      clangTokenTypeName(token)
//      }.joined(separator: " ")
//
//    return [
//      "tokens": tokenSpellings,
//      "file_path": start?.file.name,
//      "start": [
//        "line": start?.line,
//        "column": start?.column,
//      ],
//      "end": [
//        "line": end?.line,
//        "column": end?.column,
//      ],
//    ]
//  }
//}


