import Foundation

@main struct RoleFocusTests {
    static func main() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) throws {
            checks+=1
            if !value {throw NSError(domain:"RoleFocusTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
        }
        struct Matrix:Decodable {let attributes:[String];let profiles:[String:String]}
        let matrix=try JSONDecoder().decode(Matrix.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let valid=Set(technical+mental+physical+goalkeeper)
        let profiles=RoleFocusCatalog.profiles
        try check(profiles.count==85 && Set(profiles.map(\.id)).count==85,"85 unique role/duty profiles")
        try check(Set(profiles.map(\.role)).count==45,"45 named roles")
        try check(Set(matrix.profiles.keys)==Set(profiles.map(\.id)),"Complete public matrix coverage")
        try check(Set(matrix.attributes)==valid,"Every matrix attribute uses a current Touchline identifier")
        for profile in profiles {
            try check(!profile.key.isEmpty,"Nonempty key tier: \(profile.id)")
            try check(profile.key.isDisjoint(with:profile.preferable),"No contradictory tiers: \(profile.id)")
            try check(profile.key.union(profile.preferable).isSubset(of:valid),"Valid identifiers: \(profile.id)")
            let cells=Array(matrix.profiles[profile.id]!)
            try check(cells.count==matrix.attributes.count,"Matrix shape")
            for (index,key) in matrix.attributes.enumerated() {
                let expected:RoleAttributeTier?=cells[index]=="g" ? .key : (cells[index]=="b" ? .preferable : nil)
                try check(profile.tier(for:key)==expected,"Public matrix \(profile.id)/\(key)")
            }
            for excluded in ["height","weight","left_foot","right_foot","consistency","professionalism","traits"] {
                try check(profile.tier(for:excluded)==nil,"Non-attribute excluded: \(excluded)")
            }
        }
        let groups=RoleFocusCatalog.groups
        try check(groups.count==14 && Set(groups.map(\.id)).count==14,"14 unique position groups")
        try check(Set(groups.flatMap(\.roles))==Set(profiles.map(\.role)),"Every role reachable through position cascade")
        for group in groups {
            try check(Set(group.roles).count==group.roles.count,"No duplicate menu roles")
            for role in group.roles {
                let duties=RoleFocusCatalog.byRole[role] ?? []
                try check(!duties.isEmpty,"No dead-end role menu")
                try check(Set(duties.map(\.duty)).count==duties.count,"No duplicate duty items")
            }
        }
        try check(groups.first {$0.id=="GK"}!.roles==["gk","sk"],"GK menu contains only keeper roles")
        try check(groups.first {$0.id=="AMC"}!.roles==["am","ap","t","eng","ss"],"AMC role membership")
        try check(RoleFocusCatalog.byRole["lib"]!.map(\.duty)==[.defend,.support],"FM24 Libero duties")
        try check(RoleFocusCatalog.byRole["ifb"]!.map(\.duty)==[.defend],"FM24 Inverted Full-Back duty")
        try check(RoleFocusCatalog.byID["ifb-defend"]!.key==Set(["heading","marking","tackling","positioning","strength"]),"Independent official IFB key-attribute cross-check")
        let overlap=RoleFocusProfile("test","Test",.support,"passing","passing vision")
        try check(overlap.tier(for:"passing") == .key,"Key takes precedence defensively")
        var state=RoleFocusState()
        try check(state.profile==nil && state.label=="Role Focus","Default is no role focus")
        for profile in profiles {
            state.select(profile.id)
            try check(state.profileID==profile.id && state.label==profile.label,"Selection/label: \(profile.id)")
        }
        state.select("af-attack")
        try check(state.label=="Advanced Forward (At)","Compact selected label")
        state.select("af-defend")
        try check(state.profileID=="af-attack","Invalid combination cannot be selected")
        state.select(nil)
        try check(state.label=="Role Focus" && valid.allSatisfy {state.tier(for:$0)==nil},"Clear removes every highlight")
        print("Role focus: \(checks) checks passed (85 profiles × 47 public matrix cells; no AppKit/GUI).")
    }
}
