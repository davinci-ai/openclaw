# Custom Modifications to OpenClaw

This document tracks all custom modifications made to this fork.
Update this file whenever you make custom changes.

## Modified Files

### Plugin System Enhancements

- `src/auto-reply/reply/get-reply.ts` - Added `message_sending` and `before_media_understanding` plugin hooks
- `src/infra/outbound/deliver.ts` - Wired message_sending hook for outbound messages
- `src/plugins/hooks.ts` - Added new hook definitions
- `src/plugins/types.ts` - Extended plugin type definitions

### Model Support

- `src/agents/pi-embedded-runner/extra-params.ts` - Added Kimi K2.5 thinking mode support via extraParams
- `src/agents/pi-embedded-runner/model.ts` - Added apiId mapping for model variants
- `src/config/types.models.ts` - Extended model configuration types
- `src/config/zod-schema.core.ts` - Updated schema for model variants

### Build Configuration

- `package.json` - Include control UI in default build step

## Added Files/Directories

### Fork Sync Infrastructure

- `scripts/setup-fork.sh` - Initial fork setup script
- `scripts/sync-upstream.sh` - Daily upstream sync script (includes post-sync rebuild + gateway restart)
- `scripts/resolve-conflicts.sh` - Interactive conflict resolution
- `scripts/health-check.sh` - Fork health verification
- `scripts/emergency-rollback.sh` - Disaster recovery script
- `.github/workflows/daily-sync.yml` - Automated daily sync workflow
- `FORK_SYNC.md` - Fork sync documentation
- `.sync-protected` - Protected files list

### Custom Scripts (Termux)

- `scripts/termux-auth-widget.sh` - Termux authentication widget
- `scripts/termux-quick-auth.sh` - Quick authentication helper
- `scripts/termux-sync-widget.sh` - Termux sync widget

## Removed/Disabled Features

- None

## Configuration Changes

- Added support for `thinking` parameter in model extraParams (Kimi K2.5)
- Added `apiId` field for model variant mapping

## Last Upstream Sync

- Date: 2026-02-05
- Upstream Commit: 8b8451231 (v2026.2.4)
- Conflicts Resolved:
  - `package.json` - Merged upstream's tsdown build with custom ui:build step
