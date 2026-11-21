extends SceneTree
const Selector = preload("res://scripts/source_selector.gd")

func _initialize() -> void:
	var rows := [
		{"id": 1, "bundle_id": "example.app", "title": "One"},
		{"id": 2, "bundle_id": "example.app", "title": "Two"},
	]
	var selector: Dictionary = Selector.selector_for(rows[0])
	assert(not selector.has("id"))
	assert(Selector.resolve(selector, rows) == {"state": "resolved", "id": 1})
	assert(Selector.resolve(selector, [rows[1]]).state == "missing")
	assert(Selector.resolve(selector, [rows[0], rows[0]]).state == "ambiguous")
	assert(Selector.resolve({"bundle_id": 2, "title": "One"}, rows).state == "invalid")
	print("Source selector checks: PASS")
	quit()
