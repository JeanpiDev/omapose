import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// Plugin string catalog. Same t()/tn() API as Commons.Translations, plus a
// language override: "auto" follows Omarchy's language, "en"/"es" force one.
// English is always the fallback layer.
QtObject {
  id: root

  property var directory: ""
  property string override: "auto"

  readonly property string language: Model.languageFor(override, Commons.I18n.language)
  readonly property string directoryPath: String(directory).replace(/^file:\/\//, "").replace(/\/+$/, "")

  property FileView englishFile: FileView {
    path: root.directoryPath !== "" ? root.directoryPath + "/en.json" : ""
    blockLoading: true
    printErrors: false
  }

  property FileView spanishFile: FileView {
    path: root.directoryPath !== "" ? root.directoryPath + "/es.json" : ""
    blockLoading: true
    printErrors: false
  }

  readonly property var english: parse(englishFile.text())
  readonly property var spanish: parse(spanishFile.text())
  readonly property var current: language === "es" ? spanish : english

  function parse(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function lookup(key, count) {
    var layers = [root.current, root.english]
    for (var i = 0; i < layers.length; i++) {
      var value = Model.pluralPick(layers[i][key], count)
      if (value) return value
    }
    return ""
  }

  function t(key, fallback) {
    var value = lookup(key, -1)
    return value ? value : (fallback !== undefined ? fallback : key)
  }

  function tn(key, count, fallback) {
    var value = lookup(key, count)
    return value ? value : (fallback !== undefined ? fallback : key)
  }
}
