# Cheatble

[English](README.md) · [한국어](README.ko.md)

**Version 1.0.1** — A free, local macOS shortcut reference that stays beside your work. Follow the active app, browse macOS shortcuts, or pin a saved app's list. No server, account, subscription, or external package dependencies.

Requires **macOS 13 or later**. The current app interface and bundled shortcut descriptions are in Korean.

## Install

1. [Build from source](#build-from-source), or use a build made for your Mac's CPU.
2. Move `dist/Cheatble.app` to `/Applications` and launch it.
3. Use the **⌘ menu bar icon** to show or hide the sheet, open settings, or quit. Drag Cheatble from Applications to the Dock to pin it; clicking its Dock icon shows the sheet.
4. To read other apps' menus, enable Cheatble in **System Settings → Privacy & Security → Accessibility**. The **권한 설정** button opens this pane.

Bundled shortcuts, saved lists, and global hotkeys work without Accessibility permission. Permission is needed to read other apps' menus and follow the active window's display. Changes are checked automatically.

Local builds use a certificate created on the build Mac; they are not notarized public distribution builds. Reuse the same signing identity when updating an installed copy.

## Use the sheet

### Switch lists

| Top bar selector | Behavior |
| --- | --- |
| Active app icon | Follows the active app and updates its shortcut list. |
| Apple icon | Shows macOS shortcuts. |
| Saved app icon and dropdown | Opens a searchable app icon grid. Keeps the chosen list visible as you switch apps. |

When macOS or a saved app is selected, switching apps updates only the active app icon; the list, search, and filters stay in place. The dropdown omits the active app because it already has its own selector.

In the dropdown, type an app name to search, use **arrow keys** to move, **Return** to select, or **Escape** to close. Pressing its hotkey again also closes it. Apps whose menus have been read are saved automatically and remain available after they quit.

### Default hotkeys

| Action | Shortcut |
| --- | --- |
| Show or hide Cheatble | `Control + Option + Command + Return` |
| Follow the active app | `Control + Option + Command + J` |
| Show macOS shortcuts | `Control + Option + Command + K` |
| Open or close the saved app picker | `Control + Option + Command + ;` |

Use your left hand for the modifiers and your right hand for the final key. Each shortcut can be changed or disabled in settings. Cheatble checks known shortcut lists and system registration conflicts; it cannot detect every app's internal shortcuts.

If a newly loaded pack conflicts with a configured hotkey, that hotkey is temporarily unregistered and settings show the conflict. Removing the conflicting pack restores the hotkey without changing your saved key combination.

### Move, resize, and adjust opacity

- Drag the **CHEATBLE header** to move the sheet. Its position is saved.
- Drag the **bottom-left corner handle** to resize both dimensions, the left edge to change width, or the bottom edge to change height. Settings also provide size sliders.
- Minimum width is **240 pt**. Lists switch to **two columns at 596 pt** and **three columns at 888 pt**.
- The bottom opacity slider adjusts the whole sheet, including text and icons, from **20% to 100%**.
- Choose **자동 오른쪽 배치로 되돌리기** in settings to restore automatic placement on the right side of the active window's display.

### Search and personalize

- Search action names, keys, descriptions, aliases, and menu paths. Modifier filters (`⌘`, `⌥`, `⌃`, `⇧`) require all selected modifiers. The star shows favorites; the checkmark includes learned shortcuts, which are otherwise hidden.
- Click a category header to collapse or expand it. Click a shortcut row to reveal its description, **favorite**, **learned**, and **pencil/edit** controls.
- Use **설정 → 앱별 단축키 설정** to add, edit, or remove custom entries. Removing an override restores the original menu or bundled value. Editing a reference does not change the shortcut in the target app.
- Settings can import/export custom entries, saved menus, favorites, learned marks, and collapsed groups as JSON. Import merges data; imported custom entries replace matching custom entries. Shortcut packs are stored separately.
- **메뉴 더 읽기** switches to the target app and briefly opens its menus to discover lazily created items. Normal refresh does not open menus or execute commands.

Key symbols: `⌘` Command · `⌥` Option · `⌃` Control · `⇧` Shift · `⇥` Tab · `↩` Return · `⌫` Delete. Press keys within one combination together. For `Control+B → C`, release the first combination before pressing the next key. Enter arrow keys as `Left`, `Right`, `Up`, or `Down`, and the plus key as `Plus`.

## Included shortcuts

Version 1.0 includes **364 shortcuts**, available offline:

| List | Count | List ID |
| --- | ---: | --- |
| macOS | 68 | `macOS` |
| Finder | 44 | `com.apple.finder` |
| Safari | 31 | `com.apple.Safari` |
| Terminal | 16 | `com.apple.Terminal` |
| Google Search in Safari | 11 | `web.google.search` |
| tmux | 36 | `org.tmux.tmux` |
| cmux | 42 | `com.cmuxterm.app` |
| Microsoft Excel | 40 | `com.microsoft.Excel` |
| Microsoft Word | 36 | `com.microsoft.Word` |
| Microsoft PowerPoint | 40 | `com.microsoft.Powerpoint` |

Google Search and tmux are manually selected reference lists; Cheatble does not detect websites or programs inside a terminal. tmux uses its default `Control+B` prefix. App settings, OS versions, and keyboard layouts can affect the actual shortcuts. See [sources and pack details](docs/app-packs.md).

## Add shortcuts for another app

### Ask a coding agent to create a pack

1. Activate the target app and select Cheatble's active app icon.
2. If the list is empty, click **추가 요청 복사**. This copies the app name, bundle ID, version, and installation instructions.
3. Paste it into a coding agent with local file and command access. Nothing is sent automatically; Cheatble itself needs no service account or API key.
4. Ask the agent to verify shortcuts against official macOS documentation or the actual app menus, create a JSON pack, and install it using the CLI below.
5. Select the new list in the saved app dropdown. Cheatble checks for pack changes every two seconds; no restart is required.

For an app that already has entries, or a website/tool reference, replace the placeholders in this request:

```text
Add shortcuts for <app or tool name> to Cheatble.
Target version: <version>; macOS app bundle ID or list ID: <ID>.
Verify shortcuts using official macOS documentation or the app's actual menus.
Do not invent unverified shortcuts. Use Korean action names and categories.
Include official sourceURL references and any conditions in detail.
Read the JSON schema with:
/Applications/Cheatble.app/Contents/MacOS/Cheatble --pack-example
Keep action IDs stable and retain all needed entries when updating an existing pack.
Install the completed JSON with --install-pack <absolute JSON path>.
Do not modify library.json or overwrite my custom entries.
Report the installed file, shortcut count, and verification sources.
```

### Add manually or import a pack

For a few shortcuts, use **설정 → 앱별 단축키 설정 → 단축키 추가…**. For a full list, choose **추가 목록 가져오기** in settings or run:

```sh
# Print a template; replace its example values with verified shortcuts.
/Applications/Cheatble.app/Contents/MacOS/Cheatble --pack-example

# Validate and install the completed pack.
/Applications/Cheatble.app/Contents/MacOS/Cheatble --install-pack "/absolute/path/app-shortcuts.json"
```

A pack has `schemaVersion: 1`, `bundleIdentifier`, `appName`, and a `shortcuts` array. Each item requires `id`, `title`, `category`, and `keys`; optional fields are `detail`, `aliases`, and `sourceURL`. See the [complete JSON example](docs/app-packs.md#팩-형식과-설치) or [bundled packs](Sources/CheatbleCore/Resources/Packs).

Packs are installed at `~/Library/Application Support/Cheatble/Packs/<bundleIdentifier>.json`. Invalid files do not replace existing packs. An installed pack replaces the entire bundled pack for the same ID, so include all entries you want to retain. Custom entries remain higher priority. Keep action IDs stable to preserve favorites, learned marks, and overrides. Pack files are separate from library export JSON.

## Build from source

Install Xcode Command Line Tools and Swift 6 or later. Full Xcode and a paid Apple developer account are not required.

```sh
python3 scripts/setup-signing.py   # One-time local signing identity setup
bash scripts/test.sh
bash scripts/build-app.sh
bash scripts/smoke-test.sh        # Requires a logged-in macOS GUI session
```

Outputs are `dist/Cheatble.app` and `dist/Cheatble.zip`, built for the Mac's architecture. Packaging and validation finish in a staging directory before replacing existing outputs; replacement errors restore the previous outputs. Set `CHEATBLE_CACHE_DIR` to use another build cache directory.

The signing key stays in the login Keychain. Allow `codesign` to use it when macOS asks. Public signing configuration is outside the repository at `~/Library/Application Support/Cheatble/Signing`. Reuse this identity for updates to preserve Accessibility authorization. Temporary ad-hoc builds use `CHEATBLE_ADHOC_SIGNING=1 bash scripts/build-app.sh`; installing one over a certificate-signed copy changes its identity.

`python3 scripts/verify-signing.py` checks update identity, rejects a different signer with the same app ID, and detects altered resources. It signs a temporary test copy and may trigger a Keychain confirmation. Smoke tests use a separate app ID, temporary data, and test hotkeys. See [manual validation](docs/manual-validation.md) for multi-display, Spaces, and app-specific checks.

## Data and troubleshooting

| Data | Location |
| --- | --- |
| Custom entries, saved menus, favorites, learned marks | `~/Library/Application Support/Cheatble/library.json` |
| Installed packs | `~/Library/Application Support/Cheatble/Packs/` |
| Copied pack requests | `~/Library/Application Support/Cheatble/Requests/` |
| Window and hotkey settings | UserDefaults domain `app.cheatble.desktop` |

- **Permission appears missing:** check that the enabled Accessibility entry points to `/Applications/Cheatble.app`. From the source directory, run `python3 scripts/permission-status.py` to check the GUI app via LaunchServices. Direct terminal execution can report the terminal's permission context instead.
- **An app has few or no menu shortcuts:** activate it and refresh, try **메뉴 더 읽기**, or install a pack. Some apps do not expose every shortcut through Accessibility.
- **A custom value hides a pack update:** custom entries take priority. Remove that override in app shortcut settings to see the pack or menu value.
- **A library cannot be read:** the original is preserved and writes stop. Recovery in settings backs up the file before starting a new library.

Cheatble runs locally. It does not record keystrokes, collect browser history, send usage data, or execute displayed shortcuts. Menu reading uses only the Accessibility access you explicitly grant.
