extends "res://tests/test_case.gd"

## BattleBackground's reading of battle_bg's layer column (Dc5w1Yda).


func test_a_back_layer_names_its_file_animation_and_offset() -> void:
	var layers: Array = BattleBackground.parse_layers("battle_bg_0005_01.ssbp#battle_bg_0005_01,back/anime,0,216")
	assert_eq(layers, [{"file": "battle_bg_0005_01.ssbp", "animation": "back/anime", "layer": 0, "offset": 216}])


func test_a_front_layer_without_an_offset_reuses_the_one_before() -> void:
	var layers: Array = BattleBackground.parse_layers("battle_bg_0003_01.ssbp#battle_bg_0003_01,back/anime,0,216&battle_bg_0003_01,front/anime,1")
	assert_eq(layers.size(), 2)
	assert_eq(layers[1], {"file": "battle_bg_0003_01.ssbp", "animation": "front/anime", "layer": 1, "offset": 216})


func test_an_explicit_offset_is_kept() -> void:
	var layers: Array = BattleBackground.parse_layers("sg_battle_bg_0037.ssbp#sg_battle_bg_0037,back/anime,0,256&sg_battle_bg_0037,front/anime,2,0")
	assert_eq(layers[0]["offset"], 256)
	assert_eq(layers[1]["layer"], 2)
	assert_eq(layers[1]["offset"], 0)


func test_no_offset_at_all_means_216() -> void:
	var layers: Array = BattleBackground.parse_layers("battle_bg_0002_02.ssbp#battle_bg_0002_02,back/anime,0")
	assert_eq(layers[0]["offset"], 216)


func test_an_empty_column_has_no_layers() -> void:
	assert_eq(BattleBackground.parse_layers(""), [])


func test_the_database_gives_a_missions_layers() -> void:
	assert_eq(GameDatabase.get_mission_bg_layers("1110301"), "battle_bg_0005_01.ssbp#battle_bg_0005_01,back/anime,0,216", "Dalnakya Cavern")
	assert_eq(GameDatabase.get_mission_bg_layers("no such mission"), "")
