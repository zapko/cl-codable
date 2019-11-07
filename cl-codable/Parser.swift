//
//  Parser.swift
//  cl-codable
//
//  Created by Zapko on 2019-11-03.
//  Copyright © 2019 Zababako. All rights reserved.
//

import Foundation


enum ParsingError: Error {
    case invalidFormat(String)
    case internalError(context: [String: Any])
    case invalidLiteral(String)
}

let spaces = CharacterSet.whitespacesAndNewlines
let structPrefix = "#s("

func read(clStruct: String, catalog: [String : ([String : String]) -> Any]) throws -> Any {
    
    var fieldValues: [String : String] = [:]
        
    var inside: [(struct: String, field: String?)] = []
    
    var remaining = clStruct.trimmingCharacters(in: spaces)

    var result: Any? = nil

    var previousLength = remaining.count
    while !remaining.isEmpty {

        if remaining.prefix(structPrefix.count).lowercased() == structPrefix  {
            
            remaining = String(remaining.suffix(
                from: remaining.index(remaining.startIndex, offsetBy: structPrefix.count))
            )
            
            guard let spaceIndex = remaining.firstIndex(of: " ") else {
                
                if let parenthesisIndex = remaining.firstIndex(of: ")") {
                    inside.append((String(remaining.prefix(upTo: parenthesisIndex)), nil))
                    
                    remaining = String(remaining.suffix(from: parenthesisIndex))
                    remaining = remaining.trimmingCharacters(in: spaces)
                    continue
                }
                
                throw ParsingError.invalidFormat("Missing structure end: \(remaining)")
            }
            
            let type = String(remaining.prefix(upTo: spaceIndex))
            inside.append((type, nil))

            remaining = String(remaining.suffix(from: spaceIndex))
            remaining = remaining.trimmingCharacters(in: spaces)
        }
        
        if remaining.hasPrefix(":") {
            
            guard let last = inside.last, last.field == nil else {
                throw ParsingError.invalidFormat("Field with no struct: \(remaining)")
            }
            
            remaining = remaining.trimmingCharacters(in: CharacterSet.init(charactersIn: ":"))
            
            guard let spaceIndex = remaining.firstIndex(of: " ") else {
                throw ParsingError.invalidFormat("Missing field name end: \(remaining)")
            }
            
            let fieldName = String(remaining.prefix(upTo: spaceIndex))
            inside[inside.count - 1].field = fieldName

            remaining = String(remaining.suffix(from: spaceIndex))
            remaining = remaining.trimmingCharacters(in: spaces)
        }
        
        if let currentField = inside.last?.field {
            
            var value: String?
            defer {
                fieldValues[currentField] = value
                inside[inside.count - 1].field = nil
            }
            
            if remaining.hasPrefix("\"") {
                
                remaining.remove(at: remaining.startIndex)
                
                guard let endOfLiteral = remaining.closingQuoteIndex() else {
                    throw ParsingError.invalidFormat("Non-ending literal")
                }
                
                value = try String(remaining.prefix(upTo: endOfLiteral)).unscreenedLiteral()

                remaining = String(remaining.suffix(from: endOfLiteral))
                remaining.remove(at: remaining.startIndex)
                remaining = remaining.trimmingCharacters(in: spaces)
                
            } else {
                
                guard let spaceIndex = remaining.firstIndex(of: " ") else {
                    
                    if let parenthesisIndex = remaining.firstIndex(of: ")") {
                        value = String(remaining.prefix(upTo: parenthesisIndex))
                        
                        remaining = String(remaining.suffix(from: parenthesisIndex))
                        remaining = remaining.trimmingCharacters(in: spaces)
                        continue
                    }
                    
                    throw ParsingError.invalidFormat("Missing field value end: \(remaining)")
                }

                value = String(remaining.prefix(upTo: spaceIndex))

                remaining = String(remaining.suffix(from: spaceIndex))
                remaining = remaining.trimmingCharacters(in: spaces)
            }
        }
        
        if remaining.hasPrefix(")") {
            
            guard let (structType, field) = inside.popLast() else {
                throw ParsingError.invalidFormat("Ending struct with no start")
            }
            
            guard field == nil else {
                let message = "Field with no value: \(field!) in \(structType)"
                throw ParsingError.invalidFormat(message)
            }
            
            print("Field values: \(fieldValues)")
            result = catalog[structType]!(fieldValues)
            fieldValues = [:]
            
            remaining.remove(at: remaining.startIndex)
            remaining = remaining.trimmingCharacters(in: spaces)
        }

        print(remaining)

        if previousLength <= remaining.count {
            throw ParsingError.internalError(context: [
                "values"    : fieldValues,
                "struct"    : inside,
                "remaining" : remaining
            ])
        }
        previousLength = remaining.count
    }
    
    guard let result2 = result else {
        throw ParsingError.invalidFormat("There is no object")
    }
    
    return result2
}


extension String {

    func closingQuoteIndex() -> String.Index? {

        var screened = false
        return firstIndex {

            switch ($0, screened) {
            case ("\\", true):  screened = false
            case ("\\", false): screened = true
            case ("\"", true):  screened = false
            case ("\"", false): return true
            default:            screened = false
            }

            return false
        }
    }

    func unscreenedLiteral() throws -> String {

        typealias Aggregator = (chars: [Character], screenOn: Bool)

        let aggregator = try self.reduce(into: Aggregator(chars: [], screenOn: false)) {
            (aggregator, char) in

            switch (char, aggregator.screenOn) {
            case ("\\", true):
                aggregator.chars.append(char)
                aggregator.screenOn = false

            case ("\\", false):
                aggregator.screenOn = true

            case ("\"", true):
                aggregator.chars.append(char)
                aggregator.screenOn = false

            case ("\"", false):
                throw ParsingError.invalidLiteral("Unscreened quote in: '\(self)'")

            case (_, true):
                throw ParsingError.invalidLiteral("Screened non-quote in: '\(self)'")

            case (_, false):
                aggregator.chars.append(char)
            }
        }

        return String(aggregator.chars)
    }
}