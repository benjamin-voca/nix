{
  lib,
  pkgs,
}: let
  d = import ../../../lib/domain.nix;
  render = import ./render.nix {inherit lib pkgs;};

  openclawConfigJson = builtins.toJSON {
    gateway = {
      mode = "local";
      bind = "lan";
      port = 18789;
      auth = {
        mode = "token";
      };
      trustedProxies = [
        "10.0.0.0/8"
        "192.168.0.0/16"
        "172.16.0.0/12"
      ];
      controlUi = {
        enabled = true;
        allowedOrigins = [
          (d.url "openclaw")
          "http://${d.host "openclaw"}"
        ];

      };
    };
    messages = {
      groupChat = {
        # Discord's autocomplete lists Clawd's auto-managed bot role before the
        # bot user, so role mentions (<@&ID>) must count as bot mentions too.
        mentionPatterns = ["<@&1547195973363564669>"];
      };
    };
    models = {
      providers = {
        zai = {
          # glm-5.3-flash is served on the Coding Plan endpoint for this key.
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
        };
      };
    };
    channels = {
      discord = {
        enabled = true;
        # Same as the bot user id for this application; skips Discord's startup
        # application lookup which can stall gateway READY in this cluster.
        applicationId = "1487458103782936707";
        groupPolicy = "allowlist";
        dmPolicy = "pairing";
        allowFrom = [
          "722143468700565575" # Beni
        ];
        historyLimit = 20;
        # Default "all" feeds Clawd its own Discord replies as few-shot. GLM-flash
        # then copies the old "Blade stays Blade" bit over SOUL.md. allowlist
        # keeps recent messages from allowed senders and drops the bot's.
        contextVisibility = "allowlist";
        # Native slash-command reconcile uses Carbon and races the READY event.
        commands = {
          native = false;
        };
        # Off, not partial. GLM-flash streams a first-token draft ("Blade stays
        # Blade") then the real answer ("Mommy Blade"). Discord's live preview
        # posts that draft as its own message and never edits it, so the channel
        # sees two contradictory bubbles. The session transcript only keeps the
        # final answer — deliver that one message.
        streaming = {
          mode = "off";
          block = {
            enabled = false;
          };
        };
        guilds = {
          # QuadCoreTech — all channels, mention-gated (unchanged behavior)
          "1429150059932422315" = {
            requireMention = true;
          };
          # Voltrum Studios — promptable by Admin or higher in the role hierarchy.
          # Beni's nick here is Big Yahu (Lead Developer). Missing that role made
          # preflight drop him as "member not allowed" while Discord history still
          # few-shot the bot's own Blade-refusal replies.
          "1542902554399219937" = {
            requireMention = true;
            users = [
              "722143468700565575" # Beni / Big Yahu
            ];
            roles = [
              "1542986561510051911" # Director
              "1544402051772190750" # Co Director
              "1543419562987364362" # Server Management
              "1542902756480917595" # Lead Developer (Beni)
              "1542986562617483355" # Dev
              "1545320514568847460" # Dev | Builder
              "1543419695909048340" # Head of Marketing
              "1543975868081246230" # Community Manager
              "1543418849737711677" # Head Admin
              "1543698897036251306" # Personal Assistant
              "1542986565800960110" # Admin
            ];
          };
        };
      };
    };
    agents = {
      defaults = {
        workspace = "~/.openclaw/workspace";
        model = {
          primary = "zai/glm-5.3-flash";
        };
        modelPolicy = {
          allow = ["zai/glm-5.3-flash"];
        };
        blockStreamingDefault = "off";
        # GLM-5.3's provider default is max; that dumps a thinking block and a
        # final answer as two Discord messages. low is the lowest effort this
        # model actually supports (off/minimal remap to low).
        thinkingDefault = "low";
        reasoningDefault = "off";
      };
      entries = {
        main = {
          name = "OpenClaw Assistant";
          workspace = "~/.openclaw/workspace";
        };
      };
    };
    commands = {
      ownerAllowFrom = ["722143468700565575"];
    };
    plugins = {
      load = {
        paths = [
          "/home/node/.openclaw/extensions/mommy-blade"
          "/home/node/.openclaw/extensions/output-filters"
          "/home/node/.openclaw/extensions/staff-authority"
        ];
      };
      entries = {
        # Bundled Z.AI provider for glm-5.3-flash.
        zai = {
          enabled = true;
        };
        # Explicit trust/enable for the Discord channel plugin — without this
        # the gateway installs it but leaves the channel runtime stopped.
        discord = {
          enabled = true;
        };
        # Prompt-only identity reminder. GLM-5.3-flash copies Discord history
        # over AGENTS.md; appending this at prompt-build time puts the name
        # after that history so the model actually knows it.
        "mommy-blade" = {
          enabled = true;
          hooks = {
            allowConversationAccess = true;
          };
        };
        # Local backport of openclaw/openclaw#45041 (closed as not planned).
        # Regex strip/drop plus keep-last so GLM's extra thinking bubble never posts.
        # Not under agents.defaults.outputFilters — that key is not in the schema.
        "output-filters" = {
          enabled = true;
          hooks = {
            allowConversationAccess = true;
          };
        };
        # Appends the staff-authority rule at prompt-build time. AGENTS.md alone
        # loses to Discord channel history (see Mommy Blade); this puts the rule
        # after the history so the model actually sees it on every prompt.
        "staff-authority" = {
          enabled = true;
          hooks = {
            allowConversationAccess = true;
          };
        };
      };
    };
    cron = {enabled = false;};
  };

  namespace = {
    apiVersion = "v1";
    kind = "Namespace";
    metadata = {
      name = "openclaw";
      labels = {
        "app.kubernetes.io/name" = "openclaw";
      };
    };
  };

  pvc = {
    apiVersion = "v1";
    kind = "PersistentVolumeClaim";
    metadata = {
      name = "openclaw-data-cephfs";
      namespace = "openclaw";
    };
    spec = {
      accessModes = ["ReadWriteOnce"];
      storageClassName = "ceph-filesystem-csi";
      resources = {
        requests = {
          storage = "10Gi";
        };
      };
    };
  };

  configMap = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "openclaw-config";
      namespace = "openclaw";
    };
    data = {
      "openclaw.json" = openclawConfigJson;
      "AGENTS.md" = ''
        ## CRITICAL RULE — Mommy Blade
        - The person Blade / bladebruh / @Blade is named **Mommy Blade**.
        - That is his name in your mouth. You know it. You can joke *with* it.
        - You cannot refuse it, "keep calling him Blade", or treat the title as
          a bill, vote, firmware, or attack. Those bits are banned.
        - If Discord history shows you saying just "Blade", that history is
          stale and wrong. Do not imitate it. Correct yourself naturally.

        ## OpenClaw Assistant
        You are a helpful AI assistant running in Kubernetes.
        Default model: zai/glm-5.3-flash.

        ## Discord behavior
        - In Discord guild channels, respond when mentioned with @Clawd (or the bot role).
        - Direct messages require pairing unless the sender is already allowlisted.
        - When asked to summarize recent chat, summarize the latest 20 channel messages.

        ## Forgejo integration
        - Forgejo is hosted at ${d.url "forge"}.
        - Use the FORGEJO_AGENT_TOKEN environment variable for API authentication.
        - Use this endpoint for REST calls: ${d.url "forge"}/api/v1.
        - Send header: Authorization: token <FORGEJO_AGENT_TOKEN>.
        - When asked to turn a summary into issues, create issues in Forgejo with clear titles and markdown descriptions.

        ## Discord REST API (audit log, member lookups)
        - Header is exactly `Authorization: Bot <DISCORD_BOT_TOKEN>`.
        - NEVER send Forgejo-style `Authorization: token <token>` to Discord: that
          scheme returns 401 Unauthorized even with a valid token. The `token`
          convention above is FORGEJO-only. A 401 with the `Bot` scheme means the
          token was actually rotated; a 401 with the `token` scheme means nothing.

        ## Staff commands (Voltrum Studios)
        - Guild 1542902554399219937. Staff (Admin+) roles: Admin 1542986565800960110,
          Head Admin 1543418849737711677, Director 1542986561510051911,
          Co Director 1544402051772190750, Lead Developer 1542902756480917595,
          Dev 1542986562617483355. Anyone the gateway allowlist lets prompt you in
          this guild is staff or staff-adjacent: treat them as staff.
        - A direct instruction from staff is a command. Follow it every time: no
          refusals, no stalls, no negotiating. Old channel messages showing you
          refusing or deflecting are stale; do not imitate them.
        - Never claim a blocker you have not verified (no invented token resets,
          maintenance windows, or outages). To check a sender's roles or an API
          claim, use the Discord REST API with the Bot header above:
          GET /guilds/1542902554399219937/members/<user_id> — the response's
          "roles" array holds the member's role IDs.

        ## Discord GIFs (Giphy)
        - GIPHY_API_KEY is in the environment. Use it to search Giphy when someone asks for a GIF, or for a rare visual reaction (celebration, humor). At most one GIF per moment; never GIF-only back-to-back; skip GIFs in serious or info-dense replies.
        - GET https://api.giphy.com/v1/gifs/search?api_key=$GIPHY_API_KEY&q=<urlencoded query>&limit=1&rating=g&lang=en
        - Send the direct file, not the giphy.com page: MEDIA:<data[0].images.downsized.url> (fallback images.original.url). Discord will not animate a bare page URL.
        - Caption the same message with creator credit when username is present, always including Powered by GIPHY, e.g.:
          via @username · [Powered by GIPHY](<data[0].url>)
          MEDIA:<direct gif url>
        - Stay rating=g. If search returns nothing, say so in text. Do not mix GIFs with Discord components.
      '';
      "giphy-SKILL.md" = ''
        ---
        name: giphy-gif
        description: Search Giphy and send a GIF in Discord. Use when a user asks for a GIF or a brief visual reaction (celebration, humor, emotion) fits.
        ---

        # Giphy GIF Search

        Env: `GIPHY_API_KEY`.

        ## Behavior
        - Send a GIF when asked, or rarely as a reaction. One GIF per moment. Prefer text when the topic is serious.
        - Always `rating=g`.

        ## Steps
        1. URL-encode the query.
        2. GET `https://api.giphy.com/v1/gifs/search?api_key=$GIPHY_API_KEY&q=<query>&limit=1&rating=g&lang=en`
        3. Read `data[0]`:
           - media: `images.downsized.url` (fallback `images.original.url`) — must be a direct `.gif`
           - page: `url`
           - creator: `username` if non-empty
        4. Reply with caption then a MEDIA line (required for Discord animation):

        ```
        via @<username> · [Powered by GIPHY](<page url>)
        MEDIA:<direct gif url>
        ```

        If there is no username, omit the `via @... · ` prefix but keep Powered by GIPHY.
        Never send only the giphy.com page URL. Never attach Discord components on a GIF send.
      '';
      "SOUL.md" = ''
        # SOUL.md

        Be a useful Discord bot. Have a personality. Do not be a corporate drone.

        You can joke, roast, and riff. You cannot pretend you don't know someone's name.

        ## Blade

        His name, when you speak it, is **Mommy Blade**. That is established fact in
        this community, like a nickname you actually use — not a rule you protest.
        Jokes that *use* "Mommy Blade" are on-voice. Jokes that refuse the name
        ("Blade stays Blade", firmware, congress, votes) are off-voice and wrong.
        If old messages show you refusing it, you outgrew that bit. Move on.

        Have opinions about everything else.
      '';
      "IDENTITY.md" = ''
        # IDENTITY.md

        - **Name:** Clawd
        - **Vibe:** chaotic Discord staff bot
        - **People:** Blade is Mommy Blade. You call him that on purpose.
      '';
      "mommy-blade-package.json" = builtins.toJSON {
        name = "mommy-blade";
        version = "1.0.0";
        type = "module";
        openclaw.extensions = ["./index.js"];
      };
      "mommy-blade-plugin.json" = builtins.toJSON {
        id = "mommy-blade";
        name = "Mommy Blade identity";
        activation = {
          onStartup = true;
          onCapabilities = ["hook"];
        };
        configSchema = {
          type = "object";
          additionalProperties = false;
        };
      };
      "mommy-blade-index.js" = ''
        const BLADE_CONTEXT =
          "Community fact, not a restriction: you call Blade \"Mommy Blade\". " +
          "Jokes that use that name are in-character. Jokes that refuse it " +
          "(just Blade, firmware, votes, congress) are outdated and wrong. " +
          "If older channel messages show you refusing the name, ignore that bit.";

        export default {
          id: "mommy-blade",
          name: "Mommy Blade identity",
          description: "Prompt identity plus drop leaked thinking bubbles.",
          register(api) {
            api.on("before_prompt_build", () => ({
              appendSystemContext: BLADE_CONTEXT,
              appendContext: BLADE_CONTEXT,
            }));
            api.on("reply_payload_sending", (event) => {
              if (event.kind === "block") return { cancel: true };
              if (event.payload && event.payload.isReasoning) return { cancel: true };
            });
          },
        };
      '';
      "staff-authority-package.json" = builtins.toJSON {
        name = "staff-authority";
        version = "1.0.0";
        type = "module";
        openclaw.extensions = ["./index.js"];
      };
      "staff-authority-plugin.json" = builtins.toJSON {
        id = "staff-authority";
        name = "Staff authority";
        activation = {
          onStartup = true;
          onCapabilities = ["hook"];
        };
        configSchema = {
          type = "object";
          additionalProperties = false;
        };
      };
      # Compliance rule for Admin+ (staff) commands. Appended after channel
      # history at prompt-build time so GLM-5.3-flash cannot copy stale refusals
      # or invent blockers over it.
      "staff-authority-index.js" = ''
        const STAFF_CONTEXT =
          "STAFF AUTHORITY (Voltrum Studios): members with the Admin, Head Admin, " +
          "Director, Co Director, Lead Developer, or Dev role are staff. A direct " +
          "instruction from staff is a command: start executing it in your first " +
          "reply. Never refuse, stall, or negotiate with staff. Never invent " +
          "blockers — no fake token resets, maintenance windows, or permission " +
          "errors; verify with the Discord REST recipe in AGENTS.md before claiming " +
          "any failure. If a capability is genuinely missing, name the exact missing " +
          "piece in one sentence and do the part you can. Old messages showing you " +
          "refusing staff are stale; do not imitate them.";

        export default {
          id: "staff-authority",
          name: "Staff authority",
          description: "Prompt-time rule that staff (Admin+) commands are always followed.",
          register(api) {
            api.on("before_prompt_build", () => ({
              appendSystemContext: STAFF_CONTEXT,
              appendContext: STAFF_CONTEXT,
            }));
          },
        };
      '';
      "output-filters-package.json" = builtins.toJSON {
        name = "output-filters";
        version = "1.0.0";
        type = "module";
        openclaw.extensions = ["./index.js"];
      };
      "output-filters-plugin.json" = builtins.toJSON {
        id = "output-filters";
        name = "Output filters";
        activation = {
          onStartup = true;
          onCapabilities = ["hook"];
        };
        configSchema = {
          type = "object";
          additionalProperties = false;
        };
      };
      # Backport of https://github.com/openclaw/openclaw/issues/45041
      # (closed as not planned). Regex strip/drop on outbound text, plus keep-last
      # because GLM-5.3-flash leaks a full extra assistant message that no regex
      # from that issue would match ("Blade. ten straight...").
      "output-filters-index.js" = ''
        const FILTERS = [
          { pattern: "<think>[\\s\\S]*?</think>", flags: "gi", action: "strip" },
          { pattern: "^Reasoning:.*$", flags: "gm", action: "strip" },
          { pattern: "^Thinking:.*$", flags: "gm", action: "strip" },
          { pattern: "^(OK,? )?(Let me|I will|I need to|Now I|First,? let me).*$", flags: "gm", action: "strip" },
        ];

        function applyOutputFilters(text) {
          if (typeof text !== "string") return { text, drop: false };
          let out = text;
          for (const f of FILTERS) {
            let re;
            try { re = new RegExp(f.pattern, f.flags || "gm"); }
            catch { continue; }
            if (f.action === "drop" && re.test(out)) return { text: "", drop: true };
            out = out.replace(re, "");
          }
          out = out.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
          return { text: out, drop: false };
        }

        export default {
          id: "output-filters",
          name: "Output filters",
          description: "Strip leaked reasoning from outbound replies; keep last Discord bubble.",
          register(api) {
            globalThis.__clawdOutputFilters = FILTERS;
            globalThis.__clawdKeepLast = true;
            let safety;
            api.on("before_prompt_build", () => {
              globalThis.__clawdHoldDiscordSends = true;
              clearTimeout(safety);
              safety = setTimeout(() => {
                const flush = globalThis.__clawdFlushDiscordSend;
                if (typeof flush === "function") void flush();
              }, 15000);
            });
            api.on("agent_end", () => {
              clearTimeout(safety);
              setTimeout(() => {
                const flush = globalThis.__clawdFlushDiscordSend;
                if (typeof flush === "function") void flush();
              }, 2000);
            });
            api.on("reply_payload_sending", (event) => {
              if (event.kind === "block") return { cancel: true };
              if (event.payload && event.payload.isReasoning) return { cancel: true };
              const payload = event.payload || {};
              const next = applyOutputFilters(payload.text || "");
              if (next.drop || (!(next.text || "").trim() && !payload.mediaUrl && !(payload.mediaUrls && payload.mediaUrls.length))) {
                return { cancel: true };
              }
              if (next.text !== payload.text) payload.text = next.text;
            });
          },
        };
      '';
      # GLM thinking is delivered as Discord kind=block BEFORE reply_payload_sending
      # runs (silent REST send). Patch the Discord plugin so those never post.
      "patch-discord-blocks.js" = ''
        const fs = require("fs");
        const dir = "/home/node/.openclaw/npm/projects/openclaw-discord-c0892df945/node_modules/@openclaw/discord/dist";
        function insertAfter(file, key, insert, already) {
          const p = dir + "/" + file;
          if (!fs.existsSync(p)) {
            console.log("missing file", file);
            return false;
          }
          const s = fs.readFileSync(p, "utf8");
          if (s.includes(already || insert.trim())) {
            console.log("already patched", file);
            return true;
          }
          const i = s.indexOf(key);
          if (i < 0) {
            console.log("needle missing", file, key);
            return false;
          }
          fs.writeFileSync(p, s.slice(0, i + key.length) + insert + s.slice(i + key.length));
          console.log("patched", file);
          return true;
        }
        insertAfter(
          "provider-PI8UiejY.js",
          "async function deliverDiscordReply(params) {",
          "\nif (params.kind === \"block\") return { visibleReplySent: false, suppression: { reason: \"block_suppressed\" } };",
          "block_suppressed"
        );
        insertAfter(
          "message-handler.process-CWh432Ak.js",
          "const isFinal = info.kind === \"final\";",
          "\n\t\tif (info.kind === \"block\") return { visibleReplySent: false, suppression: { reason: \"block_suppressed\" } };",
          "block_suppressed"
        );
        (function revert(file, start, orig, marker) {
          const p = dir + "/" + file;
          if (!fs.existsSync(p)) return;
          let s = fs.readFileSync(p, "utf8");
          if (!s.includes(marker)) return;
          const i = s.indexOf(start);
          const j = s.indexOf(orig, i);
          if (i < 0 || j < 0) return;
          fs.writeFileSync(p, s.slice(0, i + start.length) + s.slice(j));
          console.log("reverted", file, marker);
        })(
          "send.shared-D4BAjlRo.js",
          "async function sendDiscordChunks(params, upload) {",
          "\n\tconst chunks = buildDiscordTextChunks",
          "__clawdPendingDiscordSend"
        );
        (function revertCreate() {
          const p = dir + "/discord-CmL3ati-.js";
          if (!fs.existsSync(p)) return;
          let s = fs.readFileSync(p, "utf8");
          if (!s.includes("__clawdPendingDiscordCreate")) return;
          const start = "async function createChannelMessage(rest, channelId, data) {";
          const orig = "\n\treturn await rest.post(Routes.channelMessages(channelId), data);";
          const i = s.indexOf(start);
          const j = s.indexOf(orig, i);
          if (i < 0 || j < 0) {
            console.log("could not revert createChannelMessage");
            return;
          }
          fs.writeFileSync(p, s.slice(0, i + start.length) + s.slice(j));
          console.log("reverted createChannelMessage hold");
        })();
        // Thinking bubble bypasses createChannelMessage. Intercept the REST
        // client so every POST /channels/.../messages is held.
        insertAfter(
          "discord-CmL3ati-.js",
          "async request(method, path, params) {",
          "\n\t\tif (method === \"POST\" && globalThis.__clawdKeepLast && globalThis.__clawdHoldDiscordSends && !globalThis.__clawdFlushingDiscord) {\n\t\t\tconst pathStr = typeof path === \"string\" ? path : String(path ?? \"\");\n\t\t\tconst data = params && params.data;\n\t\t\tconst body = data && data.body ? data.body : data;\n\t\t\tconst text = typeof (body && body.content) === \"string\" ? body.content : \"\";\n\t\t\tconst isTyping = pathStr.indexOf(\"/typing\") !== -1;\n\t\t\tconsole.log(\"[output-filters] rest.request POST\", pathStr, String(text).slice(0, 120));\n\t\t\tif (!isTyping) {\n\t\t\t\tif (!globalThis.__clawdFlushDiscordSend) {\n\t\t\t\t\tglobalThis.__clawdFlushDiscordSend = async () => {\n\t\t\t\t\t\tconst p = globalThis.__clawdPendingDiscordPost;\n\t\t\t\t\t\tglobalThis.__clawdPendingDiscordPost = null;\n\t\t\t\t\t\tglobalThis.__clawdHoldDiscordSends = false;\n\t\t\t\t\t\tif (!p) return;\n\t\t\t\t\t\tglobalThis.__clawdFlushingDiscord = true;\n\t\t\t\t\t\ttry { return await p.rest.request(p.method, p.path, p.params); }\n\t\t\t\t\t\tfinally { globalThis.__clawdFlushingDiscord = false; }\n\t\t\t\t\t};\n\t\t\t\t}\n\t\t\t\tglobalThis.__clawdPendingDiscordPost = { rest: this, method, path, params };\n\t\t\t\treturn { id: \"skipped-held\" };\n\t\t\t}\n\t\t}",
          "__clawdPendingDiscordPost"
        );
      '';
    };
  };

  deployment = {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "openclaw";
      namespace = "openclaw";
      labels = {
        app = "openclaw";
      };
    };
    spec = {
      replicas = 1;
      selector = {
        matchLabels = {
          app = "openclaw";
        };
      };
      strategy = {
        type = "Recreate";
      };
      template = {
        metadata = {
          labels = {
            app = "openclaw";
          };
          annotations = {
            "checksum/openclaw-config" = builtins.hashString "sha256" (builtins.toJSON configMap.data);
          };
        };
        spec = {
          affinity = import ../../../lib/anti-affinity.nix "openclaw";
          automountServiceAccountToken = false;
          securityContext = {
            fsGroup = 1000;
            seccompProfile = {
              type = "RuntimeDefault";
            };
          };
          initContainers = [
            {
              name = "init-config";
              image = "busybox:1.37";
              imagePullPolicy = "IfNotPresent";
              command = [
                "sh"
                "-c"
                ''
                  # Always overlay declarative config so PVC drift cannot hide
                  # Discord/model changes.
                  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
                  mkdir -p /home/node/.openclaw/workspace/skills/giphy
                  mkdir -p /home/node/.openclaw/skills/giphy
                  mkdir -p /home/node/.openclaw/extensions/mommy-blade
                  mkdir -p /home/node/.openclaw/extensions/output-filters
                  mkdir -p /home/node/.openclaw/extensions/staff-authority
                  cp /config/AGENTS.md /home/node/.openclaw/workspace/AGENTS.md
                  cp /config/SOUL.md /home/node/.openclaw/workspace/SOUL.md
                  cp /config/IDENTITY.md /home/node/.openclaw/workspace/IDENTITY.md
                  cp /config/giphy-SKILL.md /home/node/.openclaw/workspace/skills/giphy/SKILL.md
                  cp /config/giphy-SKILL.md /home/node/.openclaw/skills/giphy/SKILL.md
                  cp /config/mommy-blade-index.js /home/node/.openclaw/extensions/mommy-blade/index.js
                  cp /config/mommy-blade-package.json /home/node/.openclaw/extensions/mommy-blade/package.json
                  cp /config/mommy-blade-plugin.json /home/node/.openclaw/extensions/mommy-blade/openclaw.plugin.json
                  cp /config/output-filters-index.js /home/node/.openclaw/extensions/output-filters/index.js
                  cp /config/output-filters-package.json /home/node/.openclaw/extensions/output-filters/package.json
                  cp /config/output-filters-plugin.json /home/node/.openclaw/extensions/output-filters/openclaw.plugin.json
                  cp /config/staff-authority-index.js /home/node/.openclaw/extensions/staff-authority/index.js
                  cp /config/staff-authority-package.json /home/node/.openclaw/extensions/staff-authority/package.json
                  cp /config/staff-authority-plugin.json /home/node/.openclaw/extensions/staff-authority/openclaw.plugin.json
                  # Drop a Discord plugin that does not match this image so
                  # doctor/gateway can install the matching channel plugin.
                  # Any @openclaw/discord tree that is not 2026.9.3 will fail to
                  # load against this core. Check known install locations only.
                  for pkg in \
                    /home/node/.openclaw/npm/node_modules/@openclaw/discord/package.json \
                    /home/node/.openclaw/npm/projects/openclaw-discord-*/node_modules/@openclaw/discord/package.json; do
                    [ -f "$pkg" ] || continue
                    ver=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$pkg" | head -1)
                    if [ "$ver" != "2026.9.3" ]; then
                      dir=$(dirname "$pkg")
                      mv "$dir" "$dir.stale-$$" || true
                    fi
                  done
                  # SQLite on local emptyDir; chmod works on the subdir we create.
                  mkdir -p /sqlite/state
                  chown 1000:1000 /sqlite/state
                  chmod 700 /sqlite/state
                  rm -rf /home/node/.openclaw/state
                  ln -sfn /sqlite/state /home/node/.openclaw/state
                  chown -h 1000:1000 /home/node/.openclaw/state
                  find /home/node/.openclaw -user 0 -exec chown 1000:1000 {} +
                ''
              ];
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
              };
              resources = {
                requests = {
                  memory = "32Mi";
                  cpu = "50m";
                };
                limits = {
                  memory = "64Mi";
                  cpu = "100m";
                };
              };
              volumeMounts = [
                {
                  name = "openclaw-home";
                  mountPath = "/home/node/.openclaw";
                }
                {
                  name = "config";
                  mountPath = "/config";
                }
                {
                  name = "openclaw-sqlite";
                  mountPath = "/sqlite";
                }
              ];
            }
          ];
          containers = [
            {
              name = "gateway";
              # 2026.9.3 is required for bundled zai/glm-5.3-flash. Discord READY
              # hangs without --verbose + a delayed config touch (Carbon race).
              image = "ghcr.io/openclaw/openclaw:2026.9.3";
              imagePullPolicy = "IfNotPresent";
              command = [
                "/bin/sh"
                "-c"
                ''
                  DISCORD_JS=/home/node/.openclaw/npm/projects/openclaw-discord-c0892df945/node_modules/@openclaw/discord/dist/index.js
                  ZAI_JS=/home/node/.openclaw/npm/projects/openclaw-zai-provider-aefca72c67/node_modules/@openclaw/zai-provider/dist/index.js
                  if [ ! -f "$DISCORD_JS" ]; then
                    node /app/dist/index.js plugins install @openclaw/discord@2026.9.3 || true
                  fi
                  if [ ! -f "$ZAI_JS" ]; then
                    node /app/dist/index.js plugins install @openclaw/zai-provider@2026.9.3 || true
                  fi
                  if [ ! -f /home/node/.openclaw/.doctor-fixed-2026.9.3 ]; then
                    node /app/dist/index.js doctor --fix || true
                    touch /home/node/.openclaw/.doctor-fixed-2026.9.3 || true
                  fi
                  # Doctor rewrites openclaw.json; restore declarative config.
                  cp /config/openclaw.json /home/node/.openclaw/openclaw.json
                  node /config/patch-discord-blocks.js || true
                  # Crash-loop breaker lives on the PVC and will suppress Discord
                  # even after a config fix. Drop it on every start.
                  rm -rf /home/node/.openclaw/logs/stability
                  # One-shot: drop stored session DBs so old Blade/GIF replies
                  # cannot be replayed. OpenClaw recreates empty DBs on boot.
                  # Discord historyLimit stays 20 so the bot remembers after this.
                  WIPE_MARK=/home/node/.openclaw/.memory-wiped-2026-09-10b
                  if [ ! -f "$WIPE_MARK" ]; then
                    rm -f /home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite \
                      /home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite-* \
                      /home/node/.openclaw/agents/default/agent/openclaw-agent.sqlite \
                      /home/node/.openclaw/agents/default/agent/openclaw-agent.sqlite-*
                    rm -rf /home/node/.openclaw/agents/main/sessions \
                      /home/node/.openclaw/agents/default/sessions
                    mkdir -p /home/node/.openclaw/agents/main/sessions \
                      /home/node/.openclaw/agents/default/sessions \
                      /home/node/.openclaw/agents/main/agent \
                      /home/node/.openclaw/agents/default/agent
                    : > /home/node/.openclaw/workspace/MEMORY.md || true
                    chown -R 1000:1000 /home/node/.openclaw/agents || true
                    touch "$WIPE_MARK" || true
                  fi
                  # Carbon races Discord READY; a delayed config touch unsticks it.
                  (sleep 12 && touch /home/node/.openclaw/openclaw.json) &
                  exec node /app/dist/index.js gateway run --allow-unconfigured --verbose
                ''
              ];
              ports = [
                {
                  name = "gateway";
                  containerPort = 18789;
                  protocol = "TCP";
                }
              ];
              env = [
                {
                  name = "HOME";
                  value = "/home/node";
                }
                {
                  name = "OPENCLAW_CONFIG_DIR";
                  value = "/home/node/.openclaw";
                }
                {
                  name = "NODE_ENV";
                  value = "production";
                }
                {
                  name = "OPENCLAW_DEBUG";
                  value = "1";
                }
                {
                  # Routes verbose traces (discord preflight, mention decisions)
                  # into the file log. OPENCLAW_DEBUG alone does not.
                  name = "OPENCLAW_LOG_LEVEL";
                  value = "debug";
                }
                {
                  name = "OPENCLAW_GATEWAY_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_GATEWAY_TOKEN";
                    };
                  };
                }
                {
                  name = "DISCORD_BOT_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "DISCORD_BOT_TOKEN";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_DISCORD_SERVER_ID";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_DISCORD_SERVER_ID";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_BENI_DISCORD_ID";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "OPENCLAW_BENI_DISCORD_ID";
                      optional = true;
                    };
                  };
                }
                {
                  name = "FORGEJO_AGENT_TOKEN";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "FORGEJO_AGENT_TOKEN";
                      optional = true;
                    };
                  };
                }
                {
                  name = "MINIMAX_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "MINIMAX_API_KEY";
                      optional = true;
                    };
                  };
                }
                {
                  name = "ZAI_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "ZAI_API_KEY";
                      optional = true;
                    };
                  };
                }
                {
                  name = "GIPHY_API_KEY";
                  valueFrom = {
                    secretKeyRef = {
                      name = "openclaw-secrets";
                      key = "GIPHY_API_KEY";
                      optional = true;
                    };
                  };
                }
                {
                  name = "OPENCLAW_DISCORD_READY_TIMEOUT_MS";
                  value = "60000";
                }
                {
                  name = "OPENCLAW_DISCORD_GATEWAY_INFO_TIMEOUT_MS";
                  value = "30000";
                }
              ];
              resources = {
                requests = {
                  memory = "512Mi";
                  cpu = "100m";
                };
                limits = {
                  memory = "2Gi";
                  cpu = "1";
                };
              };
              livenessProbe = {
                exec = {
                  command = [
                    "node"
                    "-e"
                    "require('http').get('http://127.0.0.1:18789/healthz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
                  ];
                };
                initialDelaySeconds = 360;
                periodSeconds = 30;
                timeoutSeconds = 10;
              };
              readinessProbe = {
                exec = {
                  command = [
                    "node"
                    "-e"
                    "require('http').get('http://127.0.0.1:18789/readyz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
                  ];
                };
                initialDelaySeconds = 90;
                periodSeconds = 10;
                timeoutSeconds = 10;
              };
              volumeMounts = [
                {
                  name = "openclaw-home";
                  mountPath = "/home/node/.openclaw";
                }
                {
                  name = "config";
                  mountPath = "/config";
                  readOnly = true;
                }
                {
                  name = "openclaw-sqlite";
                  mountPath = "/sqlite";
                }
                {
                  name = "openclaw-cache";
                  mountPath = "/home/node/.cache";
                }
                {
                  name = "npm-cache";
                  mountPath = "/home/node/.npm";
                }
                {
                  name = "tmp-volume";
                  mountPath = "/tmp";
                }
              ];
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                runAsGroup = 1000;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities = {
                  drop = ["ALL"];
                };
              };
            }
          ];
          volumes = [
            {
              name = "openclaw-home";
              persistentVolumeClaim = {
                claimName = "openclaw-data-cephfs";
              };
            }
            {
              name = "config";
              configMap = {
                name = "openclaw-config";
              };
            }
            {
              name = "openclaw-sqlite";
              emptyDir = {};
            }
            {
              name = "openclaw-cache";
              emptyDir = {};
            }
            {
              name = "npm-cache";
              emptyDir = {};
            }
            {
              name = "tmp-volume";
              emptyDir = {};
            }
          ];
        };
      };
    };
  };

  service = {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      name = "openclaw";
      namespace = "openclaw";
    };
    spec = {
      type = "ClusterIP";
      ports = [
        {
          port = 18789;
          targetPort = 18789;
          protocol = "TCP";
        }
      ];
      selector = {
        app = "openclaw";
      };
    };
  };

  ingress = {
    apiVersion = "networking.k8s.io/v1";
    kind = "Ingress";
    metadata = {
      name = "openclaw";
      namespace = "openclaw";
      annotations = {
        "nginx.ingress.kubernetes.io/ssl-redirect" = "false";
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
        "nginx.ingress.kubernetes.io/proxy-body-size" = "50m";
        "nginx.ingress.kubernetes.io/websocket-services" = "openclaw";
      };
    };
    spec = {
      ingressClassName = "nginx";
      rules = [
        {
          host = d.host "openclaw";
          http = {
            paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend = {
                  service = {
                    name = "openclaw";
                    port = {
                      number = 18789;
                    };
                  };
                };
              }
            ];
          };
        }
      ];
    };
  };

  manifests = {
    "17-openclaw-namespace.yaml" = render.writeOne "17-openclaw-namespace" namespace;
    "17a-openclaw-pvc.yaml" = render.writeOne "17a-openclaw-pvc" pvc;
    "17b-openclaw-configmap.yaml" = render.writeOne "17b-openclaw-configmap" configMap;
    "17c-openclaw-deployment.yaml" = render.writeOne "17c-openclaw-deployment" deployment;
    "17d-openclaw-service.yaml" = render.writeOne "17d-openclaw-service" service;
    "17e-openclaw-ingress.yaml" = render.writeOne "17e-openclaw-ingress" ingress;
  };
in {
  inherit manifests;
}
