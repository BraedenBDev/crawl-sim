#!/usr/bin/env node

// crawl-sim installer
// Usage:
//   npx crawl-sim install              → ~/.claude/skills/crawl-sim/
//   npx crawl-sim install --project    → ./.claude/skills/crawl-sim/
//   npx crawl-sim install --dir <path> → <path>/crawl-sim/

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

function parseArgs(argv) {
  const args = { command: null, project: false, dir: null, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === 'install' || a === 'uninstall') args.command = a;
    else if (a === '--project') args.project = true;
    else if (a === '--dir') args.dir = argv[++i];
    else if (a === '-h' || a === '--help') args.help = true;
  }
  return args;
}

function printHelp() {
  console.log(`
crawl-sim — Multi-bot visibility audit for Claude Code

Usage (recommended):
  npm install -g @braedenbuilds/crawl-sim
  crawl-sim install              Install the skill to ~/.claude/skills/crawl-sim/
  crawl-sim install --project    Install to ./.claude/skills/crawl-sim/
  crawl-sim install --dir <path> Install to <path>/crawl-sim/

After installing, invoke in Claude Code with: /crawl-sim <url>

Not using npm? Clone the repo directly:
  git clone https://github.com/BraedenBDev/crawl-sim.git ~/.claude/skills/crawl-sim
`);
}

function resolveTarget(args) {
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

function install(target) {
  console.log(`Installing crawl-sim to: ${target}`);

  fs.mkdirSync(target, { recursive: true });

  for (const file of SKILL_FILES) {
    // Look in skills/crawl-sim/ first (canonical), fallback to root (symlink)
    let src = path.join(SKILL_ROOT, file);
    if (!fs.existsSync(src)) src = path.join(SOURCE_DIR, file);
    const dest = path.join(target, file);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, dest);
      console.log(`  ✓ ${file}`);
    } else {
      console.error(`  ✗ missing source: ${file}`);
      process.exit(1);
    }
  }

  for (const dir of SKILL_DIRS) {
    let src = path.join(SKILL_ROOT, dir);
    if (!fs.existsSync(src)) src = path.join(SOURCE_DIR, dir);
    const dest = path.join(target, dir);
    if (fs.existsSync(src)) {
      if (fs.existsSync(dest)) {
        fs.rmSync(dest, { recursive: true, force: true });
      }
      copyRecursive(src, dest);
      console.log(`  ✓ ${dir}/`);
    } else {
      console.error(`  ✗ missing source: ${dir}/`);
      process.exit(1);
    }
  }

  // Make scripts executable
  const scriptsDir = path.join(target, 'scripts');
  for (const script of fs.readdirSync(scriptsDir)) {
    if (script.endsWith('.sh')) {
      fs.chmodSync(path.join(scriptsDir, script), 0o755);
    }
  }
  console.log(`  ✓ scripts chmod +x`);

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
    return promptPlaywright(target);
  }

  printSuccess(target);
}

function promptPlaywright(target) {
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
    printSuccess(target);
  });
}

function printSuccess(target) {
  console.log(`\n✓ crawl-sim installed to: ${target}`);
  console.log('\nUsage:');
  console.log('  In Claude Code: /crawl-sim https://yoursite.com');
  console.log('  Direct shell:   ' + path.join(target, 'scripts', 'fetch-as-bot.sh') + ' <url> ' + path.join(target, 'profiles', 'gptbot.json'));
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help || !args.command) {
    printHelp();
    process.exit(args.help ? 0 : 1);
  }

  if (args.command === 'install') {
    install(resolveTarget(args));
  } else if (args.command === 'uninstall') {
    const target = resolveTarget(args);
    if (fs.existsSync(target)) {
      fs.rmSync(target, { recursive: true, force: true });
      console.log(`✓ removed ${target}`);
    } else {
      console.log(`Not installed at ${target}`);
    }
  }
}

main();
