# Vivobook S14 Copilot+

Omarchy shell plugin for the **ASUS Vivobook S14 Copilot+** (S5406SA,
Intel Core Ultra 7 258V, Arc 130V/140V, 2880×1800@120 panel).

Plugin id: `vivobook.s14-copilot`

![Customize extras overlay](images/preview.png)

It does not edit `/usr/share/omarchy`. It watches power-profiles-daemon and
the AC adapter, then applies Vivobook S14 Copilot+ extras on top of the
stock Omarchy power profiles.

![Power menu with Vivobook S14 Copilot+ profiles](images/power-menu.png)

## Install

From git:

```sh
omarchy plugin add https://github.com/paulogeyer/omarchy-vivobook-s14-copilot.git --enable
```

From a local checkout:

```sh
omarchy plugin add "$HOME/Projects/omarchy-vivobook-s14-copilot" --enable --yes
```

The shell loads the copy under `~/.config/omarchy/plugins/vivobook.s14-copilot`
(a git clone). A symlink there will not load.

The stock power menu still sets the PPD profile. This service applies the
matching extras whenever that profile or the power source changes. Charge
hold needs root once: Omarchy's polkit dialog asks on first apply (or tap
**Enable charge limit** in Customize extras). After that it is passwordless
and restored at boot. The profile CLI in `bin/omarchy-vivobook-profile` is
shipped with the plugin and calls `bin/apply` for the performance /
balanced / battery bundles.

Open **Customize extras** from the power menu (or run
`omarchy-shell vivobook.s14-copilot open '{}'`). That panel edits
per-profile refresh rate, animations, charge limit, keyboard backlight, and
thermal policy. Choices are saved to
`~/.config/omarchy/vivobook-s14-copilot.json`.

To have the bar buttons call the tuner directly, clone the stock widget and
point `setProfile()` at `bin/apply`:

```sh
omarchy plugin clone omarchy.power
```

```qml
actionProc.command = [
  Quickshell.env("HOME") + "/.config/omarchy/plugins/vivobook.s14-copilot/bin/apply",
  "--remember", "--source", source, String(profile)
]
```

## What each profile does

| Bar button | PPD | Panel | Animations | Charge | Keyboard | ASUS thermal |
|---|---|---|---|---|---|---|
| Performance | performance | 120 Hz | on | 100% | restored | overboost (1) |
| Balanced | balanced | 120 Hz | on | 80% | restored | default (0) |
| Power-saver | power-saver | 60 Hz | off | 80% | off | silent (2) |

Unplugging forces **power-saver**. Plug back in and Omarchy restores the last
AC profile; this plugin reapplies matching extras. Set
`OMARCHY_VIVOBOOK_AUTO_BATTERY=0` to leave the last battery PPD alone.

Chromium VAAPI flags are turned on if they are missing (Arc decode). Bluetooth
is not touched.

## Extra knobs this machine actually has

- Session: Hyprland `hl.monitor` / `animations` via `hyprctl eval` (Lua parser).
- Keyboard backlight via `brightnessctl` on `asus::kbd_backlight`.
- Charge hold at `BAT0/charge_control_end_threshold`. First use installs a
  root helper via polkit (passwordless for `%wheel` afterward) and a boot
  restore unit. The pack does not drain down to 80%; the limit only stops
  further charging.
- Best-effort `asus-nb-wmi` `throttle_thermal_policy` if sysfs is writable.
- power-profiles-daemon already drives Intel P-state EPP and ACPI platform
  profile. TLP is not used (it conflicts with PPD).

Wi-Fi power save and PCI runtime PM need root and are skipped rather than
prompting on every unplug.

## Files

- `bin/apply` — tuner used by the service and by a cloned power menu
- `bin/set-charge-limit` — root helper copied to `/usr/local/lib` by `apply setup`
- `bin/omarchy-vivobook-profile` — CLI for profiles, VAAPI, and cleanup
- `bin/config` — merge defaults with the user JSON
- `system/vivobook-s14-copilot-charge.service` — restore the last limit at boot
- `Service.qml` — watches UPower + PPD, and hosts the customize overlay
- `images/` — customize overlay and power menu screenshots

```bash
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/apply status
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/apply balanced
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/apply setup
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/omarchy-vivobook-profile status
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/omarchy-vivobook-profile battery
```

## Remove

```sh
~/.config/omarchy/plugins/vivobook.s14-copilot/bin/apply teardown
omarchy plugin remove vivobook.s14-copilot
```

## License

MIT. See [LICENSE](LICENSE).
