extends "res://tests/test_case.gd"

## EventText: how a raw dialogue line splits into a speaker and pages of tokens.


func test_the_name_tag_and_its_br_become_the_speaker() -> void:
	var line: EventText = EventText.parse("<name=100000><br>Is that...<wait=20>a crystal!?<wait=90>")
	assert_eq(line.speaker_id, 100000)
	assert_eq(line.speaker_kind, "name")
	assert_eq(line.pages, [[{"text": "Is that..."}, {"wait": 20}, {"text": "a crystal!?"}, {"wait": 90}]])


func test_br_inside_the_text_is_a_newline_and_speed_is_a_token() -> void:
	var line: EventText = EventText.parse("<name=100008><br><speed=8>Please...<wait=90><br>You must...help me...<wait=150>")
	assert_eq(line.pages[0], [{"speed": 8}, {"text": "Please..."}, {"wait": 90}, {"text": "\nYou must...help me..."}, {"wait": 150}])
	assert_eq(EventText.page_text(line.pages[0]), "Please...\nYou must...help me...")


func test_page_and_keywait_end_a_page() -> void:
	var line: EventText = EventText.parse("<name=100000><br>Was that... a dream?<wait=50><page>But...<br>when did I fall asleep?<wait=50><page>")
	assert_eq(line.pages.size(), 2)
	assert_eq(EventText.page_text(line.pages[1]), "But...\nwhen did I fall asleep?")
	assert_eq(EventText.parse("stop<keywait>").pages, [[{"text": "stop"}]])


func test_an_npc_speaker_after_a_leading_br() -> void:
	var line: EventText = EventText.parse("<invalid_touchwait><br><name_npc=100000800><br>You shall die by my hand!<wait=70>")
	assert_eq(line.speaker_id, 100000800)
	assert_eq(line.speaker_kind, "name_npc")
	assert_true(line.auto_close)
	assert_eq(EventText.page_text(line.pages[0]), "You shall die by my hand!")


func test_the_full_width_comma_reads_as_a_comma() -> void:
	var line: EventText = EventText.parse("<name=100000><br>As a knight of Grandshelt，<br>I'll do my duty!")
	assert_eq(EventText.page_text(line.pages[0]), "As a knight of Grandshelt, \nI'll do my duty!")


func test_a_line_without_a_speaker() -> void:
	var line: EventText = EventText.parse("*knock* *knock* <page>")
	assert_eq(line.speaker_id, -1)
	assert_eq(line.pages, [[{"text": "*knock* *knock* "}]])
