// Copyright 2018, Oath Inc
// Licensed under the terms of the MIT license. See LICENSE file in https://github.com/anthony-lai/ShadowClass/blob/master/LICENSE for terms.

#!/usr/bin/env xcrun --sdk macosx swift

let TestFileForceIgnore = "//  @ForceIgnore"
let TestFileIdentifier = "//  @ShadowTesting"
let FileTypesToScan = [".swift"]
let ScanDirPath = "."

// Script Strings
let GeneratedFolder = "/ShadowClasses/"
let TestClassPrefix = "Test"
let TestVariablePrefix = "test_"
let IgnoredFolders = [GeneratedFolder, "ShadowClasses/", "SmartTopDemoTests/", "SmartTopDemoUITests/", "Pods/"]

// Script settings
let GenerateJSONIntermediates = false
// If TRUE, this will generate Test Files containing the Test Classes within your PROJECT_DIR/GENERATEDFOLDER. GENERATEDFOLDER defaults to 'ShadowClasses'
let GenerateSwiftTestFiles = true
// If TRUE, this will automatically append the Test Classes to your source files. DANGEROUS.
let AppendToSwiftFiles = false
// Verbose analysis of classes printed
let VerboseAnalysisOn = false
// Set to FALSE to clean up print statements for debugging
let DebugPrintingOn = false
// A value of 0 means TESTFILEIDENTIFIER MUST appear on the first line. Setting this to a higher value allows for flexibility on where to place TESTFILEIDENTIFIER
let TestFileIdentifierLines = 3


//  TestClassBuilder.swift
//  Created by Tony Lai on 11/10/17.
//  Copyright © 2017 yahoo. All rights reserved.

import Foundation

/*
 * Hunts for files that begin with "//@ShadowTesting" and generates shadowClasses
 */

struct ProgenitorFile: CustomStringConvertible {
    let fileURL: URL
    let classes: [ProgenitorClass]
    let structs: [ProgenitorStruct]
    var description: String {
        var testFile = "#if TESTING\n"
        if classes.count + structs.count == 0 {
            return "#if TESTING\n    // No classes or structs found within this file\n#endif"
        }
        for progenitorClass in classes {
            testFile += progenitorClass.description
        }
        for progenitorStruct in structs {
            testFile += progenitorStruct.description
        }
        testFile += "#endif"
        return testFile
    }
}

// Represents a class as a filepath, name, variables, and functions
struct ProgenitorClass: CustomStringConvertible {
    let className: String
    let variables: [ProgenitorVariable]
    let functions: [ProgenitorFunction]
    let structs: [ProgenitorStruct]
    var description: String {
        var testFile = "class \(TestClassPrefix)\(className): \(className) {\n\n"
        if variables.count + functions.count + structs.count == 0 {
            return "class \(TestClassPrefix)\(className): \(className) {\n    // No fileprivate variables, functions, or structs found within this class\n}\n"
        }
        for variable in variables {
            testFile += variable.description
        }
        testFile += "\n"
        for function in functions {
            testFile += function.description
        }
        if structs.count != 0 {
            testFile += "\n"
        }
        for structure in structs {
            testFile += structure.description
        }
        testFile += "\n}\n"
        return testFile
    }
}

struct ProgenitorStruct: CustomStringConvertible {
    let name: String
    let variables: [ProgenitorVariable]
    var description: String {
        var descriptor = "    struct \(name) {\n"
        for variable in variables {
            descriptor += "    \(variable.description)"
        }
        descriptor += "    }\n"
        return descriptor
    }
}

// Representes a fileprivate variable as a name, type, and attributes
struct ProgenitorVariable: CustomStringConvertible {
    let name: String
    let type: String
    let attributes: [SwiftAttributes]
    var description: String {
        var attributeString = ""
        for attribute in attributes {
            if attribute == SwiftAttributes.override {
                continue
            }
            attributeString += "\(attribute) "
        }
        return "    \(attributeString)var \(TestVariablePrefix)\(name): \(type) { get { return \(name)<# as! Test\(name.capitalizeFirstLetter())#> } }\n"
    }
}

// Represents a fileprivate function as a name and attributes
struct ProgenitorFunction: CustomStringConvertible {
    let name: String
    let attributes: [SwiftAttributes]
    var description: String {
        var attributeString = ""
        for attribute in attributes {
            if attribute == SwiftAttributes.override {
                continue
            }
            attributeString += "\(attribute) "
        }
        return "    override \(attributeString)func \(name)<# -> RETURNS#> {\n        super.\(name)\n        <#STUB#>\n    }\n"
    }
}

enum SwiftKeywords: String {
    case swiftClass             = "source.lang.swift.decl.class"
    case swiftVariableInstance  = "source.lang.swift.decl.var.instance"
    case swiftMethodInstance    = "source.lang.swift.decl.function.method.instance"
    case swiftStruct            = "source.lang.swift.decl.struct"
    case swiftMark              = "source.lang.swift.syntaxtype.comment.mark"
    case swiftIf                = "source.lang.swift.stmt.if"
    case swiftCall              = "source.lang.swift.expr.call"
}

enum SwiftPrivacyLevels: String {
    case filePrivate            = "source.lang.swift.accessibility.fileprivate"
}

enum SwiftAttributes: String {
    case weak                   = "source.decl.attribute.weak"
    case objc                   = "source.decl.attribute.objc"
    case override               = "source.decl.attribute.override"
    case required               = "source.decl.attribute.required"
}

func isClass(possibleClass: [String: Any]) -> Bool {
    return possibleClass["key.kind"] as! String == SwiftKeywords.swiftClass.rawValue
}

func isStruct(possibleStruct: [String: Any]) -> Bool {
    return possibleStruct["key.kind"] as! String == SwiftKeywords.swiftStruct.rawValue
}

class Particulate {
    var kind: String
    var name: String?
    var accessibility: String?
    var typename: String?
    var substructure : [Any]?
    var attributes : [Any]?
    
    init(dictionary: [String:Any]) {
        self.kind = dictionary["key.kind"] as! String
        self.name = dictionary["key.name"] as? String
        self.accessibility = dictionary["key.accessibility"] as? String
        self.typename = dictionary["key.typename"] as? String
        self.substructure = dictionary["key.substructure"] as? [Any]
        self.attributes = dictionary["key.attributes"] as? [Any]
    }
    
    // Returns true if the Particulate is not part of a fileprivate variable or function
    func canBeIgnored(previousParticulate: Particulate?) -> Bool {
        if VerboseAnalysisOn {
            if isMarkComment() {
                print("Ignoring MARK declaration")
                return true
            }
            if isComputedProperty() {
                print("Ignoring computed property")
                return true
            }
            if !isFilePrivate() && previousParticulate == nil {
                print("Ignoring non-Fileprivate particulate \(name!)")
                return true
            }
            return false
        }
        return isMarkComment() || isComputedProperty() || (!isFilePrivate() && previousParticulate == nil)
    }
    
    func isMarkComment() -> Bool {
        return kind == SwiftKeywords.swiftMark.rawValue
    }
    
    func isComputedProperty() -> Bool {
        return kind == SwiftKeywords.swiftIf.rawValue
    }
    
    func isInstanceVariable() -> Bool {
        return kind == SwiftKeywords.swiftVariableInstance.rawValue
    }
    
    func isMethodCall() -> Bool {
        return kind == SwiftKeywords.swiftCall.rawValue
    }
    
    func isMethodInstance() -> Bool {
        return kind == SwiftKeywords.swiftMethodInstance.rawValue
    }
    
    func isFilePrivate() -> Bool {
        return accessibility == SwiftPrivacyLevels.filePrivate.rawValue
    }
    
    func isStruct() -> Bool {
        return kind == SwiftKeywords.swiftStruct.rawValue
    }
    
    func attributeArray() -> [SwiftAttributes] {
        var myAttributes = [SwiftAttributes]()
        if attributes != nil {
            for attribute in attributes! {
                let attributeDict = attribute as! [String: String]
                myAttributes.append(SwiftAttributes(rawValue: attributeDict["key.attribute"]!)!)
            }
        }
        return myAttributes
    }
    
    func functionString() -> String? {
        if takesNoArguments() {
            return name!
        } else if substructure != nil {
            return functionComplexString()
        }
        return nil
    }
    
    func takesNoArguments() -> Bool {
        return name!.suffix(2) == "()"
    }
    
    func functionComplexString() -> String {
        let signature = name!.components(separatedBy: "(")
        let arguments = signature[1].dropLast(2).components(separatedBy: ":")
        var completeArguments = "("
        for (idx, argument) in arguments.enumerated() {
            completeArguments += argument
            let internalArgument = substructure![idx] as! [String: Any]
            let internalArgumentName = internalArgument["key.name"] as! String
            if argument != internalArgumentName {
                completeArguments += " " + internalArgumentName
            }
            completeArguments += ": " + (internalArgument["key.typename"] as! String) + ", "
        }
        completeArguments = String(completeArguments.dropLast(2)) + ")"
        return signature[0] + completeArguments
    }
    
}

func buildTestFiles() {
    let date_start = NSDate()
    var allTestFiles: [ProgenitorFile] = []
    let urls = getURLsForFiles(ofTypes: FileTypesToScan, withPath: ScanDirPath)
    for url in urls {
        allTestFiles.append(contentsOf: scanFileForTestClasses(url))
    }
    allTestFiles.forEach { (testClassMatch) in
        dprint("\(testClassMatch)\n")
    }
    if allTestFiles.count == 0 {
        print("NO FILES MARKED WITH \(TestFileIdentifier) IN FIRST LINE")
    }
    print("Finished in \(-date_start.timeIntervalSinceNow) seconds")
}

/// Searches for a list of files with a type in "types" in path "path", returns an array of all found matches. Types are a simple filename suffix, path can be relative.
func getURLsForFiles(ofTypes types: [String], withPath path: String) -> [URL] {
    let fileManager = FileManager.default
    guard let bundle = Bundle(path: path) else {
        print("Couldn't get bundle for path '\(path)', aborting")
        return []
    }
    guard let enumerator = fileManager.enumerator(at: bundle.bundleURL, includingPropertiesForKeys: [.nameKey, .isDirectoryKey], options: .skipsHiddenFiles, errorHandler: nil) else {
        print("Couldn't build file enumerator at bundleURL '\(bundle.bundleURL)', aborting")
        return []
    }
    
    var fileURLS: [URL] = []
    for fileURLUntyped in enumerator {
        guard let url = fileURLUntyped as? URL else { continue }
        guard let values = try? url.resourceValues(forKeys: Set<URLResourceKey>([.nameKey, .isDirectoryKey])) else { continue }
        guard let filename = values.name, let isDir = values.isDirectory else { continue }
        if isDir {
            continue
        }
        for type in types {
            if filename.hasSuffix(type) {
                fileURLS.append(url)
                continue
            }
        }
    }
    return fileURLS
}

/// Scan a file for test classes.
func scanFileForTestClasses(_ fileURL: URL) -> [ProgenitorFile] {
    let fileString = fileURL.absoluteString
    let index = fileString.index(fileString.startIndex, offsetBy: FileManager.default.currentDirectoryPath.count + 8)
    let shortFileString = fileString.suffix(from: index)
    
    for folder in IgnoredFolders {
        if shortFileString.hasPrefix(folder) {
            return []
        }
    }
    
    print("Scanning \(shortFileString)")
    
    guard let fileContents = try? String(contentsOf: fileURL) else {
        print("Couldn't read file at url '\(fileURL)', aborting")
        return []
    }
    
    var testFiles: [ProgenitorFile] = []
    
    let fileComponentArray = fileContents.components(separatedBy: "\n")
    let linesToScan = min(TestFileIdentifierLines, fileComponentArray.count - 1)
    
    for i in 0...linesToScan {
        let line = fileComponentArray[i].trimmingCharacters(in: .whitespacesAndNewlines)
        if scanForForceIgnore(in: line) {
            return []
        }
        if scanForIdentifier(in: line) {
            print("* Entering \(fileString.suffix(from: index))")
            dprint("⎡ -----------------------------------------------------------------------⎤")
            testFiles += createShadowFile(for: fileURL)
            dprint("⎣ -----------------------------------------------------------------------⎦")
            break
        }
    }
    return testFiles
}

/// Scan a single line for the identifier
func scanForIdentifier(in line: String) -> Bool {
    let range = NSRange(location: 0, length: line.utf16.count)
    return Regex.shared.testKeyword.firstMatch(in: line, range: range) != nil
}

func scanForForceIgnore(in line: String) -> Bool {
    let range = NSRange(location: 0, length: line.utf16.count)
    return Regex.shared.ignoreKeyword.firstMatch(in: line, range: range) != nil
}

func createShadowFile(for fileURL: URL) -> [ProgenitorFile] {
    
    var path = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)!
    path.scheme = nil
    let tildeString = path.url!.absoluteString.replacingOccurrences(of: "%20", with: " ")
    let strippedPath = path.url!.deletingPathExtension().lastPathComponent
    
    var outerClasses = [ProgenitorClass]()
    var outerStructs = [ProgenitorStruct]()
    
    let outputData = shell("sourcekitten", "structure", "--file", tildeString).output
    let outputJSON = try? JSONSerialization.jsonObject(with: outputData, options: []) as? [String: Any]
    
    if GenerateJSONIntermediates {
        let outputString = String(data: outputData, encoding: String.Encoding.utf8)!
        let file = "\(strippedPath)ShadowJSON.txt" // File that output JSON is written to.
        write(to: file, contents: outputString)
    }
    
    let fileEnclosure = outputJSON!!["key.substructure"] as! [Any]
    
    for outerEnclosure in fileEnclosure {
        var fileName: String
        let unknownType = outerEnclosure as! [String: Any]
        if isClass(possibleClass: unknownType) {
            fileName = unknownType["key.name"] as! String
            if fileName.hasPrefix(TestClassPrefix) {
                dprint("  Skipping analysis of \(fileName) as it is a test class")
                continue
            }
            dprint("  Analysing \(fileName)")
            
            var variables   = [ProgenitorVariable]()
            var functions   = [ProgenitorFunction]()
            var structs     = [ProgenitorStruct]()
            let variablesAndMethods = unknownType["key.substructure"] as! [Any]
            var previousParticulate : Particulate? = nil
            for classElement in variablesAndMethods {
                
                let particulate = Particulate(dictionary: classElement as! [String: Any])
                
                if particulate.canBeIgnored(previousParticulate: previousParticulate) {
                    continue
                }
                
                if particulate.isInstanceVariable() && particulate.isFilePrivate() {
                    if let explicitType = particulate.typename {
                        variables.append(ProgenitorVariable(name: particulate.name!, type: explicitType, attributes: particulate.attributeArray()))
                        vprint("    \(particulate.name!): \(explicitType)")
                        previousParticulate = nil // Failsafe, probably unnecessary, but used to correctly reset state after an implicit declaration
                    } else {
                        previousParticulate = particulate
                        vprint("        Chain Definition Part 1 for: \(particulate.name!)")
                    }
                } else if particulate.isMethodCall() && previousParticulate != nil {
                    variables.append(ProgenitorVariable(name: previousParticulate!.name!, type: particulate.name!, attributes: previousParticulate!.attributeArray()))
                    vprint("        Chain Definition Part 2 for: \(particulate.name!)")
                    vprint("    \(previousParticulate!.name!): \(particulate.name!)")
                    previousParticulate = nil
                } else if particulate.isFilePrivate() && particulate.isMethodInstance() {
                    let functionName = particulate.functionString()!
                    functions.append(ProgenitorFunction(name: functionName, attributes: particulate.attributeArray()))
                    vprint("    func: \(functionName)")
                } else if particulate.isFilePrivate() && particulate.isStruct() {
                    structs.append(ProgenitorStruct(name: particulate.name!, variables: findVariablesFromStruct(particulate)))
                    vprint("    struct: \(particulate.name!)")
                } else {
                    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!! FALLTHROUGH !!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
                    print(classElement)
                    print("!!!!!!!!!!!!!!!!!!!!!!!!!!! END FALLTHROUGH !!!!!!!!!!!!!!!!!!!!!!!!!!!")
                }
            }
            let progeny = ProgenitorClass(className: fileName, variables: variables, functions: functions, structs: structs)
            outerClasses.append(progeny)
            
        } else if isStruct(possibleStruct: unknownType) {
            print(unknownType)
            fileName = unknownType["key.name"] as! String
            if fileName.hasPrefix(TestClassPrefix) {
                dprint("  Skipping analysis of \(fileName) as it is a test struct")
                continue
            }
            dprint("  Analysing \(fileName)")
            
            let particulate = Particulate(dictionary: unknownType)
            outerStructs.append(ProgenitorStruct(name: particulate.name!, variables: findVariablesFromStruct(particulate)))
        } else {
            let particulate = Particulate(dictionary: unknownType)
            if particulate.isMarkComment() {
                continue
            }
            fileName = unknownType["key.name"] as! String
            dprint("  Skipping analysis of \(fileName) as it is not a class")
            continue
        }
    }
    
    let progenitorFile = ProgenitorFile(fileURL: fileURL, classes: outerClasses, structs: outerStructs)
    
    if GenerateSwiftTestFiles {
        let file = "\(strippedPath)ShadowClass.swift"
        write(to: file, contents: progenitorFile.description)
        dprint("  Shadow Class created at: \(strippedPath)ShadowClass.swift")
    }
    if AppendToSwiftFiles { //DANGER
        do {
            dprint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! DANGER !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            dprint("ATTEMPTING TO APPEND TO FILE: \(strippedPath).swift")
            try progenitorFile.description.appendToFile(at: fileURL)
        }
        catch {
            print("Attempting to append to file: \(strippedPath).swift failed")
        }
    }
    
    return [progenitorFile]
}

func findVariablesFromStruct(_ particulate: Particulate) -> [ProgenitorVariable] {
    var variables = [ProgenitorVariable]()
    
    for item in particulate.substructure as! [[String:Any]] {
        let particulate = Particulate(dictionary: item)
        variables.append(ProgenitorVariable(name: particulate.name!, type: particulate.typename!, attributes: particulate.attributeArray()))
    }
    return variables
}

struct Regex {
    static let shared = Regex()
    let testKeyword: NSRegularExpression
    let ignoreKeyword: NSRegularExpression
    init() {
        do {
            testKeyword = try NSRegularExpression(pattern: TestFileIdentifier, options: .caseInsensitive)
            ignoreKeyword = try NSRegularExpression(pattern: TestFileForceIgnore, options: .caseInsensitive)
        }
        catch let error {
            fatalError("Couldn't construct regexes: \(error)")
        }
    }
}

func vprint(_ str: String) {
    if VerboseAnalysisOn {
        print(str)
    }
}

// Used to clean up output when debugging
func dprint(_ str: String) {
    if DebugPrintingOn {
        print(str)
    }
}

extension String {
    func capitalizeFirstLetter() -> String {
        return prefix(1).uppercased() + dropFirst()
    }
    
    func appendToFile(at fileURL: URL) throws {
        let data = self.data(using: String.Encoding.utf8)!
        try data.append(fileURL: fileURL)
    }
}

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

func write(to file: String, contents: String) {
    let fileManager = FileManager.default
    let rawString = "file://" + fileManager.currentDirectoryPath + GeneratedFolder
    if let dir = URL(string: rawString.replacingOccurrences(of: " ", with: "%20"))  {
        // If the directory does not exist
        
        if !fileManager.fileExists(atPath: dir.path) {
            print("Creating Directory at: \(dir.path)")
            do {
                try fileManager.createDirectory(atPath: dir.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Creating Directory failed with error \(error)")
            }
        }
        // Create the File
        let fileURL = dir.appendingPathComponent(file)
        do {
            try contents.write(to: fileURL, atomically: false, encoding: .utf8)
        } catch {
            print("Writing output JSON to file failed with error \(error)!")
        }
        
    }
}

@discardableResult
func shell(_ args: String...) -> (output: Data, exitCode: Int32) {
    
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = args
    
    let outpipe = Pipe()
    task.standardOutput = outpipe
    
    task.launch()
    
    let data = outpipe.fileHandleForReading.readDataToEndOfFile()
    
    task.waitUntilExit()
    return (data, task.terminationStatus)
}

buildTestFiles()

