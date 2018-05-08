// Copyright 2018, Oath Inc
// Licensed under the terms of the MIT license. See LICENSE file in https://github.com/anthony-lai/ShadowClass/blob/master/LICENSE for terms.

#!/usr/bin/env xcrun --sdk macosx swift
//MARK: CHANGE ME
let TestClassMacroName = "TESTING"
let FileTypesToScan = [".swift"]
let ScanDirPath = "."

//  TestClassCanary.swift
//  Created by Michael Cornell on 10/19/17.
//  Copyright © 2017 Yahoo Inc. All rights reserved.

import Foundation

/*
 * Hunts for classes starting with "Test", case insensitive, which are not contained within a #if TESTING ... #end macro
 */

struct TestClassMatch {
    let line: String
    let lineIdx: Int
    let file: String
}

struct Regex {
    static let shared = Regex()
    let openIf: NSRegularExpression
    let macroFlag: NSRegularExpression
    let testClass: NSRegularExpression
    let endIf: NSRegularExpression
    init() {
        do {
            openIf = try NSRegularExpression(pattern: "#if", options: .caseInsensitive)
            macroFlag = try NSRegularExpression(pattern: TestClassMacroName, options: .caseInsensitive)
            testClass = try NSRegularExpression(pattern: "class( )+[Tt]est", options: .caseInsensitive)
            endIf = try NSRegularExpression(pattern: "#endif", options: .caseInsensitive)
        }
        catch let error {
            fatalError("Couldn't construct regexes: \(error)")
        }
    }
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
// TODO Its possible to fool the scan by defining a test class, a macro start, or a macro end on the same line,or by nesting #if's
func scanFileForTestClasses(_ fileURL: URL) -> [TestClassMatch]{
    guard let fileContents = try? String(contentsOf: fileURL) else {
        print("Couldn't read file at url '\(fileURL)', aborting")
        return []
    }
    var testClasses: [TestClassMatch] = []
    var macroFlagDepths: [Int] = [] // depths at which a macro flag was found
    var macroDepth = 0 // current depth in all macro flags
    
    for (lineIdx, line) in fileContents.components(separatedBy: "\n").enumerated() {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // did we find an opening macro?
        let (foundOpener, foundMacroFlag) = scanForTestMacroStart(in: line)
        if foundOpener {
            // we found the macro we care about, store the current depth
            if foundMacroFlag {
                macroFlagDepths.append(macroDepth)
            }
            macroDepth += 1
            continue
        }
        // did we find the end of a macro?
        if scanForTestMacroEnd(in: line) {
            macroDepth -= 1
            // did we just exit the macro we care about?
            if let lastDepth = macroFlagDepths.last, lastDepth == macroDepth {
                macroFlagDepths.removeLast()
            }
            continue
        }
        
        // if we aren't in any macros which except test classes, check for the now illegal test classes
        if macroFlagDepths.count == 0 {
            if scanForTestClass(in: line) {
                // found an illegal test class!
                testClasses.append(TestClassMatch(line: line, lineIdx: lineIdx + 1, file: fileURL.relativeString))
            }
        }
    }
    return testClasses
}

/// Scan for a test macro start, returns true if found
func scanForTestMacroStart(in line: String) -> (foundOpen: Bool, foundMacroFlag: Bool) {
    let range = NSRange(location: 0, length: line.utf16.count)
    var foundOpen = false
    var foundMacroFlag = false
    foundOpen = Regex.shared.openIf.firstMatch(in: line, range: range) != nil
    if foundOpen {
        foundMacroFlag = Regex.shared.macroFlag.firstMatch(in: line, range: range) != nil
    }
    return (foundOpen: foundOpen, foundMacroFlag: foundMacroFlag)
}

/// Scan for a test macro end, returns true if found
func scanForTestMacroEnd(in line: String) -> Bool {
    let range = NSRange(location: 0, length: line.utf16.count)
    return Regex.shared.endIf.firstMatch(in: line, range: range) != nil
}

/// Scan for a line which looks like a class definition starting with the word "Test", case insensitive
func scanForTestClass(in line: String) -> Bool {
    let range = NSRange(location: 0, length: line.utf16.count)
    return Regex.shared.testClass.firstMatch(in: line, range: range) != nil
}

func scanProjectForMatches() {
    var allTestClasses: [TestClassMatch] = []
    let urls = getURLsForFiles(ofTypes: FileTypesToScan, withPath: ScanDirPath)
    // print all urls to scan
    // urls.forEach { print($0) }
    for url in urls {
        allTestClasses.append(contentsOf: scanFileForTestClasses(url))
    }
    allTestClasses.forEach { (testClassMatch) in
        // print all pairs
        print("[\n\tFILE: \(testClassMatch.file), LINE: \(testClassMatch.lineIdx)\n\tFOUND: \"\(testClassMatch.line)\"\n],")
    }
    if allTestClasses.count > 0 {
        exit(1)
    }
}

scanProjectForMatches()
