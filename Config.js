function defaults() {
  return {
    autoBattery: true,
    vaapi: true,
    profiles: {
      performance: { refresh: "120", animations: "on", charge: "100", keyboard: "restore", thermal: "1" },
      balanced: { refresh: "120", animations: "on", charge: "80", keyboard: "restore", thermal: "0" },
      "power-saver": { refresh: "60", animations: "off", charge: "80", keyboard: "off", thermal: "2" }
    }
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function merge(base, overlay) {
  var out = clone(base)
  if (!overlay || typeof overlay !== "object") return out
  var keys = Object.keys(overlay)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var value = overlay[key]
    if (value && typeof value === "object" && !Array.isArray(value)
        && out[key] && typeof out[key] === "object" && !Array.isArray(out[key])) {
      out[key] = merge(out[key], value)
    } else {
      out[key] = value
    }
  }
  return out
}

function parse(raw) {
  var overlay = {}
  try {
    overlay = JSON.parse(String(raw || "{}"))
  } catch (e) {
    overlay = {}
  }
  var cfg = merge(defaults(), overlay)
  cfg.autoBattery = cfg.autoBattery === true
  cfg.vaapi = cfg.vaapi === true
  var names = ["performance", "balanced", "power-saver"]
  var keys = ["refresh", "animations", "charge", "keyboard", "thermal"]
  var base = defaults().profiles
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    var src = base[name]
    var got = cfg.profiles && cfg.profiles[name] && typeof cfg.profiles[name] === "object"
      ? cfg.profiles[name] : {}
    var next = {}
    for (var k = 0; k < keys.length; k++) {
      var key = keys[k]
      next[key] = got[key] !== undefined && got[key] !== null ? String(got[key]) : String(src[key])
    }
    cfg.profiles[name] = next
  }
  return cfg
}

function stringify(cfg) {
  return JSON.stringify(cfg, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaults: defaults,
    clone: clone,
    merge: merge,
    parse: parse,
    stringify: stringify
  }
}
