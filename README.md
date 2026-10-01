# Pipet

**Your voice, wherever you type.** A small native macOS dictation app by vietbrosinaus, built on [Codex Voice](https://github.com/anthnykr/codex-voice) by [Anthony Kroeger](https://github.com/anthnykr) (anthnykr), the GOAT.

Hold **Control-M**, speak, and release to insert a transcript at your cursor. Pipet lives in the menu bar, with a practice area, setup status, optional launch at login, and last-transcript recovery. It never automatically sends messages or submits forms.

## Download

[Install Pipet](https://vietbrosinaus.com/pipet) · [Latest release](https://github.com/vietbrosinaus/pipet/releases/latest)

## Install the shared app

Open the DMG, drag **Pipet** into **Applications**, eject the DMG, and open the installed app. See [START-HERE.txt](docs/START-HERE.txt) for the full instructions.

Pipet 0.3.1 is **Developer ID signed and Apple-notarized**, with notarization tickets attached to the app and DMG. macOS Gatekeeper accepts both. Earlier 0.2.x development previews were locally signed and required Open Anyway.

Requirements: macOS 14+, an internet connection, and your own Codex CLI sign-in. The universal app contains Apple silicon and Intel binaries; Intel has not been tested on physical hardware here. Follow [Codex CLI setup](https://developers.openai.com/codex/cli/) and run `codex login` before dictating.

Allow **Microphone** and enable the installed **Pipet** app under **Privacy & Security → Accessibility**. Click the speech-bubble menu-bar icon to open Pipet.

If you also have Codex Voice running, quit it first: both use Control-M. Pipet has its own identity and requires its own permissions.

## Build and install locally

Requires Apple Command Line Tools with Swift 6 and Python 3. Full Xcode is optional.

```bash
./scripts/build-app.sh             # current Mac architecture
./scripts/build-app.sh --universal # Apple silicon + Intel
./scripts/install-local-app.sh     # installs ~/Applications/Pipet.app
```

To update an existing local Pipet, use `./scripts/install-local-app.sh --replace`. The old app is saved under `.build/backups/`. Finish dictation first. Ad hoc signing changes the app's code identity when its executable changes; remove the old Accessibility entry and add the installed app again if the switch is on but insertion is blocked.

The included Xcode project is also maintained. `project.yml` is the XcodeGen source; its original target and source-folder names remain CodexVoice, while the built product is Pipet.

## Package for friends

```bash
./scripts/package-release.sh
```

Creates `dist/Pipet-0.3.1/` containing the universal `.app`, `.dmg`, `.zip`, setup instructions, MIT license, and SHA-256 checksums. Release files use a strict whitelist: no credentials, recordings, development caches or local logs are copied. Existing release directories are not overwritten.

For a notarized release, configure a **Developer ID Application** signing certificate and a `notarytool` Keychain profile, then run:

```bash
PIPET_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
PIPET_NOTARY_PROFILE='pipet-notary' \
./scripts/package-release.sh
```

Apple's requirements and account setup: [Developer ID](https://developer.apple.com/developer-id/). This Mac has a valid Developer ID identity and a configured `Pipet` Keychain credential profile. Use the signing identity when building future updates to preserve the permission identity; notarize each release before sharing it.

To finish notarizing an existing signed release, run `PIPET_NOTARY_PROFILE=Pipet ./scripts/notarize-release.sh /absolute/path/to/release-directory`. The script checks Apple’s acceptance, attaches tickets, verifies Gatekeeper acceptance, rebuilds the ZIP, and updates checksums.

## Verify

```bash
./scripts/check-transcription.sh
./scripts/check-transcription.sh --refresh
.build/Pipet.app/Contents/MacOS/Pipet --diagnostics
.build/Pipet.app/Contents/MacOS/Pipet --check-transcription .build/transcription-check.wav
```

The transcription check sends a generated test sentence through the same Swift service as the app; it does not use your microphone. The app diagnostic verifies its bundled icon and logo.

UI previews cover setup and ready states, light and dark modes, Settings, and a small resizable window. Live microphone and insertion require macOS permissions granted to the Pipet app.

## Privacy and limitations

Audio goes to the Codex transcription backend after you release the shortcut. Temporary WAV recordings are deleted after each attempt. Your latest transcript remains in memory until you quit. Clipboard contents are restored after paste unless you copy something else in the meantime. If you switch apps during transcription, use **Copy Last Transcript** instead of inserting into the new app.

Authentication is read from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`, using each person's own account. Expired authentication is refreshed with a bounded Codex CLI handshake. CLI discovery supports `CODEX_CLI_PATH`, PATH, `~/.local/bin`, Homebrew locations, and the original Codex desktop app resource path.

This remains an experimental, undocumented transcription endpoint. It works in current testing but could change or stop being available. Most editable fields accept Accessibility insertion or a normal paste; secure fields or apps that block both may require manual entry.

## Brand

Warm coral speech-bubble mascot, cream tile, rounded native type, inspired by the friendly identity of Plan2Go and PopPopAI. Logo: [assets/PipetLogo.png](assets/PipetLogo.png). App icon: [assets/Pipet.icns](assets/Pipet.icns). Built-in image generation prompts are saved in [docs/logo-prompts.txt](docs/logo-prompts.txt). UI design decisions are documented in [docs/design.md](docs/design.md), using UI/UX Pro Max and the applicable typography and hierarchy guidance from Taste.

## License

MIT. The original project's license is preserved in [LICENSE](LICENSE) and bundled with the application and release.

## A big thank you

Pipet builds on [Codex Voice](https://github.com/anthnykr/codex-voice), created by [Anthony Kroeger](https://github.com/anthnykr). Anthony is the GOAT behind the original project and a former colleague at Lyra. The original MIT license and upstream Git history are preserved.

The download landing page lives at [vietbrosinaus.com/pipet](https://vietbrosinaus.com/pipet); its source is in [vietbrosinaus/landing-page](https://github.com/vietbrosinaus/landing-page/tree/main/src/app/pipet).
