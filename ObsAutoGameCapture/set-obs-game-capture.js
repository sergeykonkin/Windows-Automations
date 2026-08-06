// One-shot obs-websocket v5 client: retarget "Game Capture" at a game's
// window, fit it to the canvas, and enable/disable the scene item.
// Invoked per-event by obs-auto-game-capture.ps1 - see README.md.
//
// Uses game_capture (not window_capture) so anti-cheat-protected games get
// properly hooked (anti_cheat_hook) and exclusive-fullscreen games remain
// capturable - window_capture can't see either case reliably.
//
// Usage:
//   node set-obs-game-capture.js --exe <name.exe> [--pid <pid>]   retarget + enable
//   node set-obs-game-capture.js --off                            disable
//   node set-obs-game-capture.js --list                           debug dump, no changes
//
// Exit codes: 0 ok, 1 OBS unreachable, 2 auth failed, 3 watchdog timeout,
// 4 not found (scene/input/window - normal "not ready yet" case), 5 unexpected, 6 no password.

'use strict';

const crypto = require('crypto');

const CONFIG = {
    url: 'ws://127.0.0.1:4455',
    sceneName: 'Scene',
    inputName: 'Game Capture',
};

const OP = {
    HELLO: 0,
    IDENTIFY: 1,
    IDENTIFIED: 2,
    EVENT: 5,
    REQUEST: 6,
    REQUEST_RESPONSE: 7,
};

function log(msg) {
    process.stderr.write(`${msg}\n`);
}

class ObsRequestError extends Error {
    constructor(requestType, code, comment) {
        super(`${requestType} failed: [${code}] ${comment}`);
        this.code = code;
        this.comment = comment;
    }
}

function computeAuthResponse(password, salt, challenge) {
    const secret = crypto.createHash('sha256').update(password + salt).digest('base64');
    return crypto.createHash('sha256').update(secret + challenge).digest('base64');
}

// Connects, performs the Identify handshake, and returns { ws, request(type, data) }.
// Rejects with err.kind = 'unreachable' | 'auth' if the socket closes before Identified.
function connectAndIdentify(password) {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(CONFIG.url);
        const pending = new Map();
        let requestCounter = 0;
        let identified = false;

        function request(requestType, requestData) {
            return new Promise((res, rej) => {
                const requestId = String(++requestCounter);
                pending.set(requestId, { resolve: res, reject: rej, requestType });
                ws.send(JSON.stringify({ op: OP.REQUEST, d: { requestType, requestId, requestData } }));
            });
        }

        ws.addEventListener('message', (ev) => {
            let msg;
            try {
                msg = JSON.parse(ev.data);
            } catch {
                return;
            }

            if (msg.op === OP.HELLO) {
                const identify = { rpcVersion: msg.d.rpcVersion, eventSubscriptions: 0 };
                if (msg.d.authentication) {
                    identify.authentication = computeAuthResponse(password, msg.d.authentication.salt, msg.d.authentication.challenge);
                }
                ws.send(JSON.stringify({ op: OP.IDENTIFY, d: identify }));
            } else if (msg.op === OP.IDENTIFIED) {
                identified = true;
                resolve({ ws, request });
            } else if (msg.op === OP.REQUEST_RESPONSE) {
                const p = pending.get(msg.d.requestId);
                if (!p) return;
                pending.delete(msg.d.requestId);
                if (msg.d.requestStatus.result) {
                    p.resolve(msg.d.responseData || {});
                } else {
                    p.reject(new ObsRequestError(p.requestType, msg.d.requestStatus.code, msg.d.requestStatus.comment));
                }
            }
        });

        ws.addEventListener('error', () => {
            // swallow - Node's built-in WebSocket gives no usable message here, close follows
        });

        ws.addEventListener('close', (ev) => {
            if (identified) return;
            const err = new Error(ev.reason || `closed before Identified (code ${ev.code})`);
            err.kind = ev.code === 4009 ? 'auth' : 'unreachable';
            reject(err);
        });
    });
}

// Resolves CONFIG.sceneName/inputName against what's actually in OBS, falling back
// to the unique game_capture input by kind if the configured name is stale.
// Returns null (after logging a diagnostic dump) if resolution fails.
async function resolveTargets(request) {
    const sceneList = await request('GetSceneList', {});
    const scenes = sceneList.scenes.map((s) => s.sceneName);
    if (!scenes.includes(CONFIG.sceneName)) {
        log(`ERROR scene "${CONFIG.sceneName}" not found. Available scenes: ${scenes.join(', ')}`);
        return null;
    }

    const inputList = await request('GetInputList', {});
    let inputName = CONFIG.inputName;
    const names = inputList.inputs.map((i) => i.inputName);
    if (!names.includes(inputName)) {
        const gcInputs = inputList.inputs.filter((i) => i.inputKind === 'game_capture');
        if (gcInputs.length === 1) {
            inputName = gcInputs[0].inputName;
            log(`WARN input "${CONFIG.inputName}" not found, falling back to unique game_capture input "${inputName}"`);
        } else {
            const desc = inputList.inputs.map((i) => `${i.inputName} (${i.inputKind})`).join(', ');
            log(`ERROR input "${CONFIG.inputName}" not found and ${gcInputs.length} game_capture inputs exist. Available inputs: ${desc}`);
            return null;
        }
    }

    return { sceneName: CONFIG.sceneName, inputName };
}

// itemValue is "Title:Class:exe" with colons inside title/class escaped by OBS,
// so the exe name is always safely recoverable as the last ':'-segment.
function matchWindowByExe(items, exeName) {
    const wanted = exeName.toLowerCase();
    const matches = items.filter((it) => {
        const parts = it.itemValue.split(':');
        return parts[parts.length - 1].toLowerCase() === wanted;
    });
    return matches.find((it) => it.itemEnabled) || matches[0] || null;
}

async function runLaunch(request, exeName) {
    const targets = await resolveTargets(request);
    if (!targets) return 4;

    const props = await request('GetInputPropertiesListPropertyItems', {
        inputName: targets.inputName,
        propertyName: 'window',
    });
    const match = matchWindowByExe(props.propertyItems, exeName);
    if (!match) {
        log(`NOTFOUND no OBS-visible window for exe "${exeName}" yet`);
        return 4;
    }

    // capture_mode: 'window' targets a specific window rather than "any fullscreen
    // app" or the hotkey-driven mode. priority: 2 = "match title, otherwise find
    // window of same executable" (window classes are shared across unrelated apps,
    // a real mistargeting risk if left on the title-then-class fallback).
    // anti_cheat_hook enables OBS to hook anti-cheat-protected games (EAC,
    // BattlEye, VAC) - the main reason to use game_capture over window_capture.
    // All three already match game_capture's OBS defaults; set explicitly anyway
    // so this call self-heals the source if someone changes it in the OBS UI.
    await request('SetInputSettings', {
        inputName: targets.inputName,
        inputSettings: { capture_mode: 'window', window: match.itemValue, priority: 2, anti_cheat_hook: true },
        overlay: true,
    });

    const video = await request('GetVideoSettings', {});
    const { sceneItemId } = await request('GetSceneItemId', {
        sceneName: targets.sceneName,
        sourceName: targets.inputName,
    });

    // OBS_BOUNDS_SCALE_INNER rescales the source into these bounds every frame,
    // regardless of source size - resolution-independent, no race to guard against.
    await request('SetSceneItemTransform', {
        sceneName: targets.sceneName,
        sceneItemId,
        sceneItemTransform: {
            boundsType: 'OBS_BOUNDS_SCALE_INNER',
            boundsAlignment: 0,
            boundsWidth: video.baseWidth,
            boundsHeight: video.baseHeight,
            alignment: 0,
            positionX: video.baseWidth / 2,
            positionY: video.baseHeight / 2,
            scaleX: 1,
            scaleY: 1,
            rotation: 0,
        },
    });

    // Enable last, so the previous game's dead window never flashes on screen.
    await request('SetSceneItemEnabled', {
        sceneName: targets.sceneName,
        sceneItemId,
        sceneItemEnabled: true,
    });

    log(`OK captured "${match.itemValue}" for exe "${exeName}"`);
    return 0;
}

async function runOff(request) {
    const targets = await resolveTargets(request);
    if (!targets) return 4;

    const { sceneItemId } = await request('GetSceneItemId', {
        sceneName: targets.sceneName,
        sourceName: targets.inputName,
    });
    await request('SetSceneItemEnabled', {
        sceneName: targets.sceneName,
        sceneItemId,
        sceneItemEnabled: false,
    });

    // Clear the target window too, not just hide it - otherwise the source keeps
    // pointing at the exited game's (now-dead) window until the next launch.
    await request('SetInputSettings', {
        inputName: targets.inputName,
        inputSettings: { window: '' },
        overlay: true,
    });

    log(`OK disabled and cleared ${targets.inputName}`);
    return 0;
}

async function runList(request) {
    const sceneList = await request('GetSceneList', {});
    log(`Scenes: ${sceneList.scenes.map((s) => s.sceneName).join(', ')}`);

    const inputList = await request('GetInputList', {});
    for (const i of inputList.inputs) {
        log(`Input: ${i.inputName} (${i.inputKind})`);
    }

    const targets = await resolveTargets(request);
    if (!targets) return 4;

    const props = await request('GetInputPropertiesListPropertyItems', {
        inputName: targets.inputName,
        propertyName: 'window',
    });
    for (const it of props.propertyItems) {
        log(`Window: enabled=${it.itemEnabled} value="${it.itemValue}" name="${it.itemName}"`);
    }

    return 0;
}

function parseArgs(argv) {
    const get = (flag) => {
        const i = argv.indexOf(flag);
        return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
    };
    if (argv.includes('--list')) return { mode: 'list' };
    if (argv.includes('--off')) return { mode: 'off' };
    const exe = get('--exe');
    if (exe) return { mode: 'launch', exe };
    return { mode: null };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args.mode) {
        log('Usage: set-obs-game-capture.js (--exe <name.exe> [--pid <pid>] | --off | --list)');
        return 5;
    }

    const password = process.env.OBS_WS_SERVER_PASSWORD;
    if (!password) {
        log('ERROR OBS_WS_SERVER_PASSWORD is not set');
        return 6;
    }

    let conn;
    try {
        conn = await connectAndIdentify(password);
    } catch (err) {
        if (err.kind === 'auth') {
            log(`ERROR auth failed: ${err.message}`);
            return 2;
        }
        log(`ERROR could not reach OBS: ${err.message}`);
        return 1;
    }

    try {
        if (args.mode === 'launch') return await runLaunch(conn.request, args.exe);
        if (args.mode === 'off') return await runOff(conn.request);
        return await runList(conn.request);
    } catch (err) {
        if (err instanceof ObsRequestError) {
            log(`ERROR ${err.message}`);
            return err.code === 600 ? 4 : 5;
        }
        log(`ERROR unexpected: ${err.stack || err.message}`);
        return 5;
    } finally {
        conn.ws.close();
    }
}

// Guards against a hung promise (e.g. a half-open socket) blocking forever -
// the watcher invokes this synchronously and would hang right along with it.
const watchdog = setTimeout(() => {
    log('ERROR watchdog timeout after 10s');
    process.exit(3);
}, 10000);

main()
    .then((code) => {
        clearTimeout(watchdog);
        process.exit(code);
    })
    .catch((err) => {
        clearTimeout(watchdog);
        log(`ERROR unhandled: ${err.stack || err.message}`);
        process.exit(5);
    });
