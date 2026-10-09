import Foundation

/// Exact-build personality semantics over cached inputs. Evidence: docs/PERSONALITY.md.
/// A displayed label is derived. Missing branch inputs must never choose a label by guess.
enum PlayerPersonality {
    struct Inputs:Decodable {
        let determination:Int
        let ambition:Int
        let sportsmanship:Int
        let loyalty:Int
        let professionalism:Int
        let temperament:Int
        let pressure:Int
        let age:Int?
        let leadership:Int?
        let negativeLabelsAllowed:Bool?
        let devotedToClub:Bool? // Club affinity is not captured by Touchline.
    }
    struct Result {
        let status:String
        let label:String?
        let reason:String?
        var display:String {label ?? "Unresolved"}
    }
    static let labels:[Int:String] = [
        1:"Professional",2:"Determined",3:"Temperamental",4:"Balanced",5:"Model Professional",
        6:"Driven",7:"Slack",8:"Casual",9:"Very Ambitious",10:"Ambitious",11:"Unambitious",
        12:"Honest",13:"Sporting",14:"Unsporting",15:"Realist",16:"Easily Discouraged",
        17:"Low Determination",18:"Very Loyal",19:"Loyal",20:"Mercenary",21:"Fickle",
        22:"Iron Willed",23:"Resilient",24:"Spineless",25:"Low Self Belief",26:"Born Leader",
        27:"Charismatic Leader",28:"Leader",29:"Devoted",30:"Light-Hearted",31:"Jovial",
        32:"Spirited",33:"Resolute",34:"Fairly Determined",35:"Fairly Professional",
        36:"Fairly Ambitious",37:"Fairly Loyal",38:"Fairly Sporting",39:"Perfectionist",40:"Model Citizen"
    ]
    /// Ordered first-match rules. This is independent code expressing the verified rule table.
    private static func code(_ i:Inputs,age:Int,leadership:Int,negative:Bool,devoted:Bool)->Int {
        let d=i.determination,a=i.ambition,s=i.sportsmanship,l=i.loyalty
        let p=i.professionalism,t=i.temperament,r=i.pressure
        if d>=14 && a>=12 && p>=15 && t>=15 && r>=14 && l>=15 && s>=15 {return 40}
        if d>=14 && a>=14 && p>=14 && t<=9 {return 39}
        if t<=4 && p<=10 && negative {return 3}
        if age>=23 && leadership>=19 {
            if leadership==20 && d==20 {return 26}
            return t>=18 && s>=18 ? 27 : 28
        }
        if p>=18 && t>=10 {return age>=23 && p==20 ? 5 : 1}
        if d>=18 {return a>=12 ? 6 : 2}
        if p<=4 && d<=9 && negative {return p==1 ? 7 : 8}
        if l<=6 && a>=16 && negative {return l<=3 ? 20 : 21}
        if a>=16 && l<=9 {return a==20 ? 9 : 10}
        if a<=5 && l>=11 && negative {return 11}
        if s>=18 && d<=9 {return s==20 ? 12 : 13}
        if s<=4 && d>=11 && negative {return s==1 ? 14 : 15}
        if d<=5 && a<=9 && negative {return d==1 ? 16 : 17}
        if l>=18 && a<=7 {return l==20 ? (devoted ? 29 : 18) : 19}
        if r>=17 && d>=15 {return r==20 ? 22 : 23}
        if r<=3 && d<=9 && negative {return r==1 ? 24 : 25}
        if r>=15 && t>=10 {
            if s>=15 {return 30}
            return p<=10 ? 31 : 32
        }
        if d>=15 {return p>=15 ? 33 : 34}
        if p>=15 {return 35}
        if a>=15 {return 36}
        if l>=15 {return 37}
        if s>=15 {return 38}
        return 4
    }
    /// Accept a missing branch input only when every possible branch gives the same label.
    static func classify(_ i:Inputs)->Result {
        guard [i.determination,i.ambition,i.sportsmanship,i.loyalty,i.professionalism,i.temperament,i.pressure].allSatisfy({(1...20).contains($0)}),
              i.age.map({(14...100).contains($0)}) ?? true,
              i.leadership.map({(1...20).contains($0)}) ?? true else {
            return Result(status:"inconsistent",label:nil,reason:"Personality input outside its verified range")
        }
        let ages=i.age.map {[$0]} ?? [14,22,23,100]
        let leaders=i.leadership.map {[$0]} ?? [1,18,19,20]
        let negatives=i.negativeLabelsAllowed.map {[$0]} ?? [false,true]
        let affinities=i.devotedToClub.map {[$0]} ?? [false,true]
        var result:Int?
        for age in ages {for leader in leaders {for negative in negatives {for affinity in affinities {
            let candidate=code(i,age:age,leadership:leader,negative:negative,devoted:affinity)
            if let previous=result,previous != candidate {
                return Result(status:"unresolved",label:nil,reason:"Uncaptured age, leadership, negative-label flag or club affinity affects classification")
            }
            result=candidate
        }}}}
        return Result(status:"derived",label:result.flatMap {labels[$0]},reason:nil)
    }
    static func profile(for player:Player,gameDate:String?)->Result {
        guard player.fieldStatus["personalityComponents"] == "verified",
              personality.allSatisfy({key in (player.personalityComponents[key] ?? nil).map {(1...20).contains($0)} ?? false}),
              let raw=player.rawAttributes,raw.count==54,
              player.fieldStatus["rawAttributes"] == "verified",
              (1...100).contains(raw[51]) else {
            return Result(status:"unresolved",label:nil,reason:"Required personality or determination data is missing or invalid")
        }
        func component(_ key:String)->Int {(player.personalityComponents[key] ?? nil)!}
        let leadership=(1...100).contains(raw[40]) ? min(20,max(1,(raw[40]+2)/5)) : nil
        let age=gameDate.flatMap {classificationAge(birthDate:player.birthDate,gameDate:$0)}
        let input=Inputs(determination:min(20,max(1,(raw[51]+2)/5)),ambition:component("ambition"),
            sportsmanship:component("sportsmanship"),loyalty:component("loyalty"),
            professionalism:component("professionalism"),temperament:component("temperament"),pressure:component("pressure"),
            age:age,leadership:leadership,negativeLabelsAllowed:player.personalityContext?.knownNegativeLabelsAllowed,devotedToClub:nil)
        return classify(input)
    }
    // FM24's classifier uses its own day-of-year age helper, clamped to 14...100.
    // Preserve its leap boundary behavior without changing Touchline's normal calendar age.
    private static let calendar:Calendar = {
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!;return c
    }()
    private static func date(_ text:String)->Date? {
        let p=text.split(separator:"-",omittingEmptySubsequences:false)
        guard text.count==10,p.count==3,p[0].count==4,p[1].count==2,p[2].count==2,
              let y=Int(p[0]),let m=Int(p[1]),let d=Int(p[2]),(1900...2100).contains(y),
              let value=calendar.date(from:DateComponents(year:y,month:m,day:d)),
              calendar.component(.year,from:value)==y,calendar.component(.month,from:value)==m,
              calendar.component(.day,from:value)==d else {return nil}
        return value
    }
    static func classificationAge(birthDate:String,gameDate:String)->Int? {
        guard let b=date(birthDate),let g=date(gameDate),b<=g,
              birthDate != "1900-01-01" else {return nil}
        let by=calendar.component(.year,from:b),gy=calendar.component(.year,from:g)
        let bd=calendar.ordinality(of:.day,in:.year,for:b)!,gd=calendar.ordinality(of:.day,in:.year,for:g)!
        func leap(_ y:Int)->Bool {y%4==0 && (y%100 != 0 || y%400==0)}
        let years=gy-by,delta=bd-gd
        let age:Int
        if delta>=2 {age=years-1}
        else if delta<=(-2) {age=years}
        else {
            let birthday:Int
            if !leap(gy) && leap(by) {birthday=bd-(bd>59 ? 1 : 0)}
            else if leap(gy) && !leap(by) && bd>60 {birthday=bd+1}
            else {birthday=bd}
            age=years-(gd<birthday ? 1 : 0)
        }
        return min(100,max(14,age))
    }
}
