import MongoKitten
import Clang

/// Function prototype for an Indexing functions. Indexers are functions that
/// index kgrams in a database.
/// - Parameter T: A `KgramIndexable` type.
typealias Indexer<T: KgramIndexable> = (T) throws -> Void

/// A type with a Mongo document representation.
/// Types that conforms to the `DocumentConvertible` protocol can be used for
/// storage in a MonogDB collection.
protocol DocumentConvertible {
  var document: Document? { get }
}

/// A type that can be indexed as a <Key, Value> in a a MongoDB collection.
protocol KgramIndexable: Hashable, DocumentConvertible {
  var value: String { get }
}

extension ClangKGram: KgramIndexable {
  /// Returns a document that can be stored in a MongoDB collection.
  var document: Document? {
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
  var value: String {
    return tokens.map{$0.spelling(in: unit)}.joined(separator: " ")
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
func generateIndexer<T: KgramIndexable>
  (collection: MongoKitten.Collection) -> Indexer<T> {
  return { element in
    let query = ("key" == element.hashValue) && ("value" == element.value)
    try collection.update(query, to: [
      "$push": [
        "file_anchors": element.document
      ]], upserting: true)
  }
}
