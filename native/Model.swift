import Foundation

// Monetary fields remain raw. Only this presentation layer applies a live multiplier.
struct DisplayCurrency: Decodable {
    let id: Int
    let name: String
    let shortName: String
    let symbol: String
    let value: Double
    var valid: Bool { !name.isEmpty && value.isFinite && value > 0 }
    func amount(_ raw: Int) -> Double { (Double(raw) * value).rounded(.toNearestOrEven) }
    func format(_ raw: Int) -> String {
        let number=amount(raw).formatted(.number.precision(.fractionLength(0)))
        return symbol.isEmpty ? number + " " + shortName : symbol + number
    }
}
struct CurrencyTable: Decodable {
    let status: String
    let definitions: [DisplayCurrency]
    var available: [DisplayCurrency] {
        guard status == "verified", definitions.allSatisfy({$0.valid}), Set(definitions.map(\.name)).count == definitions.count else {return []}
        return definitions.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
}
func displayMoney(_ raw:Int, currency:DisplayCurrency?) -> String { currency?.format(raw) ?? raw.formatted() }
extension Money {
    func display(in currency:DisplayCurrency?) -> String {known.map {displayMoney($0,currency:currency)} ?? display}
}

struct Club: Decodable {
    let status: String
    let name: String?
    let nameStatus: String?
    let uid: Int?
    let address: String?
    var display: String { nameStatus == "verified" ? (name ?? "Unresolved") : (status == "unavailable" ? "Unavailable" : "Unresolved") }
}
struct Team: Decodable { let status: String; let uid: Int?; let club: Club? }
struct Contract: Decodable { let status: String; let kind: String?; let team: Team? }
struct Money: Decodable {
    let status: String; let raw: Int?; let currency: String?
    var known: Int? { status == "verified" ? raw : nil }
    var display: String { known.map { $0.formatted() } ?? (status == "unavailable" ? "Unavailable" : "Unresolved") }
}
struct Expiry: Decodable {
    let status: String; let date: String?; let rawDay: Int?; let rawYear: Int?
    var known: String? { ["verified", "derived"].contains(status) ? date : nil }
    var display: String { known ?? (status == "unavailable" ? "Unavailable" : "Unresolved") }
}
struct Flag: Decodable { let status: String; let value: Bool?; var known: Bool? { ["derived","verified"].contains(status) ? value : nil } }
struct Auxiliary: Decodable { let status: String; let loanOrTrial: Contract?; let bClub: Contract? }
struct Transfers: Decodable {
    let currentTeam: Team
    let currentClub: Club
    let employmentContract: Contract
    let weeklyWage: Money
    let contractExpiry: Expiry
    let playerValue: Money
    let askingPrice: Money?
    let auxiliaryContracts: Auxiliary
    let loanState: Flag
    let freeAgentState: Flag
}
struct Reputation: Decodable { let home: Int?; let current: Int?; let world: Int?; let rawSlots: [Int] }
struct Trait: Decodable { let bit: Int; let name: String }
struct Traits: Decodable { let mapped: [Trait]; let unresolvedBits: [Int] }
struct Nationality: Decodable {
    let status: String
    let name: String?
    var known: String? {
        guard status == "verified", let name=name, !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
        return name
    }
    var display: String {
        if let name=known {return name}
        return status == "unavailable" ? "Unavailable" : "Unresolved"
    }
}
struct PersonalityContext: Decodable {
    let status:String
    let rawFlagsByte:Int
    let negativeLabelsAllowed:Bool
    var knownNegativeLabelsAllowed:Bool? {
        guard status == "verified", (0...255).contains(rawFlagsByte),
              negativeLabelsAllowed == (rawFlagsByte & 8 != 0) else {return nil}
        return negativeLabelsAllowed
    }
}
struct Player: Decodable {
    let entity: Int? // Existing cache entity field; optional for older caches.
    let uid: Int
    let name: String?
    let birthDate: String
    let age: Int?
    let ca: Int
    let pa: Int
    let positions: [String:Int?]
    let rawAttributes: [Int]? // Already serialized by capture; optional for older caches.
    let visibleAttributes: [String:Int?]
    let hiddenAttributes: [String:Int?]
    let footStrengths: [String:Int?]
    let personalityComponents: [String:Int?]
    let personalityContext: PersonalityContext?
    let heightCM: Int?
    let weightKG: Int?
    let reputation: Reputation
    let traits: Traits
    let fieldStatus: [String:String]
    let transfers: Transfers?
    let nationality: Nationality?
    var knownAge:Int? {["verified","derived"].contains(fieldStatus["age"] ?? "") ? age : nil}
    var nationalityDisplay: String {nationality?.display ?? "Unresolved"}
    var displayName: String { name ?? "Unnamed player · \(uid)" }
    var club: String {
        guard let t=transfers else {return "Unresolved"}
        if t.employmentContract.status == "verified" {
            return t.employmentContract.team?.club?.display ?? "Unresolved"
        }
        return t.freeAgentState.known == true ? "Free Agent" : "Unresolved"
    }
    var position: String {
        let ratings = positions.compactMap { key, value -> (String,Int)? in value.map { (key,$0) } }.sorted { a,b in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
        let proficient = ratings.filter { $0.1 >= 15 }
        return (proficient.isEmpty ? Array(ratings.prefix(1)) : proficient).map(\.0).joined(separator: ", ")
    }
    var isKeeper: Bool { (positions["GK"] ?? nil) ?? 0 >= 15 }
    var cost: (String,Int)? {
        if let amount = transfers?.playerValue.known { return ("Market Value",amount) }
        if let amount = transfers?.askingPrice?.known { return ("Asking Price",amount) }
        return nil
    }
}
struct CollectionInfo: Decodable { let count: Int }
struct GameDateInfo: Decodable { let status:String }
struct Snapshot: Decodable {
    let gameDate:String?
    let gameDateInfo:GameDateInfo?
    var projectionDate:String? {gameDateInfo?.status == "verified" ? gameDate : nil}
    let currencies: CurrencyTable?
    let modelVersion: Int
    let capturedAt: String
    let elapsedSeconds: Double
    let collection: CollectionInfo
    let players: [Player]
}
final class Row {
    let player: Player
    let name: String
    let club: String
    let position: String
    let nameKey: String
    let clubKey: String
    let nationality: String?
    let age: Int?
    let wage: Int?
    let askingPrice: Int?
    let cost: Int?
    let expiry: String?
    init(_ p: Player) {
        player=p; name=p.displayName; club=p.club; position=p.position
        nameKey=normalized(name); clubKey=normalized(club)
        nationality=p.nationality?.known
        age=p.knownAge
        cost=p.cost?.1 // Immutable sort key; do not resolve monetary precedence per comparison.
        askingPrice=p.transfers?.askingPrice?.known.flatMap {$0 >= 0 ? $0 : nil}
        wage=p.transfers?.weeklyWage.known; expiry=p.transfers?.contractExpiry.known
    }
}
func availableNationalities(_ rows:[Row]) -> [String] {
    Array(Set(rows.compactMap(\.nationality))).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
}
func normalized(_ s: String) -> String { s.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX")) }

let technical = ["corners","crossing","dribbling","finishing","first_touch","free_kick_taking","heading","long_shots","long_throws","marking","passing","penalty_taking","tackling","technique"]
let mental = ["aggression","anticipation","bravery","composure","concentration","decisions","determination","flair","leadership","off_the_ball","positioning","teamwork","vision","work_rate"]
let physical = ["acceleration","agility","balance","jumping_reach","natural_fitness","pace","stamina","strength"]
let goalkeeper = ["aerial_reach","command_of_area","communication","eccentricity","first_touch","handling","kicking","one_on_ones","passing","punching","reflexes","rushing_out","throwing"]
let hidden = ["consistency","dirtiness","important_matches","injury_proneness","versatility"]
let personality = ["adaptability","ambition","loyalty","pressure","professionalism","sportsmanship","temperament","controversy"]
func title(_ key: String) -> String { key.replacingOccurrences(of:"_",with:" ").capitalized }

func loadCache(_ url: URL) throws -> (Snapshot,[Row],Double) {
    let start=Date()
    let data=try Data(contentsOf:url,options:.mappedIfSafe)
    let cache=try JSONDecoder().decode(Snapshot.self,from:data)
    guard [2,3].contains(cache.modelVersion),cache.collection.count==cache.players.count,
          Set(cache.players.map(\.uid)).count==cache.players.count else {
        throw NSError(domain:"Touchline",code:1,userInfo:[NSLocalizedDescriptionKey:"The saved cache is incomplete or unsupported. Refresh live data to rebuild it."])
    }
    return (cache,cache.players.map(Row.init),Date().timeIntervalSince(start))
}
