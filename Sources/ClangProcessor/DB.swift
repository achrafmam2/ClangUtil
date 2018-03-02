import MongoKitten
import Clang

/// Function prototype for an Indexing functions. Indexers are functions that
/// index kgrams in a database.
/// - Parameter T: A `KgramIndexable` type.
public typealias Indexer<T: KgramIndexable> = (T) throws -> Void

/// A type with a Mongo document representation.
/// Types that conforms to the `DocumentConvertible` protocol can be used for
/// storage in a MonogDB collection.
public protocol DocumentConvertible {
  /// A MongoDB document that represents the current element.
  var document: Document? { get }
}

/// A type that can be indexed as a <Key, Value> in a a MongoDB collection.
public protocol KgramIndexable: Hashable, DocumentConvertible {
  /// A value that represents the current element.
  var value: String { get }
}

extension ClangKGram: KgramIndexable {
  /// Returns a document that can be stored in a MongoDB collection.
  public var document: Document? {
    guard start != nil && end != nil else {
      return nil
    }

    return [
      "file_path": start?.file.name,
      "start": [
        "line": start?.line,
        "column": start?.column,
      ],
      "end": [
        "line": end?.line,
        "column": end?.column,
      ],
    ]
  }

  /// Returns the kgram value.
  public var value: String {
    return tokens.map {
      clangTokenTypeName($0)
      }.joined(separator: " ")
  }
}

/// Generates a function for indexing.
/// The index template document looks as follows:
/// ````
/// [
///   "key": <KGram Hash Value>,
///   "value": <Kgram Value>,
///   "file_anchors": [<Source File Locations>]
/// ]
/// ````
/// - Parameter collection: A MongoDB collection.
/// - Returns: A function that stores kgrams in an index.
public func generateIndexer<T: KgramIndexable>
  (collection: MongoKitten.Collection) -> Indexer<T> {
  return { element in
    let query = ("key" == element.hashValue) && ("value" == element.value)
    try collection.update(query, to: [
      "$push": [
        "file_anchors": element.document
      ]], upserting: true)
  }
}

/// Function type for looking up kgrams.
/// - Parameter key: hashValue of the kgram.
/// - Parameter value: kgram value.
/// - Returns: A MongoDB document or nil if not found.
public typealias KgramLookup = (_ key: Int, _ value: String) throws -> Document?

/// Represents errors when doing a lookup on kgrams.
enum KgramLookupError: Error {
  /// Two kgrams with same hash and value were found.
  case MoreThanOneKgramFoundError
}

/// Generates a function for looking up kgrams.
/// - Parameter collection: A MongoDB collection.
/// - Returns: A function that lookup kgrams. See `KgramLookup` type.
public func generateKgramLookup
  (collection: MongoKitten.Collection) -> KgramLookup {
  return { key, val in
    let results = try collection.find(("key" == key) && ("value" == val))
    guard try results.count() <= 1 else {
      throw KgramLookupError.MoreThanOneKgramFoundError
    }
    return results.first
  }
}
