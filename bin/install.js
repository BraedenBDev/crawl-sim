#!/usr/bin/env node

// crawl-sim installer
// Usage:
//   npx crawl-sim install              → ~/.claude/skills/crawl-sim/
//   npx crawl-sim install --project    → ./.claude/skills/crawl-sim/
//   npx crawl-sim install --dir <path> → <path>/crawl-sim/
//   npx crawl-sim install --codex      → ~/plugins/crawl-sim/ + ~/.agents/plugins/marketplace.json

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');
const { execFileSync } = require('child_process');

const SOURCE_DIR = path.resolve(__dirname, '..');
const SKILL_ROOT = path.resolve(SOURCE_DIR, 'skills', 'crawl-sim');
const SKILL_FILES = ['SKILL.md'];
const SKILL_DIRS = ['profiles', 'scripts'];
const CODEX_FILES = ['README.md', 'LICENSE'];
const CODEX_DIRS = ['.codex-plugin', 'skills'];
const CODEX_MARKETPLACE_PATH = path.resolve(os.homedir(), '.agents', 'plugins', 'marketplace.json');

function parseArgs(argv) {
  const args = { command: null, project: false, dir: null, codex: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === 'install' || a === 'uninstall') args.command = a;
    else if (a === '--codex') args.codex = true;
    else if (a === '--project') args.project = true;
    else if (a === '--dir') args.dir = argv[++i];
    else if (a === '-h' || a === '--help') args.help = true;
  }
  return args;
}

function printHelp() {
  console.log(`
crawl-sim — Multi-bot visibility audit for Claude Code and Codex

Usage (recommended):
  npm install -g @braedenbuilds/crawl-sim
  crawl-sim install              Install the skill to ~/.claude/skills/crawl-sim/
  crawl-sim install --project    Install to ./.claude/skills/crawl-sim/
  crawl-sim install --dir <path> Install to <path>/crawl-sim/
  crawl-sim install --codex      Install the Codex plugin to ~/plugins/crawl-sim/

After installing, invoke in Claude Code with: /crawl-sim <url>
After installing for Codex, open Plugins, install crawl-sim from your local marketplace, then ask Codex to use @crawl-sim on a URL.

Not using npm? Clone the repo directly:
  git clone https://github.com/BraedenBDev/crawl-sim.git ~/.claude/skills/crawl-sim
  git clone https://github.com/BraedenBDev/crawl-sim.git ~/plugins/crawl-sim
`);
}

function validateArgs(args) {
  if (args.codex && (args.project || args.dir)) {
    console.error('Error: --codex currently supports only the default install path (~/plugins/crawl-sim)');
    process.exit(2);
  }
}

function resolveTarget(args) {
  if (args.codex) return path.resolve(os.homedir(), 'plugins', 'crawl-sim');
  let target;
  if (args.dir) {
    target = path.resolve(args.dir, 'crawl-sim');
    // Warn if installing outside $HOME (e.g., --dir /etc)
    if (!target.startsWith(os.homedir()) && !target.startsWith(process.cwd())) {
      console.warn(`  ! Warning: installing to ${target} (outside home directory)`);
      console.warn(`    If this is unintentional, use: crawl-sim install (default: ~/.claude/skills/)`);
    }
    return target;
  }
  if (args.project) return path.resolve(process.cwd(), '.claude', 'skills', 'crawl-sim');
  return path.resolve(os.homedir(), '.claude', 'skills', 'crawl-sim');
}

function checkPrereq(cmd, installHint) {
  try {
    execFileSync(cmd, ['--version'], { stdio: 'ignore' });
    return true;
  } catch {
    console.warn(`  ! ${cmd} not found — ${installHint}`);
    return false;
  }
}

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dest, entry));
    }
  } else {
    fs.copyFileSync(src, dest);
  }
}

function copyOrExit(src, dest, label) {
  if (!fs.existsSync(src)) {
    console.error(`  ✗ missing source: ${label}`);
    process.exit(1);
  }
  if (fs.existsSync(dest)) {
    fs.rmSync(dest, { recursive: true, force: true });
  }
  copyRecursive(src, dest);
  console.log(`  ✓ ${label}`);
}

function installClaudeFiles(target) {
  fs.mkdirSync(target, { recursive: true });

  for (const file of SKILL_FILES) {
    // Look in skills/crawl-sim/ first (canonical), fallback to root (symlink)
    let src = path.join(SKILL_ROOT, file);
    if (!fs.existsSync(src)) src = path.join(SOURCE_DIR, file);
    const dest = path.join(target, file);
    if (!fs.existsSync(src)) {
      console.error(`  ✗ missing source: ${file}`);
      process.exit(1);
    }
    fs.copyFileSync(src, dest);
    console.log(`  ✓ ${file}`);
  }

  for (const dir of SKILL_DIRS) {
    let src = path.join(SKILL_ROOT, dir);
    if (!fs.existsSync(src)) src = path.join(SOURCE_DIR, dir);
    const dest = path.join(target, dir);
    copyOrExit(src, dest, `${dir}/`);
  }
}

function installCodexFiles(target) {
  fs.mkdirSync(target, { recursive: true });

  for (const file of CODEX_FILES) {
    const src = path.join(SOURCE_DIR, file);
    const dest = path.join(target, file);
    if (!fs.existsSync(src)) {
      console.error(`  ✗ missing source: ${file}`);
      process.exit(1);
    }
    fs.copyFileSync(src, dest);
    console.log(`  ✓ ${file}`);
  }

  for (const dir of CODEX_DIRS) {
    copyOrExit(path.join(SOURCE_DIR, dir), path.join(target, dir), `${dir}/`);
  }
}

function makeScriptsExecutable(scriptsDir) {
  for (const script of fs.readdirSync(scriptsDir)) {
    if (script.endsWith('.sh')) {
      fs.chmodSync(path.join(scriptsDir, script), 0o755);
    }
  }
  console.log(`  ✓ scripts chmod +x`);
}

function ensureCodexMarketplaceEntry() {
  let marketplace = {
    name: 'local-personal',
    interface: { displayName: 'Local Plugins' },
    plugins: [],
  };

  if (fs.existsSync(CODEX_MARKETPLACE_PATH)) {
    try {
      marketplace = JSON.parse(fs.readFileSync(CODEX_MARKETPLACE_PATH, 'utf8'));
    } catch (err) {
      console.error(`Error: failed to parse ${CODEX_MARKETPLACE_PATH}: ${err.message}`);
      process.exit(1);
    }
  }

  if (!Array.isArray(marketplace.plugins)) marketplace.plugins = [];
  if (!marketplace.name) marketplace.name = 'local-personal';
  if (!marketplace.interface || typeof marketplace.interface !== 'object') {
    marketplace.interface = {};
  }
  if (!marketplace.interface.displayName) {
    marketplace.interface.displayName = 'Local Plugins';
  }

  const entry = {
    name: 'crawl-sim',
    source: {
      source: 'local',
      path: './plugins/crawl-sim',
    },
    policy: {
      installation: 'AVAILABLE',
      authentication: 'ON_INSTALL',
    },
    category: 'Developer Tools',
  };

  const existingIndex = marketplace.plugins.findIndex((plugin) => plugin && plugin.name === 'crawl-sim');
  if (existingIndex >= 0) marketplace.plugins[existingIndex] = entry;
  else marketplace.plugins.push(entry);

  fs.mkdirSync(path.dirname(CODEX_MARKETPLACE_PATH), { recursive: true });
  fs.writeFileSync(CODEX_MARKETPLACE_PATH, `${JSON.stringify(marketplace, null, 2)}\n`);
  console.log(`  ✓ marketplace entry: ${CODEX_MARKETPLACE_PATH}`);
}

function removeCodexMarketplaceEntry() {
  if (!fs.existsSync(CODEX_MARKETPLACE_PATH)) return;
  let marketplace;
  try {
    marketplace = JSON.parse(fs.readFileSync(CODEX_MARKETPLACE_PATH, 'utf8'));
  } catch {
    return;
  }
  if (!Array.isArray(marketplace.plugins)) return;
  const nextPlugins = marketplace.plugins.filter((plugin) => plugin && plugin.name !== 'crawl-sim');
  if (nextPlugins.length === marketplace.plugins.length) return;
  marketplace.plugins = nextPlugins;
  fs.writeFileSync(CODEX_MARKETPLACE_PATH, `${JSON.stringify(marketplace, null, 2)}\n`);
  console.log(`✓ updated ${CODEX_MARKETPLACE_PATH}`);
}

function finishInstall(target, args) {
  if (args.codex) {
    console.log(`\n✓ crawl-sim Codex plugin installed to: ${target}`);
    console.log('\nUsage:');
    console.log('  1. Restart Codex if it is already open.');
    console.log('  2. Open Plugins and install crawl-sim from your local marketplace.');
    console.log('  3. Ask Codex to use @crawl-sim on a URL.');
    console.log(`  Marketplace: ${CODEX_MARKETPLACE_PATH}`);
    return;
  }

  console.log(`\n✓ crawl-sim installed to: ${target}`);
  console.log('\nUsage:');
  console.log('  In Claude Code: /crawl-sim https://yoursite.com');
  console.log('  Direct shell:   ' + path.join(target, 'scripts', 'fetch-as-bot.sh') + ' <url> ' + path.join(target, 'profiles', 'gptbot.json'));
}

function install(target, args) {
  console.log(`Installing crawl-sim ${args.codex ? 'Codex plugin' : 'Claude skill'} to: ${target}`);

  if (args.codex) {
    installCodexFiles(target);
    makeScriptsExecutable(path.join(target, 'skills', 'crawl-sim', 'scripts'));
    ensureCodexMarketplaceEntry();
  } else {
    installClaudeFiles(target);
    makeScriptsExecutable(path.join(target, 'scripts'));
  }

  // Prerequisite check
  console.log('\nPrerequisites:');
  const hasCurl = checkPrereq('curl', 'pre-installed on macOS/Linux');
  const hasJq = checkPrereq('jq', 'install with: brew install jq  (or: apt install jq)');
  let hasPlaywright = false;
  try {
    execFileSync('npx', ['playwright', '--version'], { stdio: 'ignore' });
    hasPlaywright = true;
    console.log('  ✓ playwright');
  } catch {
    // handled below with interactive prompt
  }

  if (!hasCurl || !hasJq) {
    console.error('\nMissing required prerequisites. Install them and re-run.');
    process.exit(1);
  }

  if (!hasPlaywright) {
    return promptPlaywright(() => finishInstall(target, args));
  }

  finishInstall(target, args);
}

function promptPlaywright(onComplete) {
  console.log('\n  Playwright is not installed.');
  console.log('  It\'s optional but recommended. It enables JS render comparison,');
  console.log('  which is how crawl-sim differentiates Googlebot from AI crawlers.');
  console.log('  Without it, all bots score the same on content visibility.\n');

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.question('  Install Playwright + Chromium now? (y/N) ', (answer) => {
    rl.close();
    if (answer.trim().toLowerCase() === 'y') {
      console.log('\n  Installing Playwright and Chromium (this may take a minute)...\n');
      try {
        execFileSync('npx', ['playwright', 'install', 'chromium'], { stdio: 'inherit' });
        console.log('\n  ✓ Playwright + Chromium installed');
      } catch {
        console.warn('\n  ! Playwright installation failed. You can retry later with:');
        console.warn('    npx playwright install chromium');
      }
    } else {
      console.log('\n  Skipped. You can install later with: npx playwright install chromium');
    }
    onComplete();
  });
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  validateArgs(args);

  if (args.help || !args.command) {
    printHelp();
    process.exit(args.help ? 0 : 1);
  }

  if (args.command === 'install') {
    install(resolveTarget(args), args);
  } else if (args.command === 'uninstall') {
    const target = resolveTarget(args);
    if (fs.existsSync(target)) {
      fs.rmSync(target, { recursive: true, force: true });
      console.log(`✓ removed ${target}`);
      if (args.codex) removeCodexMarketplaceEntry();
    } else {
      console.log(`Not installed at ${target}`);
    }
  }
}

main();
