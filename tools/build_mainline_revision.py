"""Compile the user's read-only revised script and copy original expression PNGs.

No image transformations, inferred combat results or invented dialogue.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('C:/Users/myzpw/AppData/Local/Temp/codex-file-preview-A43Kmq/无敌厨神_主线剧本修订稿(2).docx')
ART = Path('C:/Users/myzpw/Desktop/画画/project nju gaming')
CAST = {'焰子':'hero','阿铃':'aling','罗金娜':'chen','罗厄':'luo','维托':'vito','赫兹':'hertz','希娜':'hina'}
MOODS = {'通常':'calm','生气':'angry','高兴':'happy','得意':'proud','哭哭':'cry','疑惑':'puzzled','困扰':'troubled','无语':'speechless'}
BACKGROUNDS = ['harbor','old-stall','ingredient-shop','knight-hall','riverside-diner','ingredient-shop','palace','harbor-square']

# Same magnification for all original 2560-square canvases; only face anchors differ.
HALF_SCALE = 2.15
FOCUS = {'hero':(.49,.26),'aling':(.50,.19),'chen':(.44,.23),'luo':(.51,.30),'vito':(.46,.235),'hertz':(.54,.19),'hina':(.50,.23)}
def half_body(actor):
    face_x, face_y = FOCUS[actor]
    width = 760 * .64 * HALF_SCALE
    height = 605 * HALF_SCALE
    x = (.26 if actor == 'hero' else .74) - (face_x-.5)*width/1280
    top = 270 - face_y*width
    bottom = top+(height+width)/2
    return f'td:{x:.6f}:{bottom/800:.6f}:{HALF_SCALE:.6f}'

def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')

def main():
    source_dir = ROOT/'docs/source/mainline-20261126'
    source_dir.mkdir(parents=True,exist_ok=True)
    saved_source=source_dir/'无敌厨神_主线剧本修订稿(2).docx'
    if not saved_source.exists(): shutil.copy2(SOURCE,saved_source)
    with zipfile.ZipFile(saved_source) as package:
        xml=ET.fromstring(package.read('word/document.xml'))
    ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    paragraphs=[''.join(t.text or '' for t in p.findall('.//w:t',ns)) for p in xml.findall('.//w:body//w:p',ns)]
    hashes=[]
    cast_resources=[]
    for name, actor in CAST.items():
        if actor == 'hina': continue
        for original in sorted((ART/name).glob('*.png')):
            mood=MOODS[original.stem]
            target=ROOT/f'assets/characters/mainline-20261126/{actor}/{mood}.png'
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(original,target)
            w,h=struct.unpack('>II',original.read_bytes()[16:24])
            write(f'content/story/vn/portraits/{actor}/{actor}_base_base_{mood}_mid.tres',f'''[gd_resource type="AtlasTexture" format=3]
[ext_resource type="Texture2D" path="res://assets/characters/mainline-20261126/{actor}/{mood}.png" id="1"]
[resource]
atlas = ExtResource("1")
region = Rect2(0, 0, {w}, {h})
filter_clip = true
''')
            hashes.append({'actor':actor,'expression':mood,'label':original.stem,'path':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'size':[w,h]})
        cast_resources.append(f'''[sub_resource type="Resource" id="cast_{actor}"]
script = ExtResource("member")
id = "{actor}"
display_name = "{name}"
default_outfit = "base"
default_pose = "base"
default_expression = "calm"
sprite_scale = 0.64
side_image = false
blip = "off"
''')
    # Hina uses a runtime text label, not an invented illustration.
    cast_resources.append('''[sub_resource type="Resource" id="cast_hina"]
script = ExtResource("member")
id = "hina"
display_name = "希娜"
default_outfit = "base"
default_pose = "base"
default_expression = "calm"
sprite_scale = 0.64
blip = "off"
''')
    cast_resources.append('''[sub_resource type="Resource" id="cast_crowd"]
script = ExtResource("member")
id = "crowd"
display_name = "居民"
blip = "off"
''')
    write('content/story/vn/config/characters/_characters.tres','''[gd_resource type="Resource" script_class="VNEngineCast" format=3]
[ext_resource type="Script" path="res://addons/vn_engine/src/defs/cast_member.gd" id="member"]
[ext_resource type="Script" path="res://addons/vn_engine/src/defs/cast.gd" id="cast"]
'''+ '\n'.join(cast_resources)+'\n[resource]\nscript = ExtResource("cast")\ncharacters = Array[ExtResource("member")](['+', '.join(f'SubResource("cast_{a}")' for a in list(CAST.values())+['crowd'])+'])\n')
    chapters=[];nodes=[];current=None
    def segment():
        nonlocal current
        if current and current['lines']:
            script='\n'.join(current.pop('lines'))+'\n@end\n'
            path=f'content/story/vn/scenario/{current["id"]}/script.txt'
            write(path,script);current['path']='res://'+path;nodes.append(current)
        current=None
    for index,line in enumerate(paragraphs):
        line=line.strip()
        if not line: continue
        heading=re.match(r'^第[一二三四五六七八]场\s+(.+)',line)
        if heading:
            segment();chapters.append({'number':len(chapters)+1,'title':line,'background':BACKGROUNDS[len(chapters)],'source_paragraph':index+1,'rows':[]})
            continue
        if not chapters: continue
        chapter=chapters[-1]
        if line.startswith('场景：'): chapter['location']=line[3:];continue
        if line=='全剧终': continue
        if line.startswith('【操作·'):
            segment();kind='battle' if '战斗' in line.split('】')[0] else ('evaluation' if '评鉴' in line else ('freeplay' if '自由经营' in line else 'preparation'))
            node={'id':f'revised_{len(nodes):02d}','chapter':chapter['number'],'title':chapter['title'],'kind':kind,'description':line,'source_paragraph':index+1,'implemented':kind=='freeplay','music':'boss' if chapter['number']==8 and kind=='battle' else ('cooking' if kind=='battle' else 'casual')}
            nodes.append(node);chapter['rows'].append({'kind':'operation','text':line,'source_paragraph':index+1});continue
        match=re.match(r'^【([^】]+)】([^：]+)：(.*)$',line)
        if match:
            mood,name,text=match.groups();actor=CAST[name];expression=MOODS[mood]
            assert actor=='hina' or (ROOT/f'assets/characters/mainline-20261126/{actor}/{expression}.png').exists(),line
            row={'kind':'dialogue','actor':actor,'name':name,'expression':expression,'expression_label':mood,'text':text,'source_paragraph':index+1}
        elif line.startswith('旁白：'): row={'kind':'narration','text':line[3:],'source_paragraph':index+1}
        else: raise ValueError('Unparsed script paragraph: '+line)
        chapter['rows'].append(row)
        if current is None:
            current={'id':f'revised_{len(nodes):02d}','chapter':chapter['number'],'title':chapter['title'],'kind':'dialogue','source_paragraph':index+1,'lines':['# start',f'@bg {chapter["background"]} with instant 0']}
        if row['kind']=='dialogue':
            actor=row['actor'];side='left' if actor=='hero' else 'right'
            for other in CAST.values():
                if actor != 'hero' and other not in ['hero',actor]: current['lines'].append(f'@hide {other} with instant')
            current['lines'].extend([f'// 原稿第 {index+1} 段 【{mood}】{name}',f'@show {actor} {expression} at {half_body(actor)} with instant',f'{actor}: {text}'])
        else: current['lines'].extend([f'// 原稿第 {index+1} 段',f'narrator: {row["text"]}'])
    segment()
    # A clearly marked read-only full-scene preview includes post-battle dialogue.
    for chapter in chapters:
        script=['# start',f'@bg {chapter["background"]} with instant 0','narrator: 【剧本预览】本场可查看完整台词，战斗和经营结果不写入正式进度。']
        for row in chapter['rows']:
            if row['kind']=='dialogue':
                a=row['actor']
                script.extend(f'@hide {other} with instant' for other in CAST.values() if a != 'hero' and other not in ['hero',a])
                script.extend([f'@show {a} {row["expression"]} at {half_body(a)} with instant',f'{a}: {row["text"]}'])
            else: script.append('narrator: '+('【接口留白】' if row['kind']=='operation' else '')+row['text'])
        script.append('@end');chapter['preview']=f'res://content/story/vn/scenario/revised_preview_{chapter["number"]:02d}/script.txt'
        write(chapter['preview'][6:],'\n'.join(script)+'\n')
    data={'schema_version':1,'revision':'20261126','source_sha256':hashlib.sha256(saved_source.read_bytes()).hexdigest(),'expressions':MOODS,'cast':CAST,'chapters':chapters,'nodes':nodes,'portraits':hashes,'combat_implemented':False}
    write('content/story/mainline-20261126.json',json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    presentation=json.loads((ROOT/'content/story/vn/presentation.json').read_text(encoding='utf-8'))
    for n in nodes:
        if n['kind']=='dialogue': presentation['chapters'][n['id']]={'title':n['title'],'path':n['path']}
    for c in chapters: presentation['chapters'][f'revised_preview_{c["number"]:02d}']={'title':c['title']+'（预览）','path':c['preview']}
    write('content/story/vn/presentation.json',json.dumps(presentation,ensure_ascii=False,indent=2)+'\n')
    print('Compiled:',len(chapters),'scenes,',len(nodes),'nodes,',len(hashes),'original expressions')

if __name__=='__main__': main()
