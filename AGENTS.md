# Repository Guidelines

## Project Structure & Module Organization

This repository contains the KOReader weather plugin in `weather.koplugin/`, including its icons. `config.example.lua` documents the local plugin settings; copy it to `weather.koplugin/config.lua` on the device and never commit the real configuration. `package.sh` creates a distributable archive in `dist/`. Old Nickel browser and NickelMenu prototypes are archived locally under `old/` and are not part of the active project or GitHub repository.

## Build, Test, and Development Commands

- `./package.sh` creates `dist/kobo-weather-plugin.zip` for USB or network transfer.
- `luac -p weather.koplugin/main.lua weather.koplugin/_meta.lua` checks Lua syntax without launching KOReader.
- On the Kobo Mini, verify login, all eight readings, refresh timing, and recovery after network failure or suspend/resume. Compare battery use over equal periods and record Wi-Fi state and interval.

There is no automated test suite. Do not add generated files, credentials, or caches to source archives.

## Coding Style & Naming Conventions

Use four spaces for Lua indentation. KOReader plugins use the `.koplugin` suffix and `_meta.lua` metadata. Use descriptive lower-case filenames and avoid dependencies not supported by the Kobo runtime.

## Security & Configuration

Never commit `weather.koplugin/config.lua` or real credentials. The KOReader configuration stores the meteodb password in plain text on the device; keep it local and out of archives. Do not modify the meteodb server as part of this project unless a task explicitly requests that scope.
