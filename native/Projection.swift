import Foundation

/// Deterministic scouting model over cached inputs; never a prediction from FM's simulation.
/// Input constraints and numeric quirks: docs/ARCHITECTURE.md. No UI or capture dependencies.
enum DevelopmentGroup: String {
    case striker, attacking, midfield, defender, goalkeeper
}
struct ProjectedAttributes {
    let raw: [String:Int]
    let displayed: [String:Int]
}
struct ProjectionProfile {
    let peak: Int
    let attributes: ProjectedAttributes
}

enum PlayerProjection {
    // Physical cache slot order, including feet. Hidden fields are modelled for
    // behavioral completeness but are never swapped into the profile's hidden section.
    static let attributeKeys = [
        "crossing","dribbling","finishing","heading","long_shots","marking","off_the_ball",
        "passing","penalty_taking","tackling","vision","handling","aerial_reach",
        "command_of_area","communication","kicking","throwing","anticipation","decisions",
        "one_on_ones","positioning","reflexes","first_touch","technique","left_foot",
        "right_foot","flair","corners","teamwork","work_rate","long_throws","eccentricity",
        "rushing_out","punching","acceleration","free_kick_taking","strength","stamina",
        "pace","jumping_reach","leadership","dirtiness","balance","bravery","consistency",
        "aggression","agility","important_matches","injury_proneness","versatility",
        "natural_fitness","determination","composure","concentration"
    ]
    static let positionKeys = ["GK","SW","DL","DC","DR","DM","ML","MC","MR","AML","AMC","AMR","ST","WBL","WBR"]
    // Ages 16...33; nil is an absolute 200 candidate, not 200 extra CA.
    private static let headroom: [DevelopmentGroup:[Int?]] = [
        .striker:[nil,179,152,130,113,99,86,73,61,49,39,33,27,21,15,9,3,0],
        .attacking:[191,164,137,115,99,86,75,64,53,43,36,29,23,17,11,5,1,0],
        .midfield:[187,160,133,111,94,81,70,60,50,41,34,28,22,17,12,7,2,0],
        .defender:[185,158,131,109,93,80,68,58,48,39,31,25,20,15,19,5,2,0],
        .goalkeeper:[193,163,133,109,92,77,64,51,38,27,21,17,13,10,7,4,2,1]
    ]
    static func signedByte(_ value:Int)->Int {Int(Int8(truncatingIfNeeded:value))}
    private static func signedWord(_ value:Int)->Int {Int(Int16(truncatingIfNeeded:value))}
    struct Positions {
        let g,c,d,f,b,dm,m,a,w,s:Bool
        init(_ values:[String:Int]) {
            func any(_ keys:String...)->Bool {keys.contains {PlayerProjection.signedByte(values[$0] ?? 0)>=15}}
            g=any("GK");c=any("SW","DC");d=any("DC");f=any("DL","DR");b=any("WBL","WBR")
            dm=any("DM");m=any("MC");a=any("AMC");w=any("ML","MR","AML","AMR");s=any("ST")
        }
        var group:DevelopmentGroup? {
            if g {return .goalkeeper};if c || f {return .defender}
            if b || dm || m {return .midfield};if a || w {return .attacking}
            return s ? .striker : nil
        }
    }
    static func projectedPeak(age:Int,ca:Int,pa:Int,positions:[String:Int])->Int? {
        guard age>=0,let group=Positions(positions).group else {return nil}
        let candidate:Int
        if age<16 {candidate=200}
        else if age<=33 {
            candidate=headroom[group]![age-16].map {signedWord(signedWord(ca)+$0)} ?? 200
        } else {candidate=signedWord(ca)}
        // There is intentionally no CA floor, monotonic age smoothing, or negative-PA reinterpretation.
        return min(candidate,signedWord(pa))
    }
    /// Uses elapsed 365.25-day years, independently of the normal calendar age label.
    static func elapsedAge(birthDate:String,gameDate:String)->Int? {
        guard let birth=day(birthDate),let game=day(gameDate) else {return nil}
        return Int((abs(game.timeIntervalSince(birth))/31_557_600).rounded(.towardZero))
    }
    private static let calendar:Calendar = {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!;return calendar
    }()
    private static func day(_ value:String)->Date? {
        let parts=value.split(separator:"-",omittingEmptySubsequences:false)
        guard value.count==10,parts.count==3,parts[0].count==4,parts[1].count==2,parts[2].count==2,
              let y=Int(parts[0]),let m=Int(parts[1]),let d=Int(parts[2]),(1...9999).contains(y),
              let date=calendar.date(from:DateComponents(year:y,month:m,day:d)),
              calendar.component(.year,from:date)==y,calendar.component(.month,from:date)==m,
              calendar.component(.day,from:date)==d else {return nil}
        return date
    }
    // A nil rate means an unassigned native slot, not zero growth. Zero means
    // copy without invoking the helper (which would still perform its upper cap).
    static func rates(positions:[String:Int])->[String:Double] {
        let p=Positions(positions)
        let (g,c,d,f,b,dm,m,a,w,s)=(p.g,p.c,p.d,p.f,p.b,p.dm,p.m,p.a,p.w,p.s)
        var r=Dictionary(uniqueKeysWithValues:attributeKeys.filter {$0 != "left_foot" && $0 != "right_foot"}.map {($0,0.0)})
        for k in ["aerial_reach","command_of_area","communication","kicking"] {r[k]=g ? 0.35 : 0}
        for k in ["handling","one_on_ones","throwing"] {r[k]=g ? 0.25 : 0}
        r["reflexes"]=g ? 0.25 : 0.075
        r["corners"]=(a || w || s) ? 0.35 : m ? 0.25 : dm ? 0.20 : (d || f || b) ? 0.15 : 0
        for k in ["crossing","finishing"] {r[k]=(b || dm || m || a || w || s) ? 0.25 : f ? 0.20 : c ? 0.15 : 0}
        r["dribbling"]=(dm || m || a || w || s) ? 0.25 : (c || f || b) ? 0.20 : 0
        r["first_touch"]=(w || s) ? 0.35 : 0.25
        r["free_kick_taking"]=(a || s) ? 0.35 : w ? 0.20 : (c || f || b || dm || m) ? 0.15 : 0
        r["heading"]=(c || m || a || s) ? 0.25 : (f || b || w) ? 0.20 : 0.15
        r["long_shots"]=(f || b || dm || m || a || w || s) ? 0.35 : c ? 0.20 : 0
        r["long_throws"]=(f || b || w) ? 0.35 : (c || a || s) ? 0.20 : (dm || m) ? 0.15 : 0
        r["marking"]=(c || f || b || dm || m || a || w) ? 0.25 : s ? 0.20 : 0
        r["passing"]=(dm || m || a) ? 0.35 : (w || s) ? 0.25 : (f || b) ? 0.20 : 0.15
        r["penalty_taking"]=(a || s) ? 0.25 : (b || dm || m || w) ? 0.20 : (c || f) ? 0.15 : 0
        r["tackling"]=(c || f || b || dm || m || a || w) ? 0.25 : s ? 0.15 : g ? 0 : nil
        r["technique"]=0.20;r["anticipation"]=0.35;r["concentration"]=0.35;r["bravery"]=0.075
        for k in ["composure","decisions"] {r[k]=g ? 0.25 : 0.35}
        for k in ["vision","off_the_ball"] {r[k]=(b || dm || m || a || w || s) ? 0.35 : (c || f) ? 0.25 : 0}
        r["flair"]=g ? 0 : 0.15;r["leadership"]=g ? 0.15 : 0.25
        r["positioning"]=(g || c || f || b || dm || a || w) ? 0.35 : m ? 0.25 : 0.20
        r["teamwork"]=(g || a) ? 0.25 : (f || b || w) ? 0.20 : 0.15
        r["work_rate"]=(g || a || w || s) ? 0.20 : 0.15
        r["acceleration"]=(g || c || f || b || dm || m || s) ? 0.25 : 0.20
        r["agility"]=(c || f || dm || m || s) ? 0.35 : 0.25
        r["balance"]=(c || f || b || dm || s) ? 0.25 : 0.20
        r["jumping_reach"]=g ? 0.20 : (c || s) ? 0.15 : 0.075
        r["natural_fitness"]=g ? 0 : (c || f) ? 0.20 : 0.15
        r["pace"]=0.25;r["stamina"]=0.25
        r["strength"]=(f || b || m || a || w) ? 0.35 : 0.25
        r["consistency"]=0.15;r["versatility"]=(dm || m || a || w || s) ? 0.15 : 0.075
        return r
    }
    static func grow(raw:Int,ca:Int,peak:Int,rate:Double)->Int {
        let delta=Double(signedWord(peak)-signedWord(ca))
        let increment=delta*rate
        let result=Int((Double(signedByte(raw))+increment).rounded(.toNearestOrEven)) & 255
        return signedByte(result)>100 ? 100 : result
    }
    static func display(raw:Int)->Int {
        let rounded=Int((Double(signedByte(raw)*20)/100).rounded(.toNearestOrEven))
        return max(1,min(20,signedByte(rounded)))
    }
    static func attributes(raw:[String:Int],ca:Int,peak:Int,positions:[String:Int])->ProjectedAttributes {
        let rules=rates(positions:positions)
        var projected:[String:Int]=[:]
        for (key,value) in raw {
            guard let rate=rules[key] else {continue} // Feet and unwritten/unknown slots remain absent.
            projected[key]=rate==0 ? value & 255 : grow(raw:value,ca:ca,peak:peak,rate:rate)
        }
        return ProjectedAttributes(raw:projected,displayed:projected.mapValues {display(raw:$0)})
    }
    /// Cache adapter: never substitutes rounded displays, host date, guessed
    /// positions or retained foreign-object state for missing verified inputs.
    static func profile(for player:Player,gameDate:String?)->ProjectionProfile? {
        guard let gameDate=gameDate,["verified","derived"].contains(player.fieldStatus["birthDate"] ?? ""),
              player.fieldStatus["ca"]=="verified",player.fieldStatus["pa"]=="verified",
              (0...200).contains(player.ca),(0...200).contains(player.pa),
              player.fieldStatus["rawAttributes"]=="verified",let raw=player.rawAttributes,raw.count==54,
              let age=elapsedAge(birthDate:player.birthDate,gameDate:gameDate) else {return nil}
        var positions:[String:Int]=[:]
        for key in positionKeys {
            guard let value=player.positions[key] ?? nil,(1...20).contains(value) else {return nil}
            positions[key]=value
        }
        guard let peak=projectedPeak(age:age,ca:player.ca,pa:player.pa,positions:positions) else {return nil}
        var inputs:[String:Int]=[:]
        for (key,value) in zip(attributeKeys,raw) where (1...100).contains(value) {inputs[key]=value}
        let result=attributes(raw:inputs,ca:player.ca,peak:peak,positions:positions)
        guard player.visibleAttributes.contains(where: {key,value in value != nil && result.displayed[key] != nil}) else {return nil}
        return ProjectionProfile(peak:peak,attributes:result)
    }
}
