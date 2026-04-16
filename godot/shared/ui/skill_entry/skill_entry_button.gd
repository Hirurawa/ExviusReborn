extends PanelContainer

var icon_rect: TextureRect
var trait_lbl: Label
var name_lbl: Label
var desc_lbl: Label
var mp_lbl: Label
var lvl_hbox: HBoxContainer
var lvl_lbl: Label
var lvl_orb: TextureRect
var button: Button

signal pressed

func _ready() -> void:
    icon_rect = $Margin/HBox/IconWrapper/IconRect
    trait_lbl = $Margin/HBox/VBox/TopHBox/TraitLabel
    name_lbl = $Margin/HBox/VBox/TopHBox/NameLabel
    desc_lbl = $Margin/HBox/VBox/DescLabel
    mp_lbl = $Margin/HBox/IconWrapper/MPLabel
    lvl_hbox = $Margin/LevelHBox
    lvl_lbl = $Margin/LevelHBox/LevelLabel
    lvl_orb = $Margin/LevelHBox/LevelOrb
    button = $Button

    button.pressed.connect(func(): pressed.emit())

func setup_from_skill_data(skill_data: Dictionary, source: String = "Trait", is_button: bool = false, skill_level: int = -1) -> void:
    if not is_inside_tree():
        await ready

    var icon_path = "res://assets/abilities/" + skill_data.get("icon", "ability_1.png")
    var tex = load(icon_path)
    if tex:
        icon_rect.texture = tex
    else:
        var color_rect = ColorRect.new()
        color_rect.custom_minimum_size = Vector2(48, 48)
        color_rect.color = Color(0.3, 0.3, 0.3)
        icon_rect.add_child(color_rect)

    var orb_path = "res://assets/ui/orb_level.png"
    var orb_tex = load(orb_path)
    if orb_tex:
        lvl_orb.texture = orb_tex
        lvl_orb.show()
    else:
        lvl_orb.hide()

    trait_lbl.text = source
    if source == "":
        trait_lbl.hide()
    else:
        trait_lbl.show()

    name_lbl.text = skill_data.get("name", "Unknown Skill")

    var cost = skill_data.get("cost", {})
    if cost.has("MP") and cost["MP"] > 0:
        mp_lbl.text = "MP " + str(int(cost["MP"]))
        mp_lbl.show()
    else:
        mp_lbl.hide()

    var effects = skill_data.get("effects", [])
    if typeof(effects) == TYPE_ARRAY and effects.size() > 0:
        var first_eff = effects[0]
        if typeof(first_eff) == TYPE_ARRAY and first_eff.size() > 0:
            desc_lbl.text = str(first_eff[0])
        elif typeof(first_eff) == TYPE_STRING:
            desc_lbl.text = str(first_eff)
        else:
            desc_lbl.text = "No description."
    else:
        desc_lbl.text = "No description."

    if skill_level > 0:
        lvl_lbl.text = "Lvl " + str(skill_level)
        lvl_hbox.show()
    else:
        lvl_hbox.hide()

    if is_button:
        button.show()
        button.mouse_filter = Control.MOUSE_FILTER_STOP
    else:
        button.hide()
        button.mouse_filter = Control.MOUSE_FILTER_IGNORE
