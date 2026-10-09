"""Small synthetic snapshot for portable query tests; no live/captured database input."""
import json
import pathlib
import sys

def fixture():
    players=[]
    for i,name in enumerate(['Synthetic Forward','Synthetic Keeper','Synthetic Free Agent','Synthetic Midfielder']):
        free=i==2
        club={'status':'verified','nameStatus':'verified','name':'Synthetic Parent Club','uid':1}
        transfers={
            'currentTeam':{'status':'verified'},'currentClub':dict(club,uid=2),
            'employmentContract':{'status':'unavailable' if free else 'verified','team':{'status':'verified','club':club}},
            'weeklyWage':{'status':'unavailable' if free else 'verified','raw':None if free else 10000+i},
            'contractExpiry':{'status':'derived','date':'2028-06-30'},'playerValue':{'status':'unresolved'},
            'askingPrice':{'status':'verified','raw':1000*i},'auxiliaryContracts':{'status':'unavailable'},
            'loanState':{'status':'unresolved'},'freeAgentState':{'status':'derived','value':free}}
        players.append({'uid':100+i,'entity':200+i,'name':name,'birthDate':'2000-01-01','age':20+i,
            'ca':140+i,'pa':180,'positions':{'GK' if i==1 else 'ST':20},
            'visibleAttributes':{'pace':15},'hiddenAttributes':{'consistency':12},'footStrengths':{},
            'personalityComponents':{},'reputation':{'rawSlots':[]},'traits':{'mapped':[],'unresolvedBits':[]},
            'fieldStatus':{'age':'derived'},'nationality':{'status':'verified','name':'Synthetic Nation'},'transfers':transfers})
    return {'modelVersion':3,'capturedAt':'2026-01-01T00:00:00.000Z','elapsedSeconds':0,
            'collection':{'count':len(players)},'players':players}

if __name__=='__main__':pathlib.Path(sys.argv[1]).write_text(json.dumps(fixture()))
