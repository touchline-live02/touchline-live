import Foundation

/// FM24's visible attribute tiers only; no rating weights or player inference.
enum RoleAttributeTier { case key, preferable }

enum RoleDuty:String,CaseIterable {
    case defend,support,attack,stopper,cover
    var name:String {rawValue.capitalized}
    var abbreviation:String {
        switch self {
        case .defend:return "De"
        case .support:return "Su"
        case .attack:return "At"
        case .stopper:return "St"
        case .cover:return "Co"
        }
    }
}

struct RoleFocusProfile {
    let role:String
    let name:String
    let duty:RoleDuty
    let key:Set<String>
    let preferable:Set<String>
    var id:String {role+"-"+duty.rawValue}
    var label:String {name+" ("+duty.abbreviation+")"}
    init(_ role:String,_ name:String,_ duty:RoleDuty,_ key:String,_ preferable:String) {
        self.role=role;self.name=name;self.duty=duty
        self.key=Set(key.split(separator:" ").map(String.init))
        self.preferable=Set(preferable.split(separator:" ").map(String.init))
    }
    func tier(for attribute:String)->RoleAttributeTier? {
        if key.contains(attribute) {return .key}
        return preferable.contains(attribute) ? .preferable : nil
    }
}

struct RolePositionGroup {
    let id:String
    let name:String
    let roles:[String]
    init(_ id:String,_ name:String,_ roles:String) {
        self.id=id;self.name=name;self.roles=roles.split(separator:" ").map(String.init)
    }
}

/// Session-only presentation state, shared by the menu and attribute renderer.
/// Selecting a player or switching projection does not mutate this state.
struct RoleFocusState {
    private(set) var profileID:String?
    var profile:RoleFocusProfile? {profileID.flatMap {RoleFocusCatalog.byID[$0]}}
    var label:String {profile?.label ?? "Role Focus"}
    mutating func select(_ id:String?) {
        guard let id=id else {profileID=nil;return}
        guard RoleFocusCatalog.byID[id] != nil else {return}
        profileID=id
    }
    func tier(for attribute:String)->RoleAttributeTier? {profile?.tier(for:attribute)}
}

enum RoleFocusCatalog {
    // FM24 key/preferable attribute tiers; source attribution: docs/ATTRIBUTION.md.
    static let profiles:[RoleFocusProfile]=[
        RoleFocusProfile("gk","Goalkeeper",.defend,"concentration positioning agility aerial_reach command_of_area communication handling kicking reflexes","anticipation decisions one_on_ones throwing"),
        RoleFocusProfile("sk","Sweeper Keeper",.defend,"anticipation concentration positioning agility command_of_area kicking one_on_ones reflexes","first_touch passing composure decisions vision acceleration aerial_reach communication handling rushing_out throwing"),
        RoleFocusProfile("sk","Sweeper Keeper",.support,"anticipation composure concentration positioning agility command_of_area kicking one_on_ones reflexes rushing_out","first_touch passing decisions vision acceleration aerial_reach communication handling throwing"),
        RoleFocusProfile("sk","Sweeper Keeper",.attack,"anticipation composure concentration positioning agility command_of_area kicking one_on_ones reflexes rushing_out","first_touch passing decisions vision acceleration aerial_reach communication eccentricity handling throwing"),
        RoleFocusProfile("cd","Central Defender",.defend,"heading marking tackling positioning jumping_reach strength","aggression anticipation bravery composure concentration decisions pace"),
        RoleFocusProfile("cd","Central Defender",.stopper,"heading tackling aggression bravery decisions positioning jumping_reach strength","marking anticipation composure concentration"),
        RoleFocusProfile("cd","Central Defender",.cover,"marking tackling anticipation concentration decisions positioning pace","heading bravery composure jumping_reach strength"),
        RoleFocusProfile("ncb","No-Nonsense Centre-Back",.defend,"heading marking tackling positioning jumping_reach strength","aggression anticipation bravery concentration pace"),
        RoleFocusProfile("ncb","No-Nonsense Centre-Back",.stopper,"heading tackling aggression bravery positioning jumping_reach strength","marking anticipation concentration"),
        RoleFocusProfile("ncb","No-Nonsense Centre-Back",.cover,"marking tackling anticipation concentration positioning pace","heading bravery jumping_reach strength"),
        RoleFocusProfile("bpd","Ball-Playing Defender",.defend,"heading marking passing tackling composure positioning jumping_reach strength","first_touch technique aggression anticipation bravery concentration decisions vision pace"),
        RoleFocusProfile("bpd","Ball-Playing Defender",.stopper,"heading passing tackling aggression bravery composure decisions positioning jumping_reach strength","first_touch marking technique anticipation concentration vision"),
        RoleFocusProfile("bpd","Ball-Playing Defender",.cover,"marking passing tackling anticipation composure concentration decisions positioning pace","first_touch heading technique bravery vision jumping_reach strength"),
        RoleFocusProfile("lib","Libero",.defend,"first_touch heading marking passing tackling technique composure decisions positioning teamwork jumping_reach strength","anticipation bravery concentration pace stamina"),
        RoleFocusProfile("lib","Libero",.support,"first_touch heading marking passing tackling technique composure decisions positioning teamwork jumping_reach strength","dribbling anticipation bravery concentration vision pace stamina"),
        RoleFocusProfile("wcb","Wide Centre-Back",.defend,"heading marking tackling positioning jumping_reach strength","dribbling first_touch passing technique aggression anticipation bravery composure concentration decisions work_rate agility pace"),
        RoleFocusProfile("wcb","Wide Centre-Back",.support,"dribbling heading marking tackling positioning jumping_reach pace strength","crossing first_touch passing technique aggression anticipation bravery composure concentration decisions off_the_ball work_rate agility stamina"),
        RoleFocusProfile("wcb","Wide Centre-Back",.attack,"crossing dribbling heading marking tackling off_the_ball jumping_reach pace stamina strength","first_touch passing technique aggression anticipation bravery composure concentration decisions positioning work_rate agility"),
        RoleFocusProfile("nfb","No-Nonsense Full-Back",.defend,"marking tackling anticipation positioning strength","heading aggression bravery concentration teamwork"),
        RoleFocusProfile("fb","Full-Back",.defend,"marking tackling anticipation concentration positioning","crossing passing decisions teamwork work_rate pace stamina"),
        RoleFocusProfile("fb","Full-Back",.support,"marking tackling anticipation concentration positioning teamwork","crossing dribbling passing technique decisions work_rate pace stamina"),
        RoleFocusProfile("fb","Full-Back",.attack,"crossing marking tackling anticipation positioning teamwork","dribbling first_touch passing technique concentration decisions off_the_ball work_rate agility pace stamina"),
        RoleFocusProfile("ifb","Inverted Full-Back",.defend,"heading marking tackling positioning strength","dribbling first_touch passing technique aggression anticipation bravery composure concentration decisions work_rate agility jumping_reach pace"),
        RoleFocusProfile("wb","Wing-Back",.defend,"marking tackling anticipation positioning teamwork work_rate acceleration stamina","crossing dribbling first_touch passing technique concentration decisions off_the_ball agility balance pace"),
        RoleFocusProfile("wb","Wing-Back",.support,"crossing dribbling marking tackling off_the_ball teamwork work_rate acceleration stamina","first_touch passing technique anticipation concentration decisions positioning agility balance pace"),
        RoleFocusProfile("wb","Wing-Back",.attack,"crossing dribbling tackling technique off_the_ball teamwork work_rate acceleration pace stamina","first_touch marking passing anticipation concentration decisions flair positioning agility balance"),
        RoleFocusProfile("cwb","Complete Wing-Back",.support,"crossing dribbling technique off_the_ball teamwork work_rate acceleration stamina","first_touch marking passing tackling anticipation decisions flair positioning agility balance pace"),
        RoleFocusProfile("cwb","Complete Wing-Back",.attack,"crossing dribbling technique flair off_the_ball teamwork work_rate acceleration stamina","first_touch marking passing tackling anticipation decisions positioning agility balance pace"),
        RoleFocusProfile("iwb","Inverted Wing-Back",.defend,"passing tackling anticipation decisions positioning teamwork","first_touch marking technique composure concentration off_the_ball work_rate acceleration agility stamina"),
        RoleFocusProfile("iwb","Inverted Wing-Back",.support,"first_touch passing tackling composure decisions teamwork","marking technique anticipation concentration off_the_ball positioning vision work_rate acceleration agility stamina"),
        RoleFocusProfile("iwb","Inverted Wing-Back",.attack,"first_touch passing tackling technique composure decisions off_the_ball teamwork vision acceleration","crossing dribbling long_shots marking anticipation concentration flair positioning work_rate agility pace stamina"),
        RoleFocusProfile("ap","Advanced Playmaker",.support,"first_touch passing technique composure decisions off_the_ball teamwork vision","dribbling anticipation flair agility"),
        RoleFocusProfile("ap","Advanced Playmaker",.attack,"first_touch passing technique composure decisions off_the_ball teamwork vision","dribbling anticipation flair acceleration agility"),
        RoleFocusProfile("anchor","Anchor",.defend,"marking tackling anticipation concentration decisions positioning","composure teamwork strength"),
        RoleFocusProfile("am","Attacking Midfielder",.support,"first_touch long_shots passing technique anticipation decisions flair off_the_ball","dribbling composure vision agility"),
        RoleFocusProfile("am","Attacking Midfielder",.attack,"dribbling first_touch long_shots passing technique anticipation decisions flair off_the_ball","finishing composure vision agility"),
        RoleFocusProfile("bwm","Ball-Winning Midfielder",.defend,"tackling aggression anticipation teamwork work_rate stamina","marking bravery concentration positioning agility pace strength"),
        RoleFocusProfile("bwm","Ball-Winning Midfielder",.support,"tackling aggression anticipation teamwork work_rate stamina","marking passing bravery concentration agility pace strength"),
        RoleFocusProfile("bbm","Box-to-Box Midfielder",.support,"passing tackling off_the_ball teamwork work_rate stamina","dribbling finishing first_touch long_shots technique aggression anticipation composure decisions positioning acceleration balance pace strength"),
        RoleFocusProfile("car","Carrilero",.support,"first_touch passing tackling decisions positioning teamwork stamina","technique anticipation composure concentration off_the_ball vision work_rate"),
        RoleFocusProfile("cm","Central Midfielder",.defend,"tackling concentration decisions positioning teamwork","first_touch marking passing technique aggression anticipation composure work_rate stamina"),
        RoleFocusProfile("cm","Central Midfielder",.support,"first_touch passing tackling decisions teamwork","technique anticipation composure concentration off_the_ball vision work_rate stamina"),
        RoleFocusProfile("cm","Central Midfielder",.attack,"first_touch passing decisions off_the_ball","long_shots tackling technique anticipation composure teamwork vision work_rate acceleration stamina"),
        RoleFocusProfile("dlp","Deep-Lying Playmaker",.defend,"first_touch passing technique composure decisions teamwork vision","tackling anticipation positioning balance"),
        RoleFocusProfile("dlp","Deep-Lying Playmaker",.support,"first_touch passing technique composure decisions teamwork vision","anticipation off_the_ball positioning balance"),
        RoleFocusProfile("dm","Defensive Midfielder",.defend,"tackling anticipation concentration positioning teamwork","marking passing aggression composure decisions work_rate stamina strength"),
        RoleFocusProfile("dm","Defensive Midfielder",.support,"tackling anticipation concentration positioning teamwork","first_touch marking passing aggression composure decisions work_rate stamina strength"),
        RoleFocusProfile("dw","Defensive Winger",.defend,"technique anticipation off_the_ball positioning teamwork work_rate stamina","crossing dribbling first_touch marking tackling aggression concentration decisions acceleration"),
        RoleFocusProfile("dw","Defensive Winger",.support,"crossing technique off_the_ball teamwork work_rate stamina","dribbling first_touch marking passing tackling aggression anticipation composure concentration decisions positioning acceleration"),
        RoleFocusProfile("eng","Enganche",.support,"first_touch passing technique composure decisions vision","dribbling anticipation flair off_the_ball agility"),
        RoleFocusProfile("hb","Half Back",.defend,"marking tackling anticipation composure concentration decisions positioning teamwork","first_touch passing aggression bravery work_rate jumping_reach stamina strength"),
        RoleFocusProfile("if","Inside Forward",.support,"dribbling finishing first_touch technique off_the_ball acceleration agility","long_shots passing anticipation composure flair vision work_rate balance pace stamina"),
        RoleFocusProfile("if","Inside Forward",.attack,"dribbling finishing first_touch technique anticipation off_the_ball acceleration agility","long_shots passing composure flair work_rate balance pace stamina"),
        RoleFocusProfile("iw","Inverted Winger",.support,"crossing dribbling passing technique acceleration agility","first_touch long_shots composure decisions off_the_ball vision work_rate balance pace stamina"),
        RoleFocusProfile("iw","Inverted Winger",.attack,"crossing dribbling passing technique acceleration agility","first_touch long_shots anticipation composure decisions flair off_the_ball vision work_rate balance pace stamina"),
        RoleFocusProfile("mez","Mezzala",.support,"passing technique decisions off_the_ball work_rate acceleration","dribbling first_touch long_shots tackling anticipation composure vision balance stamina"),
        RoleFocusProfile("mez","Mezzala",.attack,"dribbling passing technique decisions off_the_ball vision work_rate acceleration","finishing first_touch long_shots anticipation composure flair balance stamina"),
        RoleFocusProfile("rmd","Raumdeuter",.attack,"finishing anticipation composure concentration decisions off_the_ball balance","first_touch technique work_rate acceleration stamina"),
        RoleFocusProfile("reg","Regista",.support,"first_touch passing technique composure decisions flair off_the_ball teamwork vision","dribbling long_shots anticipation balance"),
        RoleFocusProfile("rpm","Roaming Playmaker",.support,"first_touch passing technique anticipation composure decisions off_the_ball teamwork vision work_rate acceleration stamina","dribbling long_shots concentration positioning agility balance pace"),
        RoleFocusProfile("sv","Segundo Volante",.support,"marking passing tackling off_the_ball positioning work_rate pace stamina","finishing first_touch long_shots anticipation composure concentration decisions acceleration balance strength"),
        RoleFocusProfile("sv","Segundo Volante",.attack,"finishing long_shots passing tackling anticipation off_the_ball positioning work_rate pace stamina","first_touch marking composure concentration decisions acceleration balance strength"),
        RoleFocusProfile("ss","Shadow Striker",.attack,"dribbling finishing first_touch anticipation composure off_the_ball acceleration","passing technique concentration decisions work_rate agility balance pace stamina"),
        RoleFocusProfile("wm","Wide Midfielder",.defend,"passing tackling concentration decisions positioning teamwork work_rate","crossing first_touch marking technique anticipation composure stamina"),
        RoleFocusProfile("wm","Wide Midfielder",.support,"passing tackling decisions teamwork work_rate stamina","crossing first_touch technique anticipation composure concentration off_the_ball positioning vision"),
        RoleFocusProfile("wm","Wide Midfielder",.attack,"crossing first_touch passing decisions teamwork work_rate stamina","tackling technique anticipation composure off_the_ball vision"),
        RoleFocusProfile("wp","Wide Playmaker",.support,"first_touch passing technique composure decisions teamwork vision","dribbling off_the_ball agility"),
        RoleFocusProfile("wp","Wide Playmaker",.attack,"dribbling first_touch passing technique composure decisions off_the_ball teamwork vision","anticipation flair acceleration agility"),
        RoleFocusProfile("wtf","Wide Target Forward",.support,"heading bravery teamwork jumping_reach strength","crossing first_touch anticipation off_the_ball work_rate balance stamina"),
        RoleFocusProfile("wtf","Wide Target Forward",.attack,"heading bravery off_the_ball jumping_reach strength","crossing finishing first_touch anticipation teamwork work_rate balance stamina"),
        RoleFocusProfile("w","Winger",.support,"crossing dribbling technique acceleration agility","first_touch passing off_the_ball work_rate balance pace stamina"),
        RoleFocusProfile("w","Winger",.attack,"crossing dribbling technique acceleration agility","first_touch passing anticipation flair off_the_ball work_rate balance pace stamina"),
        RoleFocusProfile("af","Advanced Forward",.attack,"dribbling finishing first_touch technique composure off_the_ball acceleration","passing anticipation decisions work_rate agility balance pace stamina"),
        RoleFocusProfile("cf","Complete Forward",.support,"dribbling first_touch heading long_shots passing technique anticipation composure decisions off_the_ball vision acceleration agility strength","finishing teamwork work_rate balance jumping_reach pace stamina"),
        RoleFocusProfile("cf","Complete Forward",.attack,"dribbling finishing first_touch heading technique anticipation composure off_the_ball acceleration agility strength","long_shots passing decisions teamwork vision work_rate balance jumping_reach pace stamina"),
        RoleFocusProfile("dlf","Deep-Lying Forward",.support,"first_touch passing technique composure decisions off_the_ball teamwork","finishing anticipation flair vision balance strength"),
        RoleFocusProfile("dlf","Deep-Lying Forward",.attack,"first_touch passing technique composure decisions off_the_ball teamwork","dribbling finishing anticipation flair vision balance strength"),
        RoleFocusProfile("f9","False Nine",.support,"dribbling first_touch passing technique composure decisions off_the_ball vision acceleration agility","finishing anticipation flair teamwork balance"),
        RoleFocusProfile("p","Poacher",.attack,"finishing anticipation composure off_the_ball","first_touch heading technique decisions acceleration"),
        RoleFocusProfile("pf","Pressing Forward",.defend,"aggression anticipation bravery decisions teamwork work_rate acceleration pace stamina","first_touch composure concentration agility balance strength"),
        RoleFocusProfile("pf","Pressing Forward",.support,"aggression anticipation bravery decisions teamwork work_rate acceleration pace stamina","first_touch passing composure concentration off_the_ball agility balance strength"),
        RoleFocusProfile("pf","Pressing Forward",.attack,"aggression anticipation bravery off_the_ball teamwork work_rate acceleration pace stamina","finishing first_touch composure concentration decisions agility balance strength"),
        RoleFocusProfile("tf","Target Forward",.support,"heading bravery teamwork balance jumping_reach strength","finishing first_touch aggression anticipation composure decisions off_the_ball"),
        RoleFocusProfile("tf","Target Forward",.attack,"finishing heading bravery composure off_the_ball balance jumping_reach strength","first_touch aggression anticipation decisions teamwork"),
        RoleFocusProfile("t","Trequartista",.attack,"dribbling first_touch passing technique composure decisions flair off_the_ball vision acceleration","finishing anticipation agility balance"),
    ]
    static let byID=Dictionary(uniqueKeysWithValues:profiles.map {($0.id,$0)})
    static let byRole=Dictionary(grouping:profiles,by: \.role)
    static let groups:[RolePositionGroup]=[
        RolePositionGroup("GK","Goalkeeper","gk sk"),
        RolePositionGroup("DR","Defender (Right)","fb wb nfb cwb iwb ifb"),
        RolePositionGroup("DL","Defender (Left)","fb wb nfb cwb iwb ifb"),
        RolePositionGroup("DC","Defender (Centre)","cd lib bpd ncb wcb"),
        RolePositionGroup("WBR","Wing-Back (Right)","wb cwb iwb"),
        RolePositionGroup("WBL","Wing-Back (Left)","wb cwb iwb"),
        RolePositionGroup("DM","Defensive Midfielder","dm dlp bwm anchor hb reg rpm sv"),
        RolePositionGroup("MR","Midfielder (Right)","wm w dw wp iw"),
        RolePositionGroup("ML","Midfielder (Left)","wm w dw wp iw"),
        RolePositionGroup("MC","Midfielder (Centre)","cm dlp ap bbm bwm rpm mez car"),
        RolePositionGroup("AMR","Attacking Midfielder (Right)","w ap if t wtf rmd iw"),
        RolePositionGroup("AML","Attacking Midfielder (Left)","w ap if t wtf rmd iw"),
        RolePositionGroup("AMC","Attacking Midfielder (Centre)","am ap t eng ss"),
        RolePositionGroup("ST","Striker (Centre)","dlf af tf p cf pf t f9"),
    ]
}
