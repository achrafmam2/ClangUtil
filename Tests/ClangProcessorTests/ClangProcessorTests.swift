import Clang
import Foundation
import XCTest
import MongoKitten
@testable import ClangProcessor


class ArraySlicingTests: XCTestCase {
  func testSlicing() {
    // The array [1, 2, 3] and window size of 2 should give [[1, 2], [2, 3]].
    XCTAssertTrue([1, 2, 3].slices(ofSize: 2)
      .elementsEqual([[1, 2], [2, 3]]) {$0 == $1})

    // Size of the window bigger than actual array.
    XCTAssertTrue([1, 2, 3].slices(ofSize: 5)
      .elementsEqual([[1, 2, 3]], by: {$0 == $1}))
  }
}

class ClangProcessorTests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testTokenization() {
    do {
      let processor = try ClangProcessor(src: "int main() {}", language: .c)
      XCTAssertEqual(
        processor.tokens().map {$0.spelling(in: processor.unit)},
        ["int", "main", "(", ")", "{", "}"]
      )
      XCTAssertEqual(
        processor.tokens {!($0 is PunctuationToken)}
                 .map {$0.spelling(in: processor.unit)},
        ["int", "main"]
      )
    } catch {
      XCTFail("\(error)")
    }
  }

  func testKGrams() {
    do {
      let processor = try ClangProcessor(src: "int main() {}", language: .c)
      let tokens = processor.tokens()
      let kgrams = processor.kgrams(tokens: tokens, windowSize: 5)
      XCTAssertEqual(kgrams.count, 2)
      XCTAssertEqual(
        kgrams[0].tokens.map {$0.spelling(in: kgrams[0].unit)},
        ["int", "main", "(", ")", "{",]
      )
      XCTAssertEqual(
        kgrams[1].tokens.map {$0.spelling(in: kgrams[0].unit)},
        ["main", "(", ")", "{", "}"]
      )
    } catch {
      XCTFail("\(error)")
    }
  }

  func testReduce() {
    do {
      let src = "int main(void) {int a;}"
      let processor = try ClangProcessor(src: src, language: .c)
      let tokens = processor.tokens()
      let kgrams = processor.kgrams(tokens: tokens, windowSize: 5)
      XCTAssertEqual(kgrams.count, 6)
      let fingerprints = kgrams.winnow(using: 3)
      XCTAssertEqual(fingerprints.count, 4)
    } catch {
      XCTFail("\(error)")

    }
  }
}

class DBTests: XCTestCase {
  class DummyKgram: KgramIndexable {
    var hash = 0
    var val = ""
    var doc: Document? = nil

    var hashValue: Int {
      return hash
    }

    static func ==(lhs: DummyKgram, rhs: DummyKgram) -> Bool {
      return true
    }

    var document: Document? {
      return doc
    }

    var value: String {
      return val
    }

    func setHashValue(_ h: Int) -> DummyKgram {
      hash = h
      return self
    }

    func setDoc(_ d: Document?) -> DummyKgram {
      doc = d
      return self
    }

    func setValue(_ v: String) -> DummyKgram {
      val = v
      return self
    }
  }

  func testClangKgramRecord() {
    // This test will fail if the current process cannot connect to the local
    // mongoDB server.
    do {
      let db = try Database("mongodb://localhost/__Test__")
      let testCollection = db["test"]
      defer {
        // Delete database.
        try! db.drop()
      }

      let indexer =
        generateIndexer(collection: testCollection) as Indexer<DummyKgram>
      let kgram = DummyKgram()

      try indexer(kgram
        .setHashValue(0)
        .setValue("int main")
        .setDoc(["file": 0])
      )
      XCTAssertEqual(
        try testCollection.find().count(),
        1
      )

      try indexer(kgram
        .setHashValue(0)
        .setValue("int main")
        .setDoc(["file": 1]))
      XCTAssertEqual(
        try testCollection.find().count(),
        1
      )

      try indexer(kgram
        .setHashValue(1)
        .setValue("int main ()")
        .setDoc(["file": 0]))
      try indexer(kgram
        .setHashValue(1)
        .setValue("int main ()")
        .setDoc(["file": 1]))
      XCTAssertEqual(
        try testCollection.find().count(),
        2
      )

      let kgramProjection = [
        "_id": .excluded,
        "file_anchors": .included,
      ] as Projection

      let queryKeyValue = "key" == 1 && "value" == "int main ()"
      XCTAssertEqual(
        try testCollection.findOne(queryKeyValue,
          projecting: kgramProjection),
        [
          "file_anchors": [
            ["file": 0], ["file": 1],
          ]
        ]
      )
    } catch {
      XCTFail("\(error)")
    }
  }
}
