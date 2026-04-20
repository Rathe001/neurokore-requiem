extends Node

# Loads i18n/strings.csv at startup and registers translations with the
# TranslationServer. Loading at runtime (instead of via Godot's CSV-to-
# .translation import pipeline) keeps the workflow editor-free: edit the
# CSV, restart, see new strings.
#
# CSV format: first column is "keys", each subsequent column is a locale
# code (e.g. "en", "fr"). Embedded \n escape sequences in cells are
# converted to real newlines.

const STRINGS_CSV := "res://i18n/strings.csv"
const DEFAULT_LOCALE := "en"

func _ready() -> void:
	_load_csv()

func _load_csv() -> void:
	var file := FileAccess.open(STRINGS_CSV, FileAccess.READ)
	if file == null:
		push_warning("[LocaleState] missing %s" % STRINGS_CSV)
		return
	var headers := file.get_csv_line()
	if headers.size() < 2 or headers[0].strip_edges() != "keys":
		push_warning("[LocaleState] expected header row starting with 'keys'")
		return
	var translations: Array[Translation] = []
	for i in range(1, headers.size()):
		var t := Translation.new()
		t.locale = headers[i].strip_edges()
		translations.append(t)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2:
			continue
		var key := row[0]
		if key == "":
			continue
		for i in range(1, headers.size()):
			if i >= row.size():
				continue
			translations[i - 1].add_message(key, row[i].replace("\\n", "\n"))
	for t in translations:
		TranslationServer.add_translation(t)
	if not TranslationServer.get_loaded_locales().is_empty():
		TranslationServer.set_locale(DEFAULT_LOCALE)
