"""Food in the vessel for each named step of the three regional cooking plans.

One entry per authored action, in PLANS order. "+" adds a topping; ">" shows
the physical change over the live operation. The plate uses the recipe artwork.
"""

STAGES = """
C01 bowl:rice wok:egg>curds wok:rice+curds>fried_rice wok:fried_rice+scallion wok:dish
C03 pot:stock+noodles bowl:stock bowl:stock+soy+scallion bowl:noodles+stock>dish
C04 bowl:egg bowl:egg+salt basket:egg>dish
C05 wok:shrimp>pink_shrimp wok:rice+pink_shrimp+ham>fried_rice+pink_shrimp wok:fried_rice+pink_shrimp+scallion wok:dish
C06 bowl:pork+soy wok:pork>pork_seared wok:pork_seared+peppers wok:dish
C07 pot:stock+noodles bowl:soy+scallion bowl:noodles+soy bowl:dish
C08 board:bream+ginger+scallion basket:bream>steamed_bream basket:steamed_bream+soy>dish
C09 bowl:soy+chili wok:chicken>chicken_seared wok:chicken_seared+peanuts wok:dish
C10 wok:mince>mince_seared wok:mince_seared+soy pot:stock+noodles bowl:noodles+mince_seared>dish
C11 wok:belly>belly_brown wok:belly_brown+soy pot:dark_stock+belly_brown wok:belly_brown>dish
C12 bowl:mince bowl:mince+ginger>pork_filling board:open_bun>raw_buns basket:raw_buns>buns
C13 bowl:soy+ginger+chili wok:pork>pork_seared wok:pork_seared+wood_ear+peppers wok:dish
C14 wok:mince>mince_seared wok:mince_seared+chili pot:dark_stock+tofu+mince_seared wok:dish
C15 wok:beef>beef_seared pot:dark_stock+beef_seared pot:dark_stock+beef_seared+scallion pot:stock+noodles bowl:noodles+beef_seared>dish
C16 clay:stock+dry_rice>rice clay:rice+sausage clay:rice+sausage>dish clay:dish
C17 board:raw_duck+soy oven:raw_duck>roast_duck board:wrapper+duck_slices board:duck_wrap>dish
C18 bowl:char_siu bowl:char_siu+soy board:open_pastry>puffs oven:puffs>dish
C19 clay:shells+seafood clay:stock+shells+ginger clay:stock+seafood clay:dark_stock+seafood>dish
C20 bowl:soy+ginger wok:pork>pork_seared wok:pork_seared+peppers board:open_pastry>dumplings basket:dumplings>buns pot:stock+shells board:dish
E01 bowl:dough board:dough>pretzel board:pretzel>salt_pretzel oven:salt_pretzel>dish
E02 pot:stock+pasta skillet:tomatoes>tomato_sauce skillet:tomato_sauce+basil bowl:pasta+tomato_sauce>dish
E03 skillet:onion>onion_brown skillet:onion_brown+butter pot:dark_stock+onion_brown bowl:dark_stock+toast>dish
E04 board:steak+salt skillet:steak>half_steak skillet:half_steak skillet:half_steak>steak_seared skillet:steak_seared+butter>dish
E05 board:dough>pizza_base board:pizza_base+tomato_sauce board:pizza_base+tomato_sauce+cheese oven:pizza_base+tomato_sauce+cheese>dish
E06 pot:stock+pasta skillet:mushrooms skillet:mushrooms+cream bowl:pasta+cream+mushrooms>dish
E07 tray:potatoes tray:potatoes+cream tray:potatoes+cream+cheese oven:potatoes+cheese>dish
E08 board:raw_chicken+butter board:raw_chicken>tied_bird oven:tied_bird>roasting_bird tray:roasting_bird oven:roasting_bird>dish
E09 skillet:dry_rice+shrimp skillet:yellow_rice+shrimp skillet:stock+yellow_rice+shells skillet:yellow_rice+pink_shrimp+shells>dish
E10 pot:dry_rice pot:dry_rice+butter pot:stock+rice>yellow_rice bowl:yellow_rice+cheese>dish
E11 skillet:beef>beef_seared pot:dark_stock+beef_seared pot:dark_stock+beef_seared+carrot pot:dish
E12 pot:stock+knuckle board:knuckle+salt oven:knuckle>crisp_knuckle board:crisp_knuckle+potato_chunks>dish
E13 skillet:mince>mince_seared skillet:tomato_sauce+mince_seared+cream tray:pasta_sheet+mince_seared>raw_layers oven:raw_layers>dish
E14 board:duck_leg+salt pot:oil+duck_leg pot:duck_leg>confit skillet:confit>dish
E15 skillet:dry_rice skillet:yellow_rice skillet:stock+yellow_rice+shells skillet:yellow_rice+shells+pink_shrimp>dish
E16 bowl:batter bowl:batter+butter skillet:batter>crepe_bubbles skillet:crepe_bubbles>crepe skillet:crepe board:crepe+berries>dish
E17 skillet:steak>steak_seared board:steak_seared+mushrooms board:pastry+steak_seared>wellington oven:wellington>dish
E18 bowl:whites bowl:whites+sugar bowl:whites>souffle_mix oven:ramekin>risen
E19 skillet:beef>beef_seared pot:dark_stock+beef_seared pot:dark_stock+beef_seared+carrot oven:duck_leg>confit board:dish
E20 skillet:shrimp+scallop>pink_shrimp+scallop skillet:steak>steak_seared bowl:cream+tomato_sauce oven:potatoes+cheese>gratin bowl:whites>souffle_mix oven:ramekin>risen board:dish
E21 pot:mushrooms+butter pot:cream+mushrooms pot:stock+mushrooms>cream+mushrooms bowl:cream+mushrooms>dish
J01 bowl:rice+salt bowl:rice mat:rice>triangle mat:triangle>onigiri
J02 bowl:egg bowl:egg+stock tamago:egg>soft_egg tamago:soft_egg>omelet_roll tamago:egg_roll_layer>egg_layers tamago:egg_layers>dish
J03 pot:stock+udon bowl:stock+soy bowl:udon+stock bowl:udon+scallion>dish
J04 board:raw_fish+salt grill:raw_fish>half_mackerel grill:half_mackerel>fish_flesh grill:fish_flesh>fish_grilled board:fish_grilled+lemon>dish
J05 skillet:thigh>thigh_seared skillet:thigh_seared skillet:thigh_seared+soy skillet:soy+chicken_seared bowl:rice+chicken_seared>dish
J06 pot:stock+soy pot:stock+chicken>stock+chicken_seared pot:egg+chicken_seared pot:egg+chicken_seared>soft_egg+chicken_seared bowl:rice+curds+chicken_seared>dish
J07 board:cutlet+salt board:cutlet+crumbs>breaded fryer:breaded>cutlet_blond fryer:cutlet_blond fryer:cutlet_blond>cutlet_crisp
J08 bowl:vinegar bowl:rice+vinegar>sushi_rice mat:nori>sheet_filled mat:sheet_filled>sushi_roll
J09 bowl:batter board:shrimp+batter>tempura_wet fryer:tempura_wet>tempura_blond fryer:tempura_blond fryer:tempura_blond>tempura_crisp bowl:tempura_crisp+stock
J10 pot:stock bowl:stock+soy pot:stock+ramen bowl:ramen+chashu+scallion>dish
J11 board:cutlet+crumbs>breaded fryer:breaded>cutlet_crisp pot:stock+soy pot:cutlet_crisp+egg bowl:rice+cutlet_crisp+curds>dish
J12 bowl:vinegar+wasabi bowl:rice+vinegar>sushi_rice mat:sushi_rice>nigiri mat:nigiri+salmon>dish
J13 bowl:miso pot:miso+stock pot:stock+ramen bowl:ramen+miso bowl:ramen+corn>dish
J14 board:eel+soy grill:eel>eel_grilled grill:eel_grilled>eel_skin grill:eel_skin>eel_grilled bowl:rice+eel_grilled>dish
J15 bowl:rice+vinegar bowl:rice>sushi_rice mat:nigiri+salmon mat:sheet_filled>sushi_roll mat:dish
J16 pot:stock>milky_stock pot:milky_stock pot:milky_stock+soy pot:stock+ramen bowl:ramen+chashu+scallion>dish
J17 bowl:batter board:shrimp+batter>tempura_wet fryer:tempura_wet>tempura_crisp bowl:soy+stock bowl:rice+tempura_crisp>dish
J18 basket:eel>eel_steamed board:eel_steamed+soy grill:eel_steamed>eel_grilled grill:eel_grilled>eel_skin grill:eel_skin>dish
J19 bowl:rice+vinegar bowl:rice>sushi_rice mat:nigiri+tuna mat:nigiri+scallop mat:nigiri+salmon mat:dish
J20 bowl:miso+stock basket:shrimp+shells>pink_shrimp+shells grill:raw_fish>fish_grilled bowl:rice+vinegar>sushi_rice mat:nigiri+salmon mat:dish
"""

def bind_stages(aid, authored, sheet):
    entries = FOOD_BY_DISH[aid]
    if len(entries) != len(authored):
        raise ValueError(f"{aid}: expected one illustration per authored step")
    stages = {label: state for (_, label), state in zip(authored, entries)}
    groups = sheet['groups']
    hot = next((stages[g['label']].split(':')[0] for g in groups.values()
                if g['technique'] in ('heat','boil','bake','steam','grill','fry')), None)
    sheet['initial_food_stage'] = entries[0].split(':')[0] + ':empty'
    for key, g in groups.items():
        if key.endswith('-turn'):
            continue  # A simultaneous input never replaces the food in the pan.
        if g['technique'] == 'preheat':
            stage = hot + ':empty'
        elif g['technique'] == 'oil':
            stage = hot + ':oil'
        elif g['technique'] == 'starch':
            stage = 'wok:dish'
        elif key == 'study_finish':
            stage = 'board:dish'
        elif key == 'plate':
            stage = 'plate:dish'
        else:
            stage = stages[g['label']]
        g['food_stage'] = stage

FOOD_BY_DISH = {line.split()[0]: line.split()[1:] for line in STAGES.strip().splitlines()}
