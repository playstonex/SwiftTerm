//
//  RDBrowserSessionGroup.swift
//
//
//  Created by Lakr Aream on 2022/3/10.
//

import Foundation

public struct RDBrowserSessionGroup: Codable, Identifiable, Equatable {
    public typealias AssociatedType = RDBrowserSession

    public var id = UUID()

    public private(set) var sessions: [AssociatedType] = []

    public var count: Int {
        sessions.count
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public mutating func insert(_ value: AssociatedType) {
        if let index = sessions.firstIndex(where: { $0.id == value.id }) {
            sessions[index] = value
        } else {
            sessions.append(value)
        }
    }

    public subscript(_ id: AssociatedType.ID) -> AssociatedType {
        get {
            sessions.first(where: { $0.id == id }) ?? .init()
        }

        set(newValue) {
            if let index = sessions.firstIndex(where: { $0.id == newValue.id }) {
                sessions[index] = newValue
            } else {
                debugPrint("setting subscript found nil when sending value, did you forget to call insert?")
            }
        }
    }

    public mutating func delete(_ value: AssociatedType.ID) {
        let index = sessions
            .firstIndex { $0.id == value }
        if let index = index {
            sessions.remove(at: index)
        }
    }
}
