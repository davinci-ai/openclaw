import type { MsgContext } from "../templating.js";
import type { GetReplyOptions, ReplyPayload } from "../types.js";
import {
  resolveAgentDir,
  resolveAgentWorkspaceDir,
  resolveSessionAgentId,
} from "../../agents/agent-scope.js";
import { resolveModelRefFromString } from "../../agents/model-selection.js";
import { resolveAgentTimeoutMs } from "../../agents/timeout.js";
import { DEFAULT_AGENT_WORKSPACE_DIR, ensureAgentWorkspace } from "../../agents/workspace.js";
import { type OpenClawConfig, loadConfig } from "../../config/config.js";
import { applyLinkUnderstanding } from "../../link-understanding/apply.js";
import { applyMediaUnderstanding } from "../../media-understanding/apply.js";
import { extractMediaUserText } from "../../media-understanding/format.js";
import { getGlobalHookRunner } from "../../plugins/hook-runner-global.js";
import { defaultRuntime } from "../../runtime.js";
import { resolveCommandAuthorization } from "../command-auth.js";
import { SILENT_REPLY_TOKEN } from "../tokens.js";
import { resolveDefaultModel } from "./directive-handling.js";
import { resolveReplyDirectives } from "./get-reply-directives.js";
import { handleInlineActions } from "./get-reply-inline-actions.js";
import { runPreparedReply } from "./get-reply-run.js";
import { finalizeInboundContext } from "./inbound-context.js";
import { applyResetModelOverride } from "./session-reset-model.js";
import { initSessionState } from "./session.js";
import { stageSandboxMedia } from "./stage-sandbox-media.js";
import { createTypingController } from "./typing.js";

export async function getReplyFromConfig(
  ctx: MsgContext,
  opts?: GetReplyOptions,
  configOverride?: OpenClawConfig,
): Promise<ReplyPayload | ReplyPayload[] | undefined> {
  const isFastTestEnv = process.env.OPENCLAW_TEST_FAST === "1";
  const cfg = configOverride ?? loadConfig();
  const targetSessionKey =
    ctx.CommandSource === "native" ? ctx.CommandTargetSessionKey?.trim() : undefined;
  const agentSessionKey = targetSessionKey || ctx.SessionKey;
  const agentId = resolveSessionAgentId({
    sessionKey: agentSessionKey,
    config: cfg,
  });
  const agentCfg = cfg.agents?.defaults;
  const sessionCfg = cfg.session;
  const { defaultProvider, defaultModel, aliasIndex } = resolveDefaultModel({
    cfg,
    agentId,
  });
  let provider = defaultProvider;
  let model = defaultModel;
  if (opts?.isHeartbeat) {
    const heartbeatRaw = agentCfg?.heartbeat?.model?.trim() ?? "";
    const heartbeatRef = heartbeatRaw
      ? resolveModelRefFromString({
          raw: heartbeatRaw,
          defaultProvider,
          aliasIndex,
        })
      : null;
    if (heartbeatRef) {
      provider = heartbeatRef.ref.provider;
      model = heartbeatRef.ref.model;
    }
  }

  const workspaceDirRaw = resolveAgentWorkspaceDir(cfg, agentId) ?? DEFAULT_AGENT_WORKSPACE_DIR;
  const workspace = await ensureAgentWorkspace({
    dir: workspaceDirRaw,
    ensureBootstrapFiles: !agentCfg?.skipBootstrap && !isFastTestEnv,
  });
  const workspaceDir = workspace.dir;
  const agentDir = resolveAgentDir(cfg, agentId);
  const timeoutMs = resolveAgentTimeoutMs({ cfg });
  const configuredTypingSeconds =
    agentCfg?.typingIntervalSeconds ?? sessionCfg?.typingIntervalSeconds;
  const typingIntervalSeconds =
    typeof configuredTypingSeconds === "number" ? configuredTypingSeconds : 6;
  const typing = createTypingController({
    onReplyStart: opts?.onReplyStart,
    typingIntervalSeconds,
    silentToken: SILENT_REPLY_TOKEN,
    log: defaultRuntime.log,
  });
  opts?.onTypingController?.(typing);

  const finalized = finalizeInboundContext(ctx);

  if (!isFastTestEnv) {
    // Plugin hook: let plugins provide a transcript before built-in media processing.
    let skipBuiltinAudio = false;
    let clearedAudioMetadata = false;
    const hookRunner = getGlobalHookRunner();
    if (hookRunner?.hasHooks("before_media_understanding")) {
      const mediaTypes = finalized.MediaTypes ?? (finalized.MediaType ? [finalized.MediaType] : []);
      const mediaPaths = finalized.MediaUrls ?? (finalized.MediaUrl ? [finalized.MediaUrl] : []);
      const hookResult = await hookRunner.runBeforeMediaUnderstanding(
        {
          mediaTypes,
          mediaPaths,
          body: finalized.Body,
          metadata: {
            channel: finalized.OriginatingChannel ?? finalized.Surface,
            accountId: finalized.AccountId,
          },
        },
        {
          channelId: (finalized.OriginatingChannel ?? finalized.Surface ?? "").toLowerCase(),
          accountId: finalized.AccountId,
        },
      );
      if (hookResult?.transcript) {
        finalized.Transcript = hookResult.transcript;
        const userText = extractMediaUserText(finalized.CommandBody);
        finalized.CommandBody = userText ?? hookResult.transcript;
        finalized.RawBody = userText ?? hookResult.transcript;
        // Replace <media:audio> placeholder in body fields so agent sees transcript text
        const audioPlaceholder = /<media:audio>/gi;
        if (finalized.Body) {
          finalized.Body = finalized.Body.replace(audioPlaceholder, hookResult.transcript);
        }
        if (finalized.BodyForAgent) {
          finalized.BodyForAgent = finalized.BodyForAgent.replace(
            audioPlaceholder,
            hookResult.transcript,
          );
        }
        if (finalized.BodyForCommands) {
          finalized.BodyForCommands = finalized.BodyForCommands.replace(
            audioPlaceholder,
            hookResult.transcript,
          );
        }
      }
      if (hookResult?.skipAudio) {
        skipBuiltinAudio = true;
      }
      if (hookResult?.clearAudioMetadata) {
        clearedAudioMetadata = true;
        const audioExtensions = [".ogg", ".mp3", ".wav", ".m4a", ".aac", ".opus", ".flac"];
        const isAudioPath = (p: string) =>
          audioExtensions.some((ext) => p.toLowerCase().endsWith(ext));
        const isAudioType = (t: string) => t.startsWith("audio/") || t === "audio";

        // Strip audio entries from media fields so the agent doesn't see audio attachments
        if (finalized.MediaTypes) {
          const audioIndices = new Set(
            finalized.MediaTypes.map((t, i) => (isAudioType(t) ? i : -1)).filter((i) => i >= 0),
          );
          finalized.MediaTypes = finalized.MediaTypes.filter((_, i) => !audioIndices.has(i));
          if (finalized.MediaUrls) {
            finalized.MediaUrls = finalized.MediaUrls.filter((_, i) => !audioIndices.has(i));
          }
          if (finalized.MediaPaths) {
            finalized.MediaPaths = finalized.MediaPaths.filter((_, i) => !audioIndices.has(i));
          }
        }
        if (finalized.MediaType && isAudioType(finalized.MediaType)) {
          finalized.MediaType = undefined;
        }
        if (finalized.MediaUrl && isAudioPath(finalized.MediaUrl)) {
          finalized.MediaUrl = undefined;
        }
        if (finalized.MediaPath && isAudioPath(finalized.MediaPath)) {
          finalized.MediaPath = undefined;
        }
      }
    }

    const mediaCfg = skipBuiltinAudio
      ? {
          ...cfg,
          tools: {
            ...cfg.tools,
            media: { ...cfg.tools?.media, audio: { ...cfg.tools?.media?.audio, enabled: false } },
          },
        }
      : cfg;

    // Skip media understanding entirely when plugin cleared all media (audio-only message)
    const hasMedia =
      (finalized.MediaTypes?.length ?? 0) > 0 ||
      (finalized.MediaUrls?.length ?? 0) > 0 ||
      finalized.MediaType ||
      finalized.MediaUrl;

    if (hasMedia || !clearedAudioMetadata) {
      await applyMediaUnderstanding({
        ctx: finalized,
        cfg: mediaCfg,
        agentDir,
        activeModel: { provider, model },
      });
    }
    await applyLinkUnderstanding({
      ctx: finalized,
      cfg,
    });
  }

  const commandAuthorized = finalized.CommandAuthorized;
  resolveCommandAuthorization({
    ctx: finalized,
    cfg,
    commandAuthorized,
  });
  const sessionState = await initSessionState({
    ctx: finalized,
    cfg,
    commandAuthorized,
  });
  let {
    sessionCtx,
    sessionEntry,
    previousSessionEntry,
    sessionStore,
    sessionKey,
    sessionId,
    isNewSession,
    resetTriggered,
    systemSent,
    abortedLastRun,
    storePath,
    sessionScope,
    groupResolution,
    isGroup,
    triggerBodyNormalized,
    bodyStripped,
  } = sessionState;

  await applyResetModelOverride({
    cfg,
    resetTriggered,
    bodyStripped,
    sessionCtx,
    ctx: finalized,
    sessionEntry,
    sessionStore,
    sessionKey,
    storePath,
    defaultProvider,
    defaultModel,
    aliasIndex,
  });

  const directiveResult = await resolveReplyDirectives({
    ctx: finalized,
    cfg,
    agentId,
    agentDir,
    workspaceDir,
    agentCfg,
    sessionCtx,
    sessionEntry,
    sessionStore,
    sessionKey,
    storePath,
    sessionScope,
    groupResolution,
    isGroup,
    triggerBodyNormalized,
    commandAuthorized,
    defaultProvider,
    defaultModel,
    aliasIndex,
    provider,
    model,
    typing,
    opts,
    skillFilter: opts?.skillFilter,
  });
  if (directiveResult.kind === "reply") {
    return directiveResult.reply;
  }

  let {
    commandSource,
    command,
    allowTextCommands,
    skillCommands,
    directives,
    cleanedBody,
    elevatedEnabled,
    elevatedAllowed,
    elevatedFailures,
    defaultActivation,
    resolvedThinkLevel,
    resolvedVerboseLevel,
    resolvedReasoningLevel,
    resolvedElevatedLevel,
    execOverrides,
    blockStreamingEnabled,
    blockReplyChunking,
    resolvedBlockStreamingBreak,
    provider: resolvedProvider,
    model: resolvedModel,
    modelState,
    contextTokens,
    inlineStatusRequested,
    directiveAck,
    perMessageQueueMode,
    perMessageQueueOptions,
  } = directiveResult.result;
  provider = resolvedProvider;
  model = resolvedModel;

  const inlineActionResult = await handleInlineActions({
    ctx,
    sessionCtx,
    cfg,
    agentId,
    agentDir,
    sessionEntry,
    previousSessionEntry,
    sessionStore,
    sessionKey,
    storePath,
    sessionScope,
    workspaceDir,
    isGroup,
    opts,
    typing,
    allowTextCommands,
    inlineStatusRequested,
    command,
    skillCommands,
    directives,
    cleanedBody,
    elevatedEnabled,
    elevatedAllowed,
    elevatedFailures,
    defaultActivation: () => defaultActivation,
    resolvedThinkLevel,
    resolvedVerboseLevel,
    resolvedReasoningLevel,
    resolvedElevatedLevel,
    resolveDefaultThinkingLevel: modelState.resolveDefaultThinkingLevel,
    provider,
    model,
    contextTokens,
    directiveAck,
    abortedLastRun,
    skillFilter: opts?.skillFilter,
  });
  if (inlineActionResult.kind === "reply") {
    return inlineActionResult.reply;
  }
  directives = inlineActionResult.directives;
  abortedLastRun = inlineActionResult.abortedLastRun ?? abortedLastRun;

  await stageSandboxMedia({
    ctx,
    sessionCtx,
    cfg,
    sessionKey,
    workspaceDir,
  });

  return runPreparedReply({
    ctx,
    sessionCtx,
    cfg,
    agentId,
    agentDir,
    agentCfg,
    sessionCfg,
    commandAuthorized,
    command,
    commandSource,
    allowTextCommands,
    directives,
    defaultActivation,
    resolvedThinkLevel,
    resolvedVerboseLevel,
    resolvedReasoningLevel,
    resolvedElevatedLevel,
    execOverrides,
    elevatedEnabled,
    elevatedAllowed,
    blockStreamingEnabled,
    blockReplyChunking,
    resolvedBlockStreamingBreak,
    modelState,
    provider,
    model,
    perMessageQueueMode,
    perMessageQueueOptions,
    typing,
    opts,
    defaultProvider,
    defaultModel,
    timeoutMs,
    isNewSession,
    resetTriggered,
    systemSent,
    sessionEntry,
    sessionStore,
    sessionKey,
    sessionId,
    storePath,
    workspaceDir,
    abortedLastRun,
  });
}
