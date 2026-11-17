import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func hasChinese(_ value: String) -> Bool { value.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let profiles = try JSONSerialization.jsonObject(with: Data(contentsOf:root.appendingPathComponent("Resources/profiles.json"))) as! [[String:Any]]
var copy = Set<String>()
for profile in profiles {
    for field in ["name", "subtitle", "detail"] { copy.insert(profile[field] as! String) }
}
// Check static app copy as well as the catalog, so a newly added label cannot silently fall back to Chinese.
let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
for file in ["Views.swift", "main.swift", "AppModel.swift"] {
    let source = try String(contentsOf:root.appendingPathComponent("Sources/" + file),encoding:.utf8)
    for match in literal.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
        let value = String(source[Range(match.range, in:source)!])
        guard let decoded = try? JSONDecoder().decode(String.self,from:Data(value.utf8)), hasChinese(decoded) else {continue}
        copy.insert(decoded)
    }
}
for source in copy {
    check(AppLanguage.chinese.text(source) == source, "Chinese copy changed: \(source)")
    let english = AppLanguage.english.text(source)
    check(!english.isEmpty && !hasChinese(english), "Missing English translation: \(source) -> \(english), chinese=\(hasChinese(english))")
}
check(AppLanguage.english.text("Caps Lock") == "Caps Lock", "Key names must remain intact")
check(String(format:AppLanguage.english.text("设备缓冲 %.1f ms · %.0f kHz"),1.5,44.1) == "Device buffer 1.5 ms · 44 kHz", "Device format is broken")
let suite = "KeyTone.LocalizationTests." + UUID().uuidString
let defaults = UserDefaults(suiteName:suite)!
defer { defaults.removePersistentDomain(forName:suite) }
check(AppLanguage.saved(in:defaults) == .chinese, "Existing installations should remain Chinese")
defaults.set("unsupported", forKey:"language")
check(AppLanguage.saved(in:defaults) == .chinese, "Unknown language should fall back safely")
defaults.set("eg-oreo",forKey:"profileID")
defaults.set(true,forKey:"enabled")
for language in [AppLanguage.english, .chinese, .english] {
    language.save(in:defaults)
    check(AppLanguage.saved(in:UserDefaults(suiteName:suite)!) == language, "Language preference was not persisted")
    check(defaults.string(forKey:"profileID") == "eg-oreo" && defaults.bool(forKey:"enabled"), "Language changed unrelated preferences")
}
print("Localization PASS: \(copy.count) Chinese strings, 10 sound profiles, formatting and saved preferences")
