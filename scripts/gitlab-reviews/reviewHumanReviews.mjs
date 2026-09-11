#!/usr/bin/env node
// Review the local human review ledger and record local verdicts. It never writes to GitLab.
import { CONFIG_FILE, DEFAULT_OUTPUT, DEFAULT_REPOSITORY, DEFAULT_USER, OPEN_STATUSES, readLedger, writeLedgerAtomic } from './humanReviewsLib.mjs';

// `| head` closes stdout early; an EPIPE there is not a review failure.
process.stdout.on('error', (error) => {
    if (error.code === 'EPIPE') process.exit(0);
    throw error;
});

const args = process.argv.slice(2);
const output = process.env.HR_OUT ?? DEFAULT_OUTPUT;
if (!process.env.HR_OUT && !(DEFAULT_REPOSITORY && DEFAULT_USER)) {
    process.stderr.write(`No ledger. Set HR_OUT, or add "repository" and "user" to ${CONFIG_FILE}.\n`);
    process.exit(1);
}
const STATUSES = new Set(['pending', 'applied', 'rejected', 'stale', 'superseded', 'needs-recheck']);
let showAll = false;
let showExclusions = false;
let showShort = false;
const SHORT_LIMIT = Number(process.env.HR_SHORT_LIMIT ?? 60);
let statusFilter = null;
let setId = null;
let setStatus = null;
let setNote = null;

if (args[0] === '--set') {
    setId = args[1];
    setStatus = args[2];
    setNote = args.slice(3).join(' ') || null;
} else if (args.length >= 2 && !args[0].startsWith('--') && STATUSES.has(args[1])) {
    setId = args[0];
    setStatus = args[1];
    setNote = args.slice(2).join(' ') || null;
}

for (let index = setId ? args.length : 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--all') {
        showAll = true;
    } else if (argument === '--short') {
        showShort = true;
    } else if (argument === '--exclusions') {
        showExclusions = true;
    } else if (argument === '--no-exclusions') {
        showExclusions = false;
    } else if (argument === '--status') {
        statusFilter = args[index + 1] ?? '';
        index += 1;
    } else if (argument.startsWith('--status=')) {
        statusFilter = argument.slice('--status='.length);
    } else if (argument === '--help' || argument === '-h') {
        process.stdout.write('Usage: node tools-local/reviewHumanReviews.mjs [--all] [--status STATUS] [--exclusions] [--short]\n');
        process.stdout.write('       node tools-local/reviewHumanReviews.mjs --set ID STATUS [NOTE]\n');
        process.exit(0);
    } else {
        process.stderr.write(`Unknown argument: ${argument}\n`);
        process.exitCode = 1;
    }
}

if (statusFilter != null && !STATUSES.has(statusFilter)) {
    process.stderr.write(`status must be one of: ${[...STATUSES].join(', ')}\n`);
    process.exitCode = 1;
}
if (args[0] === '--set' && (!setId || !STATUSES.has(setStatus))) {
    process.stderr.write(`Usage: node tools-local/reviewHumanReviews.mjs --set ID STATUS [NOTE]\n`);
    process.exitCode = 1;
}

if (process.exitCode) {
    // Do not read or write a ledger after an invalid invocation.
} else {
    try {
        const ledger = readLedger(output);
        if (!ledger) {
            if (setId) throw new Error(`No human review ledger at ${output}`);
            process.stdout.write(`No human review ledger at ${output}\n`);
            process.exit(0);
        }
        if (setId) {
            if (!STATUSES.has(setStatus)) throw new Error(`status must be one of: ${[...STATUSES].join(', ')}`);
            const target = ledger.entries.find((entry) => entry.id === setId);
            if (!target) throw new Error(`No candidate with id ${setId}`);
            if (['applied', 'rejected', 'stale', 'superseded'].includes(setStatus) && !setNote) {
                throw new Error(`A reason is required when setting status ${setStatus}`);
            }
            target.status = setStatus;
            target.reviewedAt = new Date().toISOString();
            if (setNote) target.reviewNote = setNote;
            if (setStatus !== 'needs-recheck') delete target.previousVerdict;
            if (['applied', 'rejected', 'stale', 'superseded'].includes(setStatus)) delete target.contentChanged;
            writeLedgerAtomic(output, ledger);
            process.stdout.write(`${ledger.repository} [${setId}] -> ${setStatus}\n`);
            process.exit(0);
        }
        const entries = ledger.entries.filter((entry) => {
            if (entry.active === false && entry.status !== 'needs-recheck' && !showAll) return false;
            if (statusFilter && entry.status !== statusFilter) return false;
            return statusFilter ? entry.status === statusFilter : showAll || OPEN_STATUSES.has(entry.status ?? 'pending');
        });
        const statusCounts = new Map();
        for (const entry of ledger.entries) statusCounts.set(entry.status ?? 'pending', (statusCounts.get(entry.status ?? 'pending') ?? 0) + 1);
        const counts = [...statusCounts.entries()].map(([status, count]) => `${status}=${count}`).join(', ');
        process.stdout.write(`Human reviews: ${ledger.repository}/${ledger.reviewer.username} (${ledger.projectId})\n`);
        process.stdout.write(`Ledger: ${output}\n`);
        process.stdout.write(`Entries: ${entries.length}/${ledger.entries.length}${counts ? `; statuses ${counts}` : ''}\n`);
        if (ledger.lastRun) {
            process.stdout.write(`Last run: ${ledger.lastRun.status} ${ledger.lastRun.startedAt ?? ''} through ${ledger.lastRun.until ?? ''}\n`);
            process.stdout.write(`Coverage: ${ledger.lastRun.mergeRequestsProcessed ?? 0}/${ledger.lastRun.mergeRequestsDiscovered ?? 0} merge requests, ${ledger.lastRun.failures ?? 0} failures\n`);
        }
        if (showShort) {
            // Groups the short open candidates so a reviewer's sign-off wording is visible
            // before curating, rather than discovered one rejection at a time.
            const groups = new Map();
            for (const entry of entries) {
                const compact = String(entry.body ?? '').trim().replace(/\s+/g, ' ');
                if (compact.length > SHORT_LIMIT) continue;
                const key = compact.toLowerCase().replace(/[^a-z0-9 ]+/g, '').trim();
                const group = groups.get(key) ?? { count: 0, sample: compact, ids: [] };
                group.count += 1;
                group.ids.push(entry.id);
                groups.set(key, group);
            }
            const ordered = [...groups.values()].sort((a, b) => b.count - a.count);
            process.stdout.write(`\nShort open candidates (${SHORT_LIMIT} characters or fewer), grouped:\n`);
            process.stdout.write('A group repeating several times is usually a sign-off. Add a whole-comment\n');
            process.stdout.write('pattern to processOnlyPatterns.json beside this script rather than rejecting each one.\n\n');
            for (const group of ordered) {
                process.stdout.write(`${String(group.count).padStart(4)}x  ${group.sample}\n`);
            }
            process.exit(0);
        }
        for (const entry of entries) {
            process.stdout.write(`\n[${entry.id}] ${entry.status ?? 'pending'} !${entry.mr} ${entry.createdAt ?? ''}\n`);
            process.stdout.write(`  ${entry.mrUrl ?? '(no MR URL)'}\n`);
            process.stdout.write(`  reason: ${entry.selectionReason ?? 'new-thread-root authored by reviewer'}\n`);
            if (entry.selfAuthored) process.stdout.write(`  self-authored: the reviewer also authored this merge request, so the comment can be a self-review note rather than a finding\n`);
            process.stdout.write(`  note: ${entry.noteId}; discussion: ${entry.discussionId ?? '(individual note)'}\n`);
            process.stdout.write(`  ${entry.body}\n`);
            if (entry.previousVerdict) process.stdout.write(`  previous verdict: ${entry.previousVerdict}; content changed: recheck required\n`);
            if (entry.reviewNote) process.stdout.write(`  review note: ${entry.reviewNote}\n`);
        }
        if (showExclusions) {
            process.stdout.write(`\nExclusions: ${ledger.exclusions.length}\n`);
            for (const exclusion of ledger.exclusions) {
                process.stdout.write(`\n[${exclusion.id}] !${exclusion.mr} ${exclusion.reason}\n`);
                process.stdout.write(`  ${exclusion.mrUrl ?? '(no MR URL)'}\n`);
                process.stdout.write(`  note: ${exclusion.noteId}; ${exclusion.body}\n`);
            }
        }
        if (ledger.lastRun?.failures) {
            process.stdout.write(`\nRun failures recorded: ${ledger.lastRun.failures}\n`);
            for (const failure of ledger.lastRun.failureDetails ?? []) {
                process.stdout.write(`  ${failure.kind} ${failure.endpoint ?? ''}: ${failure.message}\n`);
            }
        }
    } catch (error) {
        process.stderr.write(`Cannot review human review ledger: ${error.message}\n`);
        process.exitCode = 1;
    }
}
