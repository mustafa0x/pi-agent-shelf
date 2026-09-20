import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir, tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { createJiti } = require('jiti');
const packageDir = process.env.FAST_MODE_PACKAGE_DIR
    ?? join(homedir(), '.pi/agent/npm/node_modules/pi-openai-fast-mode');
const repoDir = dirname(dirname(fileURLToPath(import.meta.url)));
const jiti = createJiti(import.meta.url, {
    virtualModules: {
        '@earendil-works/pi-coding-agent': {
            getAgentDir() { throw new Error('Tests must use an isolated agentDir'); },
        },
    },
});
const { createPiFastModeExtension } = await jiti.import(join(packageDir, 'src/index.ts'));

function setup(t, fastFlag = false) {
    const directory = mkdtempSync(join(tmpdir(), 'shelf-fast-'));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const handlers = new Map();
    const commands = new Map();
    const errors = [];
    const ctx = {
        cwd: directory,
        hasUI: true,
        mode: 'tui',
        model: { provider: 'openai-codex', id: 'gpt-5.6-sol' },
        ui: { notify: (message) => errors.push(message), setStatus() {}, setWidget() {} },
        sessionManager: {
            getSessionId: () => 'session-a',
            getSessionFile: () => join(directory, 'session.jsonl'),
        },
    };
    const api = {
        registerFlag() {},
        getFlag: () => fastFlag,
        registerCommand: (name, command) => commands.set(name, command),
        on: (event, handler) => handlers.set(event, handler),
    };
    createPiFastModeExtension({ agentDir: directory, extensionDir: packageDir })(api);
    const path = join(directory, 'session-runtime', `${process.pid}.fast.json`);
    return {
        directory, ctx, errors, path,
        report: () => JSON.parse(readFileSync(path, 'utf8')),
        event: (name, value = {}) => handlers.get(name)(value, ctx),
        command: (args) => commands.get('fast').handler(args, ctx),
    };
}

test('reports live setting on startup, toggles, model changes, and cleans up', async (t) => {
    const h = setup(t);
    assert.equal(existsSync(h.path), false, 'No factory-time I/O');
    await h.event('session_start');
    assert.deepEqual(h.report(), {
        pid: process.pid, session_id: 'session-a', session_file: h.ctx.sessionManager.getSessionFile(),
        provider: 'openai-codex', model: 'gpt-5.6-sol', enabled: false,
    });
    await h.command('on');
    assert.equal(h.report().enabled, true);
    await h.event('model_select', { model: { provider: 'anthropic', id: 'unsupported' } });
    assert.equal(h.report().enabled, false);
    await h.event('model_select', { model: h.ctx.model });
    assert.equal(h.report().enabled, true);
    await h.command('off');
    assert.equal(h.report().enabled, false);
    await h.event('session_shutdown');
    assert.equal(existsSync(h.path), false);
    assert.deepEqual(h.errors, []);
});

test('uses process-local state, not another session’s saved config', async (t) => {
    const h = setup(t, true);
    await h.event('session_start');
    assert.equal(h.report().enabled, true);
    const configPath = join(h.directory, 'extensions/pi-openai-fast-mode/config.json');
    const shared = JSON.parse(readFileSync(configPath, 'utf8'));
    writeFileSync(configPath, JSON.stringify({ ...shared, enabled: false }));
    await h.event('model_select', { model: h.ctx.model });
    assert.equal(h.report().enabled, true);
    assert.equal(h.event('before_provider_request', { payload: {} }).service_tier, 'priority');
    await h.event('session_shutdown');
    assert.deepEqual(h.errors, []);
});

test('reporting errors do not change Fast payload behavior', async (t) => {
    const h = setup(t, true);
    writeFileSync(join(h.directory, 'session-runtime'), 'not a directory');
    await h.event('session_start');
    assert.equal(h.errors.length, 1);
    assert.equal(h.event('before_provider_request', { payload: {} }).service_tier, 'priority');
});

test('installer is reproducible, idempotent, and rejects unknown source', (t) => {
    const directory = mkdtempSync(join(tmpdir(), 'shelf-fast-patch-'));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    cpSync(join(packageDir, 'src'), join(directory, 'src'), { recursive: true });
    const patch = readFileSync(join(repoDir, 'Integrations/fast-mode/pi-openai-fast-mode-0.5.0.patch'));
    execFileSync('patch', ['--batch', '-R', '-p1', '-d', directory], { input: patch });
    const installer = join(repoDir, 'scripts/enable-fast-mode-status.sh');
    execFileSync('sh', [installer, directory]);
    assert.match(execFileSync('sh', [installer, directory], { encoding: 'utf8' }), /already enabled/);
    const entry = join(directory, 'src/index.ts');
    assert.equal(readFileSync(entry, 'utf8'), readFileSync(join(packageDir, 'src/index.ts'), 'utf8'));
    writeFileSync(entry, '// unknown version');
    assert.throws(() => execFileSync('sh', [installer, directory], { stdio: 'pipe' }));
    assert.equal(readFileSync(entry, 'utf8'), '// unknown version');
});
