import Foundation

// Inactive ranges include unknown values. Any active bound requires a known value.
func matchesRange(_ value:Int?,minimum:Int?,maximum:Int?)->Bool {
    guard minimum != nil || maximum != nil else {return true}
    guard let value=value else {return false}
    return (minimum == nil || value >= minimum!) && (maximum == nil || value <= maximum!)
}

struct NumericRule:Equatable {
    enum Source: String { case attribute, hidden, component }
    var source: Source
    var key: String
    var minimum: Int?
    var maximum: Int?
    func matches(_ p: Player) -> Bool {
        let values = source == .attribute ? p.visibleAttributes : (source == .hidden ? p.hiddenAttributes : p.personalityComponents)
        guard let value = values[key] ?? nil else { return false }
        return matchesRange(value,minimum:minimum,maximum:maximum)
    }
}
struct Query:Equatable {
    var name = ""
    var club = ""
    var nationality: String?
    var position = "Any position"
    var caMin: Int?; var caMax: Int?; var paMin: Int?; var paMax: Int?
    var ageMin: Int?; var ageMax: Int?
    var askingMin: Int?; var askingMax: Int?
    var wageMin: Int?; var wageMax: Int?
    var expiryAfter = ""; var expiryBefore = ""
    var employment = "Any employment"
    var rules: [NumericRule] = []
    func matches(_ r: Row) -> Bool {
        let p=r.player
        if !name.isEmpty && !r.nameKey.contains(name) { return false }
        if !club.isEmpty && !r.clubKey.contains(club) { return false }
        if let selected=nationality, r.nationality != selected { return false }
        if position != "Any position" && ((p.positions[position] ?? nil) ?? 0) < 15 { return false }
        if !matchesRange(p.ca,minimum:caMin,maximum:caMax) {return false}
        if !matchesRange(p.pa,minimum:paMin,maximum:paMax) {return false}
        if !matchesRange(r.age,minimum:ageMin,maximum:ageMax) {return false}
        if !matchesRange(r.askingPrice,minimum:askingMin,maximum:askingMax) {return false}
        if !matchesRange(r.wage,minimum:wageMin,maximum:wageMax) {return false}
        if !expiryAfter.isEmpty || !expiryBefore.isEmpty {
            guard let date=r.expiry else { return false }
            if !expiryAfter.isEmpty && date<expiryAfter { return false }
            if !expiryBefore.isEmpty && date>expiryBefore { return false }
        }
        if employment == "Free agent" && p.transfers?.freeAgentState.known != true { return false }
        if employment == "Contracted" && p.transfers?.employmentContract.status != "verified" { return false }
        if employment == "Unknown state" && p.transfers?.freeAgentState.known != nil { return false }
        return rules.allSatisfy { $0.matches(p) }
    }
}
// Both filter interfaces edit this single draft. Dismissal never creates or resets it.
// Keep text drafts (including incomplete input) separate from the last valid query.
enum FilterField: String, CaseIterable {
    case name, club, nationality, position, employment
    case caMin, caMax, paMin, paMax, ageMin, ageMax, askingMin, askingMax, wageMin, wageMax, expiryAfter, expiryBefore
    static let abilityBounds=0...200
    static let ageBounds=0...150
    var stepperBounds:ClosedRange<Int>? {
        switch self {
        case .caMin,.caMax,.paMin,.paMax:return Self.abilityBounds
        case .ageMin,.ageMax:return Self.ageBounds
        default:return nil
        }
    }
    var initial: String {
        switch self {
        case .position:return "Any position"
        case .nationality:return "Any nationality"
        case .employment:return "Any employment"
        default:return ""
        }
    }
}
struct RuleDraft {
    var source: NumericRule.Source
    var key: String
    var minimum = ""
    var maximum = ""
}
struct FilterInputError: Error { let message: String }
struct FilterEditor {
    private var values: [FilterField:String] = [:]
    var rules: [RuleDraft] = []
    subscript(_ field: FilterField) -> String {
        get {values[field] ?? field.initial}
        set {values[field]=newValue}
    }
    mutating func reset() {self=FilterEditor()}
    // Empty drafts stay empty; zero is only the native stepper's initial position.
    func stepperValue(for field:FilterField)->Int? {
        guard let bounds=field.stepperBounds else {return nil}
        let draft=self[field].trimmingCharacters(in:.whitespacesAndNewlines)
        if draft.isEmpty {return bounds.lowerBound}
        guard let value=Int(draft),bounds.contains(value) else {return nil}
        return value
    }
    @discardableResult mutating func setSteppedValue(_ value:Int,for field:FilterField)->Bool {
        guard let bounds=field.stepperBounds else {return false}
        self[field]=String(min(bounds.upperBound,max(bounds.lowerBound,value)))
        return true
    }
    func makeQuery() throws -> Query {
        var q=Query()
        func clean(_ field:FilterField)->String {self[field].trimmingCharacters(in:.whitespacesAndNewlines)}
        func range(_ low:String,_ high:String,_ cap:Int,_ label:String) throws -> (Int?,Int?) {
            func number(_ raw:String) throws -> Int? {
                let raw=raw.trimmingCharacters(in:.whitespacesAndNewlines)
                if raw.isEmpty {return nil}
                guard let n=Int(raw),n>=0,n<=cap else {throw FilterInputError(message:"\(label): enter whole numbers from 0 to \(cap).")}
                return n
            }
            let l=try number(low),h=try number(high)
            if let l=l,let h=h,l>h {throw FilterInputError(message:"\(label): minimum exceeds maximum.")}
            return (l,h)
        }
        q.name=normalized(clean(.name));q.club=normalized(clean(.club))
        q.position=self[.position];q.employment=self[.employment]
        q.nationality=self[.nationality] == FilterField.nationality.initial ? nil : self[.nationality]
        (q.caMin,q.caMax)=try range(self[.caMin],self[.caMax],FilterField.abilityBounds.upperBound,"CA")
        (q.paMin,q.paMax)=try range(self[.paMin],self[.paMax],FilterField.abilityBounds.upperBound,"PA")
        (q.ageMin,q.ageMax)=try range(self[.ageMin],self[.ageMax],FilterField.ageBounds.upperBound,"Age")
        (q.askingMin,q.askingMax)=try range(self[.askingMin],self[.askingMax],Int(UInt32.max),"Asking Price")
        (q.wageMin,q.wageMax)=try range(self[.wageMin],self[.wageMax],Int(UInt32.max),"Weekly wage")
        q.expiryAfter=clean(.expiryAfter);q.expiryBefore=clean(.expiryBefore)
        if !q.expiryAfter.isEmpty || !q.expiryBefore.isEmpty {
            let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian);formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
            for value in [q.expiryAfter,q.expiryBefore] where !value.isEmpty {
                guard value.count == 10, let date=formatter.date(from:value),formatter.string(from:date)==value else {throw FilterInputError(message:"Use valid expiry dates in YYYY-MM-DD format.")}
            }
        }
        if !q.expiryAfter.isEmpty && !q.expiryBefore.isEmpty && q.expiryAfter>q.expiryBefore {throw FilterInputError(message:"Expiry start is later than the end.")}
        for r in rules {
            let (low,high)=try range(r.minimum,r.maximum,20,title(r.key))
            if low != nil || high != nil {q.rules.append(NumericRule(source:r.source,key:r.key,minimum:low,maximum:high))}
        }
        return q
    }
}
struct SortSpec { var key="name"; var ascending=true }
func compare<T: Comparable>(_ a: T?,_ b: T?, ascending: Bool) -> Int {
    switch (a,b) {
    case (nil,nil):return 0
    case (nil,_):return 1
    case (_,nil):return -1
    case let (a?,b?):return a==b ? 0 : ((a<b)==ascending ? -1 : 1)
    }
}
func selectRows(_ rows: [Row], query: Query, sort: SortSpec, candidates:IndexSet?=nil) -> [Int] {
    var indices: [Int]
    if let candidates=candidates {indices=candidates.filter {rows.indices.contains($0) && query.matches(rows[$0])}}
    else {indices=rows.indices.filter {query.matches(rows[$0])}}
    indices.sort { lhs,rhs in
        let a=rows[lhs],b=rows[rhs]; let order: Int
        switch sort.key {
        case "club":order=compare(a.clubKey,b.clubKey,ascending:sort.ascending)
        case "position":order=compare(a.position,b.position,ascending:sort.ascending)
        case "age":order=compare(a.age,b.age,ascending:sort.ascending)
        case "ca":order=compare(a.player.ca,b.player.ca,ascending:sort.ascending)
        case "pa":order=compare(a.player.pa,b.player.pa,ascending:sort.ascending)
        case "cost":order=compare(a.cost,b.cost,ascending:sort.ascending)
        case "wage":order=compare(a.wage,b.wage,ascending:sort.ascending)
        case "expiry":order=compare(a.expiry,b.expiry,ascending:sort.ascending)
        default:order=compare(a.nameKey,b.nameKey,ascending:sort.ascending)
        }
        return order == 0 ? a.player.uid<b.player.uid : order<0
    }
    return indices
}

// Table selection refers only to the current displayed query result.
func selectedSourceRows(_ selection:IndexSet,visible:[Int])->IndexSet {
    IndexSet(selection.compactMap {visible.indices.contains($0) ? visible[$0] : nil})
}
func restoredPlayerSelection(_ selectedUIDs:Set<Int>,results:[Int],rows:[Row])->IndexSet {
    let retained=IndexSet(results.indices.filter {selectedUIDs.contains(rows[results[$0]].player.uid)})
    return retained.isEmpty && !results.isEmpty ? IndexSet(integer:0) : retained
}
