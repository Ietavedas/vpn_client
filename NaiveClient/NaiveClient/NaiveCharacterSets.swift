import Foundation

enum NaiveCharacterSets {
    static let urlUser: CharacterSet = {
        var set = CharacterSet.urlUserAllowed
        set.insert(charactersIn: ":")
        return set
    }()

    static let urlPassword: CharacterSet = {
        var set = CharacterSet.urlPasswordAllowed
        set.insert(charactersIn: ":@")
        return set
    }()
}
