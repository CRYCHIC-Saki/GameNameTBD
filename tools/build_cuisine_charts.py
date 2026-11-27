"""D078 authored culinary plans -> versioned runtime content. No runtime randomness.

The plan is gameplay abstraction, not a real cooking timer. All times/amounts are
AI-088 PROPOSED. Existing source documents and stable recipe IDs remain intact.
"""
from pathlib import Path
import copy
import json
from cuisine_food_stages import bind_stages

ROOT = Path(__file__).resolve().parents[1]

# Each dish has an ordered technique plan. The name following ':' is the action
# shown while the actual QTE runs. Shape/fold/mix do not secretly heat the food.
PLANS = '''
C01 wok|mix:打散米饭,heat:滑炒蛋液,stir:翻散饭粒,season:葱盐提味,stir:扬锅收拢
C02 wok|heat:滑炒鸡蛋,stir:倒入番茄翻炒,season:糖盐调味,stir:收拢蛋块
C03 stockpot|boil:沸水煮面,mix:调清汤底,season:葱油酱油,shape:挑面入碗
C04 steamer|mix:搅匀蛋液,season:轻盐调味,steam:小火隔水蒸蛋
C05 wok|heat:滑炒虾仁,stir:饭粒与配料翻匀,season:盐葱调味,stir:扬锅松饭
C06 wok|season:腌肉丝,heat:肉丝滑散,stir:青椒合炒,stir:沿锅翻匀
C07 stockpot|boil:煮面挑散,season:葱油酱汁,mix:拌匀挂汁,shape:卷面装碗
C08 steamer|season:姜葱料酒,steam:旺汽蒸鱼,season:蒸鱼豉油
C09 wok|season:调糖醋汁,heat:煸香鸡丁,stir:花生辣椒翻炒,stir:收汁挂味
C10 stockpot|heat:煸肉炒酱,season:下炸酱,boil:煮面,mix:浇酱拌面
C11 stockpot|heat:煸肉上色,season:糖色酱香,boil:小火慢炖,stir:收汁翻匀
C12 steamer|mix:调肉馅,season:姜盐入馅,shape:包馅捏褶,steam:上笼蒸熟
C13 wok|season:调鱼香汁,heat:滑炒肉丝,stir:木耳合炒,stir:收汁挂味
C14 wok|heat:煸肉炒酱,season:豆瓣花椒,boil:豆腐煨入味,stir:轻推豆腐
C15 stockpot|heat:煸香牛肉,season:香料入汤,boil:炖牛肉汤,boil:煮面烫熟,shape:浇汤摆肉
C16 claypot|boil:米饭吸水,shape:铺上腊肠,heat:小火焙锅巴,season:淋煲仔汁
C17 oven|season:刷鸭皮酱汁,bake:挂炉烤鸭,shape:片鸭铺饼,shape:卷饼收口
C18 oven|mix:调叉烧馅,season:蜂蜜润馅,shape:包酥叠层,bake:烤酥皮
C19 stockpot|shape:分层码海味,season:酒姜调汤,boil:文火煨汤,boil:聚鲜慢煨
C20 wok|season:调宴席底味,heat:热菜滑炒,stir:荤素合炒,shape:面点整形,steam:蒸点,boil:吊汤,shape:分盘配餐
E01 oven|mix:揉麦芽面团,shape:交叉扭卷,season:撒粗盐,bake:烤麦香表皮
E02 stockpot|boil:煮意面,heat:熬番茄酱,season:罗勒蒜香,mix:酱汁裹面
E03 stockpot|heat:慢炒洋葱,season:黄油调味,boil:熬洋葱汤,shape:覆面包片
E04 skillet|season:盐椒调味,heat:煎第一面,flip:翻面封汁,heat:煎第二面,season:迷迭香黄油
E05 oven|shape:推开饼底,season:抹番茄酱,shape:铺芝士,bake:烤饼边
E06 stockpot|boil:煮面,heat:炒香蘑菇,season:奶油黑椒,mix:收浓挂汁
E07 oven|shape:叠铺土豆片,season:奶油调味,shape:铺芝士,bake:焗出金黄顶层
E08 oven|season:香草黄油涂抹,shape:整形束翅,bake:烤第一段,flip:翻转烤盘,bake:烤香表皮
E09 skillet|heat:炒香海鲜米,season:藏红花油香,boil:吸汤焖饭,heat:收干底层
E10 stockpot|heat:炒米挂油,season:黄油调味,boil:分次吸汤,mix:乳化拌芝士
E11 stockpot|heat:牛肉煎上色,season:红酒香草,boil:慢炖入味,stir:收拢浓汁
E12 oven|boil:煮软猪肘,season:黑椒盐腌,bake:烤脆外皮,shape:配酸菜土豆
E13 oven|heat:炒香肉末,season:肉酱白酱,shape:分层铺面,bake:焗烤定型
E14 stockpot|season:香草腌鸭,heat:低温油封,flip:翻动鸭腿,heat:煎脆鸭皮
E15 skillet|heat:炒香生米,season:藏红花橄榄油,boil:海鲜汤焖饭,mix:收汁拌匀
E16 skillet|mix:调可丽饼面糊,season:糖油调味,shape:摊薄饼皮,heat:烘第一面,flip:翻薄饼,shape:包莓果
E17 oven|heat:封煎牛排,season:蘑菇酱调味,shape:酥皮包裹,bake:控制中心熟度
E18 oven|mix:打发蛋白,season:糖香草,fold:轻翻拌蛋糊,bake:烘起舒芙蕾
E19 stockpot|heat:分批煎肉,season:红酒香草,boil:慢炖主菜,bake:鸭肉烤香,shape:宴席分盘
E20 skillet|heat:海鲜快煎,flip:牛排翻面,season:两款酱汁,bake:土豆焗烤,fold:甜点翻拌,bake:烘甜点,shape:品鉴摆盘
E21 stockpot|heat:黄油炒香菌菇,season:加奶油与盐,boil:小火煨浓汤,mix:搅匀装碗
J01 sushi|season:盐饭调味,mix:松饭,shape:三角饭团,shape:包海苔
J02 tamago|mix:调蛋液,season:出汁甜味,heat:摊薄蛋液,roll:卷起蛋层,heat:补煎蛋层,roll:整形成卷
J03 stockpot|boil:煮乌冬,season:出汁调汤,mix:挑面入汤,shape:撒葱装碗
J04 grill|season:撒盐,grill:炙烤鱼皮,flip:翻鱼,grill:烤熟鱼肉,shape:配柠檬
J05 skillet|heat:煎鸡皮,flip:翻鸡肉,season:照烧酱,stir:收汁裹鸡,shape:盖饭
J06 stockpot|season:调丼汁,boil:煮鸡肉,fold:分次淋蛋,boil:凝固蛋液,shape:滑入饭碗
J07 fryer|season:盐腌肉排,shape:裹粉蛋面包糠,fry:油炸定型,flip:翻排,fry:炸酥外壳
J08 sushi|season:调寿司醋,fold:切拌醋饭,shape:铺饭黄瓜,roll:卷紧寿司
J09 fryer|mix:轻拌天妇罗糊,shape:食材挂糊,fry:下锅定型,flip:拨散翻面,fry:炸脆捞出,season:配出汁
J10 stockpot|boil:熬清骨汤,season:酱油汤底,boil:煮拉面,shape:码叉烧葱花
J11 fryer|shape:裹糠肉排,fry:炸猪排,season:丼汁调味,boil:蛋液焖排,shape:盖饭
J12 sushi|season:调醋与芥末,fold:切拌醋饭,shape:握饭团,shape:覆三文鱼
J13 stockpot|season:化开味噌,boil:煮浓汤,boil:煮面,mix:汤面合碗,shape:铺玉米
J14 grill|season:刷鳗汁,grill:炙烤鳗鱼,flip:翻面补汁,grill:烤香收汁,shape:盖饭
J15 sushi|season:调醋饭,fold:切拌米饭,shape:握鱼寿司,roll:海苔卷,shape:拼盘
J16 stockpot|boil:大火熬乳白骨汤,mix:搅拌乳化汤底,season:调豚骨汤,boil:煮硬芯拉面,shape:叉烧装碗
J17 fryer|mix:调炸糊,shape:挂糊,fry:炸虾蔬菜,season:天丼汁,shape:铺炸物盖饭
J18 grill|steam:预蒸鳗鱼,season:刷蒲烧汁,grill:炭火炙烤,flip:翻鳗,grill:反复烤香
J19 sushi|season:主厨醋饭,fold:切拌降温,shape:握金枪鱼,shape:握贝柱,shape:握三文鱼,shape:组合摆盘
J20 sushi|season:调出汁味噌,steam:蒸海鲜,grill:烤鱼,fold:拌寿司饭,shape:握寿司,shape:怀石分皿
'''

def read(path): return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path, obj): (ROOT/path).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def chart(identity, name, steps, seasonings, ordinal, tier, study=False):
    groups={}; rows={}; at=5.; serial=0
    # Stable per-dish motif, with different phrase lengths, rests, holds and
    # temperatures. Research adds one phrase and denser syncopation, not narrower windows.
    motif=['left','up','right','down']
    def note(t,group,op,action,form='tap',track='hand',**extra):
        row=rows.setdefault(t,{'t':t,'lanes':{}})
        assert track not in row['lanes']
        row['lanes'][track]=dict(group=group,op=op,input=action,form=form,**extra)
    for technique,label in steps:
        serial+=1; group=f'step{serial}'
        op={'mix':'stir','fold':'stir','shape':'stir','roll':'stir','flip':'stir','bake':'heat','grill':'heat','fry':'heat','oil':'season'}.get(technique,technique)
        params={}; definition={'operation':op,'label':label,'technique':technique,'parameters':params}
        if op=='preheat':
            note(at,group,op,'primary');at+=8
        elif technique=='oil':
            params.update(ingredient_id='oil',amount=.1,mode='common')
            for i,action in enumerate(['left','up','primary']):note(at+i*1.5,group,op,action)
            at+=9
        elif op=='season':
            if not seasonings:continue
            group='season' if 'season' not in groups else group
            params.update(ingredient_id=seasonings[0],amount=.1,mode='precise')
            definition['pour_rate_per_sec']=.2
            for i,spice in enumerate(seasonings[:5]):
                hold=1.+((ordinal+i+serial)%4)*.5
                note(at,group,op,'spice:'+spice,'hold','mouse',hold_beats=hold)
                at+=hold*1.5+3
            at+=len(seasonings[:5])+4
        elif op in ('heat','boil'):
            duration=6+tier*2+(ordinal+serial)%5+(4 if study else 0)
            center={'bake':.62,'fry':.7,'grill':.75,'boil':.48}.get(technique,.6)+((ordinal%5)-2)*.025
            definition['control']={'target_min':round(center-.12,3),'target_max':round(center+.12,3),'initial_value':.3}
            for i in range(duration):note(at+i,group,op,'Mouse','hold','mouse')
            # Wok/saute needs simultaneous hand work. Oven baking does not.
            if technique=='heat':
                parallel=group+'-turn';groups[parallel]={'operation':'stir','technique':'stir','label':'翻动食材 · 保持火候','parameters':{}}
                count=min(6,3+tier//2)
                for i in range(count):note(at+2+i,parallel,'stir',motif[(ordinal+serial+i)%4] if i<count-1 else 'primary')
            at+=duration+5
        elif op in ('plate','steam'):
            count=3+(ordinal+serial)%4+(1 if study else 0)
            for i in range(count):note(at+i,group,op,'primary','hold')
            at+=count+10
        else:
            if op=='starch':params.update(ingredient_id='starch',amount=.1)
            count=min(7,3+tier//2+(1 if study else 0))
            for i in range(count):
                action='primary' if i==count-1 else motif[(ordinal//(4**(i%3))+serial+i)%4]
                note(at,group,op,action)
                at+=(1 if tier>=3 or study else 2)+(.5 if (ordinal+serial+i)%3==0 else 0)
            at+=4
        groups[group]=definition
    if study:
        group='study_finish';groups[group]={'operation':'stir','technique':'shape','label':'研习 · 成品整形','parameters':{}}
        for i in range(6):note(at+i,group,'stir',motif[(ordinal+i)%4] if i<5 else 'primary')
        at+=11
    group='plate';groups[group]={'operation':'plate','technique':'plate','label':'把握完成时机','parameters':{}}
    at=int(at)+1
    for i in range(4+ordinal%4):note(at+i,group,'plate','primary','hold')
    return dict(id=identity,dish=name,bpm=140,preview_beats=2,groups=groups,beats=[rows[t] for t in sorted(rows)])

def main():
    materials=read('content/culinary_materials.json');atlas=read('content/research/recipe_atlas.json')
    service=read('content/service_content.json');old=read('content/research/runtime_recipes.json')
    shipped_world={r['service_recipe']:r for r in read('content/phase3_world.json')['dishes'] if r.get('service_recipe')}
    definitions={x['id']:x for x in read('content/cooking_system.json')['ingredients']}
    definitions.update({k:v['definition'] for k,v in materials['items'].items()})
    old_recipes={r['id']:r for r in service['recipes']};old_recipes.update({d['recipe']['id']:d['recipe'] for d in old['dishes']})
    legacy={'C01':'study.egg_fried_rice','C02':'service.tomato_egg','C03':'study.yangchun_noodles','C04':'study.steamed_egg','C09':'service.kungpao','C14':'service.mapo_tofu'}
    plan={}
    for line in PLANS.strip().splitlines():
        header,body=line.split('|'); aid,station=header.split();plan[aid]=(station,[p.split(':') for p in body.split(',')])
    assert set(plan)=={r['id'] for r in atlas['recipes']}
    nodes={r['id']:r for r in atlas['recipes']};dishes=[];sheets={}
    towns={'cn':'chengdu','eu':'paris','jp':'tokyo'}
    cultures={'cn':'chinese','eu':'continental','jp':'japanese'}
    for index,m in enumerate(materials['recipes']):
        aid=m['id']; station,authored=plan[aid];steps=copy.deepcopy(authored); tier=int(nodes[aid]['tier']);rid=legacy.get(aid,'study.'+aid.lower())
        primary=list(m['ingredients']);spices=list(dict.fromkeys(m['seasonings']))
        # Preserve pre-D078 saved plan identities/primary contracts for existing dishes.
        if rid in old_recipes:primary=[r['id'] for r in old_recipes[rid]['required_ingredients']]
        spices=[x for x in spices if definitions[x]['category']=='seasoning']
        thermal=next((i for i,(t,_) in enumerate(steps) if t in ['heat','boil','steam','bake','fry','grill']),None)
        if thermal is not None:
            ignition=[['preheat','预热点火' if station!='oven' else '烤箱预热']]
            if station=='wok' and 'oil' in spices:ignition.append(['oil','下油滑锅'])
            steps[thermal:thermal]=ignition
        if aid in ['C02','C09','C14']:
            # Preserve the documented Chinese wok finishing contract.
            steps.append(['starch','勾芡收汁'])
            if 'starch' not in spices:spices.append('starch')
        primary=list(dict.fromkeys(primary+[x for x in m['seasonings'] if definitions[x]['category']!='seasoning' and x not in primary]))
        hot=any(t in ['heat','boil','steam','bake','fry','grill'] for t,_ in steps)
        recipe=copy.deepcopy(old_recipes.get(rid,old_recipes['service.tomato_egg']))
        recipe.update(id=rid,name=m['name'],cuisine_id=m['cuisine_id'],workstation=station,cooking_method='steam' if station=='steamer' else 'stir',guided_profile=rid,version=2,expects_aroma=False,expected_aroma=[],allowed_ingredients=list(dict.fromkeys(primary+spices)),seasoning_palette=spices,preparation_sheets={},required_ingredients=[dict(id=x,min_amount=1,min_fine=0,max_fine=1,min_heat_dose=.2 if hot else 0) for x in primary],required_steps=[],recommended_steps=[],source='AI-088 PROPOSED; recipe_atlas + culinary_materials',initially_unlocked=False,ideal_temperature=[40,100] if hot else [15,40])
        recipe['technique_plan']=[{'technique':t,'label':l} for t,l in steps]
        sheet=chart(rid,m['name'],steps,spices,index,tier);study=chart('lesson.'+aid,m['name']+' · 研习',steps,spices,index,tier,True)
        if aid == 'C02':
            for score in (sheet, study):
                score['initial_food_stage'] = 'wok:empty'
                for key, group in score['groups'].items():
                    if group['technique'] == 'oil':
                        group['food_stage'] = 'wok:oil'
                    elif group['technique'] == 'heat':
                        group['food_stage'] = 'wok:egg>curds'
                    elif group['technique'] == 'stir' and group['label'] == '倒入番茄翻炒':
                        group['food_stage'] = 'wok:curds+tomato_dice>dish'
                    elif key == 'study_finish':
                        group['food_stage'] = 'board:dish'
                    elif key == 'plate':
                        group['food_stage'] = 'plate:dish'
        else:
            for score in (sheet, study):
                bind_stages(aid, authored, score)
        # Challenge length is musical time, not a reason every perfect banquet
        # must burn. Calibrate the authored full heat path to 2.4 food heat units.
        ideal_dose=0.
        for gid,g in sheet['groups'].items():
            notes=[r for r in sheet['beats'] if any(n['group']==gid for n in r['lanes'].values())]
            if g['operation'] in ('heat','boil'):
                ideal_dose+=(notes[-1]['t']-notes[0]['t']+1)*(60/140)*(g['control']['target_min']+g['control']['target_max'])/2
            elif g['operation']=='steam':ideal_dose+=len(notes)*.25
        recipe['thermal_scale']=round(2.4/ideal_dose,6) if ideal_dose else 1.
        sheets[rid]=sheet;sheets[study['id']]=study
        recipe['research_profile']=study['id']
        recipe['recommended_steps']=list(dict.fromkeys(g['operation'] for g in sheet['groups'].values()))
        recipe['required_steps']=[x for x in ['heat','boil','steam'] if x in recipe['recommended_steps']]
        for offset,food in enumerate(primary):
            if 'cuttable' not in definitions[food]['special']:continue
            sid=rid+'.prep.'+food;group={'operation':'cut','technique':'cut','label':m['name']+' · 处理'+definitions[food]['name'],'parameters':{}}
            count=min(12,4+tier+index%3);actions=['primary']*count
            for n in range(2,count,3):actions[n]='rotate_left' if (index+offset+n)%2 else 'rotate_right'
            beats=[{'t':5+i*(1. if tier>=3 else 1.5),'lanes':{'hand':{'group':'cut','op':'cut','input':a,'form':'tap'}}} for i,a in enumerate(actions)]
            sheets[sid]={'id':sid,'dish':m['name'],'bpm':140,'preview_beats':2,'groups':{'cut':group},'beats':beats};recipe['preparation_sheets'][food]=sid
        price=1200+tier*650+index%4*150
        existing=next((d for d in old['dishes'] if d['atlas_id']==aid),None)
        wid=atlas['runtime_mapping'].get(aid,'cuisine_'+aid.lower())
        world=copy.deepcopy(existing['world'] if existing else shipped_world[rid]) if existing or rid in shipped_world else dict(id=wid,name=m['name'],town_id=towns[m['cuisine_id']],culture=cultures[m['cuisine_id']],ingredient_cost=price/300,labor_factor=1+tier*.15,value_offset=0,price=price/100,starter=False,service_recipe=rid,source='AI-088 PROPOSED',research_runtime=True)
        old_offer=next((o for o in service['offers']+[d['offer'] for d in old['dishes']] if o['id']==rid),{})
        recipe['allowed_ingredients']=list(dict.fromkeys(recipe['allowed_ingredients']+old_recipes.get(rid,{}).get('allowed_ingredients',[])))
        offer={'id':rid,'reference_cents':price,'primary':primary,'stock':{**old_offer.get('stock',{}),**{s:1000 for s in spices},**{i:1000 for i in primary}},'source':'AI-088 PROPOSED','parameter_status':'PROPOSED'}
        # A preserved primary (e.g. bean paste in the legacy mapo recipe) can
        # also be poured in M6. The procurement kit must cover both uses.
        for ingredient in set(primary)&set(spices): offer['stock'][ingredient]=2000
        dishes.append(dict(atlas_id=aid,world=world,recipe=recipe,offer=offer))
        atlas['runtime_mapping'][aid]=world['id'];atlas['charts'][aid]={'id':'study.'+aid,'kind':'kitchen','version':3,'recipe_id':rid,'profile':study['id'],'primary':primary}
    write('content/cuisine_recipes.json',dict(schema_version=1,revision=1,parameter_status='PROPOSED',source='AI-088; explicit culinary plans in tools/build_cuisine_charts.py',dishes=dishes,sheets=sheets))
    write('content/research/recipe_atlas.json',atlas)
    print(f'{len(dishes)} dishes; {len(sheets)} cooking/research/preparation charts')

if __name__=='__main__':main()
