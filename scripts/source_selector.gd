extends RefCounted

# Runtime window IDs are intentionally excluded from persistent selectors.
static func selector_for(row: Dictionary) -> Dictionary:
	return {"bundle_id": row.get("bundle_id", ""), "title": row.get("title", "")}

# Return an ID only when both persistent fields identify exactly one window.
static func resolve(selector: Dictionary, rows: Array) -> Dictionary:
	var bundle: String = selector.get("bundle_id", "") if selector.get("bundle_id") is String else ""
	var title: String = selector.get("title", "") if selector.get("title") is String else ""
	if bundle.is_empty() or title.is_empty():
		return {"state": "invalid"}
	var matches: Array = []
	for row in rows:
		if row is Dictionary and row.get("bundle_id") == bundle and row.get("title") == title and row.get("id") is int:
			matches.append(row.id)
	if matches.size() == 1:
		return {"state": "resolved", "id": matches[0]}
	return {"state": "missing" if matches.is_empty() else "ambiguous"}
