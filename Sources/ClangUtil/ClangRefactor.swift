import Foundation
import Clang
import cclang

/// Provides the contents of a file that has not yet been saved to disk.
/// Each CXUnsavedFile instance provides the name of a file on the system along
/// with the current contents of that file that have not yet been saved to disk.
class UnsavedFile {
  /// The underlying CXUnsavedFile value.
  var clang: CXUnsavedFile

  /// A C String that represents the filename.
  private var filenamePtr: UnsafeMutablePointer<CChar>!

  /// A C String that represents the contents buffer.
  private var contentsPtr: UnsafeMutablePointer<CChar>!

  /// Creates an Unsaved file with empty filename, and content.
  public convenience init() {
    self.init(filename: "", contents: "")
  }

  /// Creates an UnsavedFile with initialized `filename` and `contents`.
  /// - Parameter filename: Filename (should exist in the filesystem).
  /// - Parameter contents: Content of the file.
  public init(filename: String, contents: String) {
    clang = CXUnsavedFile()
    self.filename = filename
    self.contents = contents
  }

  /// The file whose contents have not yet been saved.
  /// This file must already exist in the file system.
  public var filename: String {
    get {
      return String(cString: filenamePtr)
    }
    set {
      deallocate(filenamePtr)
      filenamePtr = makeCStrFrom(string: newValue)
      clang.Filename = UnsafePointer<CChar>(filenamePtr)
    }
  }

  /// A buffer containing the unsaved contents of this file.
  public var contents: String {
    get {
      return String(cString: contentsPtr)
    }
    set {
      deallocate(contentsPtr)
      contentsPtr = makeCStrFrom(string: newValue)
      clang.Contents = UnsafePointer<CChar>(contentsPtr)
      clang.Length = UInt(strlen(contentsPtr))
    }
  }

  /// Creates a C String from a Swift String.
  /// - Parameter string: A Swift String.
  /// - Returns: A C String or nil in case of error.
  private func makeCStrFrom(string: String) -> UnsafeMutablePointer<CChar>? {
    guard let cStr = string.cString(using: .utf8) else {
      return nil
    }

    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: cStr.count)
    ptr.initialize(from: cStr, count: cStr.count)
    return ptr
  }

  /// Deallocates a C String.
  /// - Parameter ptr: C String.
  private func deallocate(_ ptr: UnsafeMutablePointer<CChar>!) {
    guard let s = ptr else {
      return
    }
    ptr.deallocate(capacity: strlen(s))
  }

  deinit {
    deallocate(filenamePtr)
    deallocate(contentsPtr)
  }
}

func renameIdentifier(_ identifier: IdentifierToken,
                      in unit: TranslationUnit,
                      with name: String) -> UnsavedFile {
  let identifierSpelling = identifier.spelling(in: unit)
  let identifierCursorReferenced = clang_getCursorReferenced(
    clang_getCursor(unit.asClang(), identifier.location(in: unit).asClang()))

  // TODO: Handle error instead of crashing.
  var contents = try! String(contentsOfFile: unit.spelling, encoding: .utf8)

  let tokens = unit.tokens(in: unit.cursor.range)
  tokens.flatMap { (token) -> SourceRange? in
    let tokenSpelling = token.spelling(in: unit)
    let cursorReferenced = clang_getCursorReferenced(
      clang_getCursor(unit.asClang(), token.location(in: unit).asClang()))

    // Return range to update if same spelling, and both the referenced cursors
    // are equal.
    if identifierSpelling == tokenSpelling &&
      clang_equalCursors(identifierCursorReferenced, cursorReferenced) != 0 {
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


