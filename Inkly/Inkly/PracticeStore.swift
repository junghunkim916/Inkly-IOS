// PracticeStore.swift
import Foundation

final class PracticeStore {
    static let shared = PracticeStore()
    private init() {}
    var latestPNG: Data?
}
