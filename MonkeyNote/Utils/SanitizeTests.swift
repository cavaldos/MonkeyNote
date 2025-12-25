//
//  SanitizeTests.swift
//  MonkeyNote
//
//  Created for testing sanitize functions
//

import Foundation

// Test hàm sanitizeFileName
func sanitizeFileName(_ name: String) -> String {
    // Chỉ giữ lại chữ cái, số, khoảng trắng, gạch nối và gạch dưới
    let allowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: " -_"))
    
    var sanitized = ""
    for character in name {
        if allowedCharacters.contains(character.unicodeScalars.first!) {
            sanitized += String(character)
        }
    }
    
    // Thay thế nhiều khoảng trắng liên tiếp bằng một khoảng trắng
    sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    
    // Xóa khoảng trắng ở đầu và cuối
    sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Xóa dấu chấm ở đầu
    while sanitized.hasPrefix(".") {
        sanitized.removeFirst()
    }
    
    return sanitized.isEmpty ? "Untitled" : sanitized
}

// Test hàm firstLineTitle
func firstLineTitle(from text: String) -> String {
    let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Untitled" }
    
    // Loại bỏ các ký tự đặc biệt, chỉ giữ lại chữ, số, khoảng trắng, gạch nối và gạch dưới
    let allowedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: " -_"))
    
    var sanitized = ""
    for character in trimmed {
        if allowedCharacters.contains(character.unicodeScalars.first!) {
            sanitized += String(character)
        }
    }
    
    // Thay thế nhiều khoảng trắng liên tiếp bằng một khoảng trắng
    sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    
    // Xóa khoảng trắng ở đầu và cuối
    sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    
    let result = sanitized.isEmpty ? "Untitled" : String(sanitized.prefix(60))
    return result
}

// Test function
func runSanitizeTests() {
    print("🧪 Testing sanitizeFileName function:")
    let testCases = [
        "##note",
        "##my important note!!",
        "@project#1", 
        "***test***",
        "normal-file-name",
        "file with spaces",
        "file.with.dots",
        "file@#$%^&*()",
        "  spaced  name  ",
        ".hidden-file"
    ]
    
    for testCase in testCases {
        let result = sanitizeFileName(testCase)
        print("'\(testCase)' -> '\(result)'")
    }

    print("\n🧪 Testing firstLineTitle function:")
    let textTestCases = [
        "##note",
        "##my important note!!\nSecond line",
        "@project#1\nContent here", 
        "***test***\nMore content",
        "normal title\nSecond line",
        "This is a title with ## symbols\nContent",
        "  ##spaced title  \nContent"
    ]
    
    for testCase in textTestCases {
        let result = firstLineTitle(from: testCase)
        print("'\(testCase)' -> '\(result)'")
    }
}