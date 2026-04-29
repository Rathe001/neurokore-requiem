extends Node

# Registers translation resources with the TranslationServer at startup.
#
# Source of truth is i18n/strings.csv — Godot's csv_translation importer
# converts it to per-locale .translation files (compressed). We load those
# imported resources here because:
#   - they're always packed into exported builds (the source CSV is not)
#   - the editor re-imports on save, so editing the CSV still hot-reloads
#
# To add a locale: add a column to strings.csv. Godot will produce a new
# strings.<code>.translation file; add the path to TRANSLATION_FILES.

const DEFAULT_LOCALE := "en"
const TRANSLATION_FILES := [
	"res://i18n/strings.en.translation",
]

func _ready() -> void:
	for path in TRANSLATION_FILES:
		var t := load(path) as Translation
		if t == null:
			push_warning("[LocaleState] failed to load %s" % path)
			continue
		TranslationServer.add_translation(t)
	if not TranslationServer.get_loaded_locales().is_empty():
		TranslationServer.set_locale(DEFAULT_LOCALE)
