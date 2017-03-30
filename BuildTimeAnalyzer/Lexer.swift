//
//  Lexer.swift
//  BuildTimeAnalyzer
//

import Foundation

/// Class capable of parsing tokens out of a string.
/// Currently presents support to parse single/double-quoted strings, and
/// floating point numbers.
final class Lexer {
    
    /// Defines the smallest unit of text this lexer can process
    typealias Atom = UnicodeScalar
    
    /// Defines the type of the buffer index
    typealias Index = String.UnicodeScalarIndex
    
    let inputString: String
    
    /// The actual source of values scanned
    var inputSource: String.UnicodeScalarView {
        return inputString.unicodeScalars
    }
    
    /// Index at `inputSource` that the lexer is currently at
    private(set) var inputIndex: Index
    
    /// Past-the-end index of the `inputSource`
    private let endIndex: Index
    
    init(input: String) {
        inputString = input
        inputIndex = inputString.unicodeScalars.startIndex
        endIndex = inputString.unicodeScalars.endIndex
    }
    
    init(input: String, index: Index) {
        inputString = input
        inputIndex = index
        endIndex = inputString.unicodeScalars.endIndex
    }
    
    // MARK: Raw parsing methods
    func parseInt(skippingWhitespace: Bool = true) throws -> Int {
        if(skippingWhitespace) {
            skipWhitespace()
        }
        
        // Consume raw like this - type-checking is provided on conversion
        // method bellow
        let string = consume(while: isDigit)
        
        guard let value = Int(string) else {
            throw LexerError.invalidDateValue(message: "Invalid integer string \(string)")
        }
        
        return value
    }
    
    // MARK: String parsing methods
    func parseIntString(skippingWhitespace: Bool = true) throws -> String {
        if(skippingWhitespace) {
            skipWhitespace()
        }
        
        if(!isDigit(try peek())) {
            throw invalidCharError("Expected integer but received '\(unsafePeek())'")
        }
        
        return consume(while: isDigit)
    }
    
    func parseFloatString(skippingWhitespace: Bool = true) throws -> String {
        if(skippingWhitespace) {
            skipWhitespace()
        }
        
        // (0-9)+('.'(0..9)+)
        if(!isDigit(try peek())) {
            throw invalidCharError("Expected float but received '\(unsafePeek())'")
        }
        
        let start = inputIndex
        
        advance(while: isDigit)
        
        if(safeIsNextChar(equalTo: ".")) {
            unsafeAdvance()
            
            // Expect more digits
            if(!isDigit(try peek())) {
                throw invalidCharError("Expected float but received '\(unsafePeek())'")
            }
            
            advance(while: isDigit)
        }
        
        return String(inputSource[start..<inputIndex]) // Consume entire offset
    }
    
    /// Advances the stream until the first non-whitespace character is found.
    func skipWhitespace() {
        advance(while: isWhitespace)
    }
    
    /// Returns whether the current stream position points to the end of the
    /// stream.
    /// No further reading is possible when a stream is pointing to the end.
    func isEof() -> Bool {
        return inputIndex >= endIndex
    }
    
    /// Returns whether the next char returns true when passed to the given
    /// closure.
    /// This method is safe, since it checks isEoF before making the check call.
    func safeNextCharPasses(with closure: (Atom) throws -> Bool) rethrows -> Bool {
        return try !isEof() && closure(unsafePeek())
    }
    
    /// Returns whether the next char in the string the given char.
    /// This method is safe, since it checks isEoF before making the check call.
    func safeIsNextChar(equalTo char: Atom) -> Bool {
        return !isEof() && unsafePeek() == char
    }
    
    /// Reads a single character from the current stream position, and forwards
    /// the stream by 1 unit.
    func next() throws -> Atom {
        defer {
            unsafeAdvance()
        }
        
        return try peek()
    }
    
    /// Peeks the current character at the current index
    func peek() throws -> Atom {
        if(isEof()) {
            throw endOfStringError()
        }
        
        return inputSource[inputIndex]
    }
    
    /// Unsafe version of peek(), proper for usages where check of isEoF is 
    /// preemptively made.
    private func unsafePeek() -> Atom {
        return inputSource[inputIndex]
    }
    
    /// Advances the stream without reading a character.
    /// Throws an EoF error if the current offset is at the end of the character
    /// stream
    func advance() throws {
        if(isEof()) {
            throw endOfStringError()
        }
        
        unsafeAdvance()
    }
    
    /// Unsafe version of advance(), proper for usages where check of isEoF is
    /// preemptively made.
    private func unsafeAdvance() {
        inputIndex = inputSource.index(inputIndex, offsetBy: 1)
    }
    
    /// Advances while the passed character-consumed method returns true.
    /// Stops when reaching end-of-string, or the when the closure returns false.
    func advance(while closure: (Atom) throws -> Bool) rethrows {
        while(try !isEof() && closure(unsafePeek())) {
            unsafeAdvance()
        }
    }
    
    /// Consumes the input string while a given closure returns true.
    /// Stops when reaching end-of-string, or the when the closure returns false.
    func consume(while closure: (Atom) throws -> Bool) rethrows -> String {
        let start = inputIndex
        try advance(while: closure)
        return String(inputSource[start..<inputIndex])
    }
    
    /// Consumes the entire buffer from the current point up until the last
    /// character.
    /// Returns an empty string, if the current character is already pointing at
    /// the end of the buffer.
    func consumeRemaining() -> String {
        defer {
            inputIndex = endIndex // Stop at end of buffer
        }
        
        return String(inputSource[inputIndex..<endIndex])
    }
    
    /// Advances while the passed character-consumed method returns false.
    /// Stops when reaching end-of-string, or the when the closure returns true.
    func advance(until closure: (Atom) throws -> Bool) rethrows {
        while(try !isEof() && !closure(unsafePeek())) {
            unsafeAdvance()
        }
    }
    
    /// Consumes the input string while a given closure returns false.
    /// Stops when reaching end-of-string, or the when the closure returns true.
    func consume(until closure: (Atom) throws -> Bool) rethrows -> String {
        let start = inputIndex
        try advance(until: closure)
        return String(inputSource[start..<inputIndex])
    }
    
    /// Advances the stream if the current string under it matches the given
    /// string.
    ///
    /// The method checks the match, does nothing while returning false if the
    /// current stream position does not match the given string.
    ///
    /// By default, the lexer does a `literal`, character-by-character match,
    /// which can be overriden by specifying the `options` parameter.
    func advanceIf(equals: String, options: String.CompareOptions = .literal) -> Bool {
        guard let current = inputIndex.samePosition(in: inputString) else {
            return false
        }
        
        if let range = inputString.range(of: equals, options: options, range: current..<inputString.endIndex) {
            // Match! Advance stream and proceed...
            if(range.lowerBound == current) {
                inputIndex = range.upperBound.samePosition(in: inputSource)
                
                return true
            }
        }
        
        return false
    }
    
    /// Advance the stream if the current string under it matches the given atom
    /// character.
    /// The method throws an error if the current character is not the expected
    /// one, or advances to the next position, if it is.
    func advance(expectingCurrent atom: Atom) throws {
        let n = try next()
        if(n != atom) {
            throw LexerError.invalidCharacter(message: "Expected '\(atom)', received '\(n)' instead")
        }
    }
    
    // MARK: Character checking
    func isDigit(_ c: Atom) -> Bool {
        return c >= "0" && c <= "9"
    }
    
    func isStringDelimiter(_ c: Atom) -> Bool {
        return c == "\"" || c == "\'"
    }
    
    private static let whitespaces = CharacterSet.whitespacesAndNewlines
    func isWhitespace(_ c: Atom) -> Bool {
        return Lexer.whitespaces.contains(c)
    }
    
    private static let letters = CharacterSet.letters
    func isLetter(_ c: Atom) -> Bool {
        return Lexer.letters.contains(c)
    }
    
    func isAlphanumeric(_ c: Atom) -> Bool {
        return isLetter(c) || isDigit(c)
    }
    
    // MARK: Error methods
    func invalidCharError(_ message: String) -> Error {
        return LexerError.invalidCharacter(message: message)
    }
    
    func invalidDateValueError(_ message: String) -> Error {
        return LexerError.invalidDateValue(message: message)
    }
    
    func endOfStringError(_ message: String = "Reached unexpected end of input string") -> Error {
        return LexerError.endOfStringError(message: message)
    }
    
    func unknownTokenTypeError(_ message: String) -> Error {
        return LexerError.unknownTokenType(message: message)
    }
}

enum LexerError: Error {
    case invalidCharacter(message: String)
    case endOfStringError(message: String)
    case invalidDateValue(message: String)
    case unknownTokenType(message: String)
}
