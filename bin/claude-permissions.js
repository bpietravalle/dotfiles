#!/usr/bin/env node
// Claude permissions merger
//
// MERGE LOGIC (simple version):
//   1. Combine all permissions from global + local
//   2. If same permission in multiple arrays → most restrictive wins
//   3. Precedence: deny > ask > allow
//
// WHAT THIS MEANS:
//   - Global deny always wins (can't be overridden by local)
//   - Local-specific permissions are preserved
//   - Duplicates across arrays resolve to most restrictive
//
// EXAMPLE:
//   global: { allow: ["A", "B"], deny: ["C"] }
//   local:  { allow: ["B", "D"], ask: ["A"] }
//   merged: { allow: ["B", "D"], ask: ["A"], deny: ["C"] }
//   (A demoted to ask, B deduped, C stays denied, D added)

const fs = require('fs');
const path = require('path');

const HOME = process.env.HOME;
const CLAUDE_DIR = path.join(HOME, '.claude');
const GLOBAL_SETTINGS = path.join(CLAUDE_DIR, 'settings.json');
const SEARCH_ROOTS = [path.join(HOME, 'projects'), path.join(HOME, 'dev')];
const THIS_REPO = path.resolve(__dirname, '..');

// Directories to skip when searching
const IGNORE_DIRS = new Set([
  'node_modules', '.git', '.terraform', '.venv', 'venv',
  '__pycache__', '.mypy_cache', '.pytest_cache', '.tox',
  'dist', 'build', '.next', '.nuxt', 'target', 'vendor',
  '.cargo', 'pkg', 'deps', '_build', '.elixir_ls'
]);

// Parse args
const args = process.argv.slice(2);
const isGlobal = args.includes('--global') || args.includes('-g');

// --first N flag (default 1 if no number)
let firstN = null;
let firstArgCount = 0; // how many args to skip for --first
const firstIdx = args.findIndex(a => a === '--first' || a === '-f');
if (firstIdx !== -1) {
  firstArgCount = 1;
  const nextArg = args[firstIdx + 1];
  if (nextArg && !nextArg.startsWith('-') && /^\d+$/.test(nextArg)) {
    firstN = parseInt(nextArg, 10);
    firstArgCount = 2;
  } else {
    firstN = 1;
  }
  if (isNaN(firstN) || firstN < 1) firstN = 1;
}

// --force flag: re-merge all, don't skip "synced"
const forceMode = args.includes('--force');

// Find command (skip flags and --first's value)
const cmd = args.find((a, i) => {
  if (a.startsWith('-')) return false;
  if (firstIdx !== -1 && i === firstIdx + 1 && /^\d+$/.test(a)) return false;
  return true;
}) || 'show';

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════

function load(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function save(file, data) {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}

function getPerms(obj) {
  return {
    allow: obj?.permissions?.allow || [],
    deny: obj?.permissions?.deny || [],
    ask: obj?.permissions?.ask || []
  };
}

// Find .claude/settings.local.json walking up from cwd
function findLocalSettings() {
  let dir = process.cwd();
  while (dir !== '/') {
    const candidate = path.join(dir, '.claude', 'settings.local.json');
    if (fs.existsSync(candidate)) {
      return candidate;
    }
    dir = path.dirname(dir);
  }
  return path.join(process.cwd(), '.claude', 'settings.local.json');
}

// Find all .claude/ directories in search roots
function findAllProjects() {
  const projects = [];

  function walk(dir, depth = 0) {
    if (depth > 5) return; // Max depth

    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        if (IGNORE_DIRS.has(entry.name)) continue;
        if (entry.name.startsWith('.') && entry.name !== '.claude') continue;

        const fullPath = path.join(dir, entry.name);

        // Skip this repo
        if (fullPath === THIS_REPO) continue;

        if (entry.name === '.claude') {
          const localFile = path.join(fullPath, 'settings.local.json');
          const projectRoot = dir;
          projects.push({
            name: path.basename(projectRoot),
            root: projectRoot,
            localFile,
            exists: fs.existsSync(localFile)
          });
        } else {
          walk(fullPath, depth + 1);
        }
      }
    } catch {
      // Permission denied, etc.
    }
  }

  for (const root of SEARCH_ROOTS) {
    if (fs.existsSync(root)) {
      walk(root);
    }
  }

  return projects.sort((a, b) => a.name.localeCompare(b.name));
}

// ═══════════════════════════════════════════════════════════════
// SINGLE PROJECT COMMANDS
// ═══════════════════════════════════════════════════════════════

function show() {
  const global = load(GLOBAL_SETTINGS);
  const localFile = findLocalSettings();
  const local = load(localFile);

  if (!global) {
    console.log('No settings.json found');
    return;
  }

  const g = getPerms(global);
  const l = getPerms(local);

  console.log('=== Global ===');
  console.log(`Path: ${GLOBAL_SETTINGS}`);
  console.log(`allow: ${g.allow.length}, deny: ${g.deny.length}, ask: ${g.ask.length}`);

  console.log('\n=== Local ===');
  console.log(`Path: ${localFile}`);
  if (local) {
    console.log(`allow: ${l.allow.length}, deny: ${l.deny.length}, ask: ${l.ask.length}`);
  } else {
    console.log('(not found)');
  }
}

function merge() {
  const global = load(GLOBAL_SETTINGS);
  if (!global) {
    console.log('No settings.json found');
    process.exit(1);
  }

  const localFile = findLocalSettings();
  let local = load(localFile);
  const g = getPerms(global);
  const l = getPerms(local);

  const deny = [...new Set([...g.deny, ...l.deny])].sort();

  const askSet = new Set([...g.ask, ...l.ask]);
  deny.forEach(d => askSet.delete(d));
  const ask = [...askSet].sort();

  const allowSet = new Set([...g.allow, ...l.allow]);
  deny.forEach(d => allowSet.delete(d));
  ask.forEach(a => allowSet.delete(a));
  const allow = [...allowSet].sort();

  const merged = {
    ...(local || global),
    permissions: { allow, deny, ask }
  };

  if (merged.permissions.deny.length === 0) delete merged.permissions.deny;
  if (merged.permissions.ask.length === 0) delete merged.permissions.ask;

  save(localFile, merged);

  console.log('Merged → settings.local.json');
  console.log(`allow: ${allow.length}, deny: ${deny.length}, ask: ${ask.length}`);
}

function diff() {
  const global = load(GLOBAL_SETTINGS);
  const localFile = findLocalSettings();
  const local = load(localFile);

  if (!global || !local) {
    console.log('Need both files for diff');
    return;
  }

  const g = getPerms(global);
  const l = getPerms(local);

  const onlyLocal = l.allow.filter(x => !g.allow.includes(x));
  const onlyGlobal = g.allow.filter(x => !l.allow.includes(x));

  if (onlyLocal.length) {
    console.log('=== Local-only allow ===');
    onlyLocal.forEach(x => console.log(`  ${x}`));
  }
  if (onlyGlobal.length) {
    console.log('=== Global-only allow ===');
    onlyGlobal.forEach(x => console.log(`  ${x}`));
  }
  if (!onlyLocal.length && !onlyGlobal.length) {
    console.log('No differences in allow arrays');
  }
}

// ═══════════════════════════════════════════════════════════════
// GLOBAL COMMANDS (--global flag)
// ═══════════════════════════════════════════════════════════════

function globalShow() {
  const global = load(GLOBAL_SETTINGS);
  if (!global) {
    console.log('No global settings.json found');
    return;
  }

  const g = getPerms(global);
  console.log(`Global: allow=${g.allow.length} deny=${g.deny.length} ask=${g.ask.length}`);
  console.log('');

  let projects = findAllProjects();
  if (firstN) {
    console.log(`(--first ${firstN}: showing ${firstN} of ${projects.length} projects)`);
    projects = projects.slice(0, firstN);
  }
  if (projects.length === 0) {
    console.log('No projects found in ~/projects/ or ~/dev/');
    return;
  }

  // Table header
  console.log('Project'.padEnd(35) + 'Allow'.padStart(6) + 'Deny'.padStart(6) + 'Ask'.padStart(6) + '  Status');
  console.log('─'.repeat(65));

  for (const proj of projects) {
    const local = load(proj.localFile);
    const l = getPerms(local);
    const name = proj.name.length > 33 ? proj.name.slice(0, 30) + '...' : proj.name;

    if (proj.exists) {
      const synced = l.allow.length >= g.allow.length ? '✓' : '⚠ needs merge';
      console.log(
        name.padEnd(35) +
        String(l.allow.length).padStart(6) +
        String(l.deny.length).padStart(6) +
        String(l.ask.length).padStart(6) +
        '  ' + synced
      );
    } else {
      console.log(name.padEnd(35) + '     -     -     -  (no local)');
    }
  }
}

function globalDiff() {
  const global = load(GLOBAL_SETTINGS);
  if (!global) {
    console.log('No global settings.json found');
    return;
  }

  const g = getPerms(global);
  let projects = findAllProjects();
  if (firstN) {
    console.log(`(--first ${firstN}: checking ${firstN} of ${projects.length} projects)\n`);
    projects = projects.slice(0, firstN);
  }

  let needsMerge = 0;
  let noLocal = 0;
  let synced = 0;

  for (const proj of projects) {
    if (!proj.exists) {
      noLocal++;
      continue;
    }

    const local = load(proj.localFile);
    const l = getPerms(local);
    const missing = g.allow.filter(x => !l.allow.includes(x));

    if (missing.length > 0) {
      needsMerge++;
      console.log(`${proj.name}: missing ${missing.length} global permissions`);
    } else {
      synced++;
    }
  }

  console.log('');
  console.log(`Summary: ${synced} synced, ${needsMerge} need merge, ${noLocal} no local file`);
}

function globalMerge() {
  const global = load(GLOBAL_SETTINGS);
  if (!global) {
    console.log('No global settings.json found');
    process.exit(1);
  }

  const g = getPerms(global);
  let projects = findAllProjects();
  const totalProjects = projects.length;

  // Get valid MCP prefixes from global (mcp__context7, mcp__serena, etc)
  const validMcpPrefixes = new Set();
  [...g.allow, ...g.deny, ...g.ask].forEach(p => {
    if (p.startsWith('mcp__')) {
      const prefix = p.split('__').slice(0, 2).join('__');
      validMcpPrefixes.add(prefix);
    }
  });

  if (firstN) {
    projects = projects.slice(0, firstN);
    console.log(`(--first ${firstN}: merging ${firstN} of ${totalProjects} projects)`);
  } else {
    console.log(`Syncing global permissions to ${totalProjects} projects...`);
  }
  if (forceMode) console.log('(--force: re-syncing all)');
  console.log('');

  let merged = 0;
  let created = 0;
  let skipped = 0;

  for (const proj of projects) {
    const local = load(proj.localFile);
    const l = getPerms(local);

    // Filter local: keep non-MCP perms + only valid MCP perms
    const filterValid = arr => arr.filter(p => {
      if (!p.startsWith('mcp__')) return true; // keep non-MCP
      const prefix = p.split('__').slice(0, 2).join('__');
      return validMcpPrefixes.has(prefix); // keep only valid MCPs
    });

    const localFiltered = {
      allow: filterValid(l.allow),
      deny: filterValid(l.deny),
      ask: filterValid(l.ask)
    };

    // Now merge: global + filtered local
    const deny = [...new Set([...g.deny, ...localFiltered.deny])].sort();
    const askSet = new Set([...g.ask, ...localFiltered.ask]);
    deny.forEach(d => askSet.delete(d));
    const ask = [...askSet].sort();
    const allowSet = new Set([...g.allow, ...localFiltered.allow]);
    deny.forEach(d => allowSet.delete(d));
    ask.forEach(a => allowSet.delete(a));
    const allow = [...allowSet].sort();

    // Check if already synced (skip unless --force)
    if (!forceMode && local &&
        l.allow.length === allow.length &&
        l.deny.length === deny.length &&
        l.ask.length === ask.length) {
      skipped++;
      continue;
    }

    const mergedConfig = {
      ...(local || global),
      permissions: { allow, deny, ask }
    };

    if (mergedConfig.permissions.deny.length === 0) delete mergedConfig.permissions.deny;
    if (mergedConfig.permissions.ask.length === 0) delete mergedConfig.permissions.ask;

    save(proj.localFile, mergedConfig);

    if (proj.exists) {
      console.log(`✓ ${proj.name}: synced (allow: ${l.allow.length} → ${allow.length})`);
      merged++;
    } else {
      console.log(`+ ${proj.name}: created (allow: ${allow.length})`);
      created++;
    }
  }

  console.log('');
  console.log(`Done: ${merged} synced, ${created} created, ${skipped} unchanged`);
}

// ═══════════════════════════════════════════════════════════════
// DISPATCH
// ═══════════════════════════════════════════════════════════════

if (isGlobal) {
  switch (cmd) {
    case 'show': globalShow(); break;
    case 'diff': globalDiff(); break;
    case 'merge': globalMerge(); break;
    default:
      console.log('Usage: claude-permissions.js --global [show|diff|merge]');
  }
} else {
  switch (cmd) {
    case 'show': show(); break;
    case 'merge': merge(); break;
    case 'diff': diff(); break;
    default:
      console.log('Usage: claude-permissions.js [show|merge|diff] [--global]');
  }
}
