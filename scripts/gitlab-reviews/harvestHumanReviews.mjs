#!/usr/bin/env node
// Collect substantive new-thread reviews from one or more GitLab reviewers in a single scan.
import { readFileSync } from 'node:fs';

// Repository config comes from the checkout you run in, not from this script's directory,
// so one copy of the engine serves every repository.
const REPOS = (() => {
    const file = process.env.HR_REPOS ?? 'tools-local/repos.json';
    try {
        return JSON.parse(readFileSync(file, 'utf8'));
    } catch {
        return {};
    }
})();
import {
    CONFIG_FILE,
    DEFAULT_CONCURRENCY,
    DEFAULT_PROJECT_ID,
    DEFAULT_REPOSITORY,
    DEFAULT_SINCE,
    DEFAULT_USER,
    DEFAULT_USER_ID,
    collectHumanReviews,
    createGlabApi,
    emptyLedger,
    ledgerPathFor,
    mergeLedger,
    readLedger,
    resolveReviewer,
    validateWindow,
    writeLedgerAtomic,
} from './humanReviewsLib.mjs';

const repository = process.env.HR_REPO ?? DEFAULT_REPOSITORY;
const config = REPOS[repository];
const projectId = String(config?.projectId ?? (repository === DEFAULT_REPOSITORY ? DEFAULT_PROJECT_ID : ''));
const usernames = (process.env.HR_USERS ?? process.env.HR_USER ?? DEFAULT_USER)
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean);
const since = process.env.HR_SINCE ?? DEFAULT_SINCE;
const until = process.env.HR_UNTIL ?? new Date().toISOString();
const concurrency = Number(process.env.HR_CONCURRENCY ?? DEFAULT_CONCURRENCY);
const runId = `${new Date().toISOString()}-${process.pid}`;
const startedAt = new Date().toISOString();

const print = (line) => process.stdout.write(`${line}\n`);
const printError = (line) => process.stderr.write(`${line}\n`);

// HR_OUT names one file, so it only applies to a single-reviewer run.
const outputFor = (username) =>
    usernames.length === 1 && process.env.HR_OUT ? process.env.HR_OUT : ledgerPathFor(repository, username);

const expectedIdFor = (username) =>
    process.env.HR_USER_ID == null && username === DEFAULT_USER ? DEFAULT_USER_ID : process.env.HR_USER_ID;

if (!repository) {
    printError(`No repository. Set HR_REPO, or add "repository" to ${CONFIG_FILE}.`);
    process.exitCode = 1;
} else if (usernames.length === 0) {
    printError(`No reviewer. Set HR_USERS, or add "user" to ${CONFIG_FILE}.`);
    process.exitCode = 1;
} else if (!config && !projectId) {
    printError(`Unknown repository ${repository}. Known: ${Object.keys(REPOS).join(', ')}`);
    process.exitCode = 1;
} else if (usernames.length > 1 && process.env.HR_OUT) {
    printError('HR_OUT names a single file. Drop it when HR_USERS lists several reviewers.');
    process.exitCode = 1;
} else if (new Set(usernames).size !== usernames.length) {
    printError(`HR_USERS repeats a reviewer: ${usernames.join(', ')}`);
    process.exitCode = 1;
} else {
    try {
        validateWindow(since, until);
        if (!Number.isInteger(concurrency) || concurrency < 1) throw new Error(`HR_CONCURRENCY must be a positive integer: ${concurrency}`);

        const targets = usernames.map((username) => {
            const output = outputFor(username);
            const previous = readLedger(output) ?? emptyLedger({ repository, projectId, user: username, userId: expectedIdFor(username) ?? 0 });
            if (previous.repository !== repository || String(previous.projectId) !== projectId) {
                throw new Error(`Ledger ${output} belongs to ${previous.repository}/${previous.projectId}, expected ${repository}/${projectId}`);
            }
            if (previous.reviewer.username !== username) {
                throw new Error(`Ledger ${output} belongs to reviewer ${previous.reviewer.username}, expected ${username}`);
            }
            return { username, output, previous };
        });
        if (new Set(targets.map((target) => target.output)).size !== targets.length) {
            throw new Error('Two reviewers resolve to the same ledger path');
        }

        const runFor = (target, reviewer, extra = {}) => ({
            id: runId,
            startedAt,
            repository,
            projectId,
            username: target.username,
            userId: reviewer?.id ?? null,
            reviewer: reviewer ?? undefined,
            since,
            until,
            ...extra,
        });
        const writeAll = (snapshot, extra = {}) => {
            for (const target of targets) {
                const slice = snapshot.byUser?.[target.username] ?? { candidates: [], exclusions: [], failures: snapshot.failures ?? [] };
                const run = runFor(target, target.reviewer, extra);
                writeLedgerAtomic(target.output, mergeLedger(readLedger(target.output) ?? target.previous, slice, run, { partial: extra.partial === true }));
            }
        };

        let latestSnapshot = { processed: 0, total: 0, candidates: [], exclusions: [], failures: [], byUser: {} };
        const api = createGlabApi();
        try {
            for (const target of targets) {
                target.reviewer = await resolveReviewer(api, { username: target.username, expectedId: expectedIdFor(target.username) });
                print(`${repository}: reviewer ${target.reviewer.username} (${target.reviewer.id}) -> ${target.output}`);
            }
            latestSnapshot = await collectHumanReviews({
                api,
                projectId,
                repository,
                users: targets.map((target) => target.reviewer),
                since,
                until,
                concurrency,
                runId,
                onProgress: async (progress) => {
                    print(`${repository}: processed ${progress.processed}/${progress.total} merge requests, ${progress.candidates} candidates, ${progress.exclusions} exclusions, ${progress.failures} failures`);
                },
                onCheckpoint: async (snapshot) => {
                    latestSnapshot = snapshot;
                    writeAll(snapshot, { partial: true });
                    if (snapshot.processed % 50 === 0) {
                        print(`${repository}: checkpoint saved after ${snapshot.processed} merge requests`);
                    }
                },
            });
            const status = latestSnapshot.failures.length ? 'incomplete' : 'complete';
            writeAll(latestSnapshot, { completedAt: new Date().toISOString(), status });
            print(`${repository}: since ${since} through ${until}`);
            print(`  discovered ${latestSnapshot.mergeRequestsDiscovered} merge requests, processed ${latestSnapshot.mergeRequestsProcessed}`);
            for (const target of targets) {
                const slice = latestSnapshot.byUser[target.username];
                print(`  ${target.username}: ${slice.candidates.length} candidates, ${slice.exclusions.length} exclusions -> ${target.output}`);
            }
            print(`  ${latestSnapshot.failures.length} failures`);
            if (latestSnapshot.failures.length) {
                for (const failure of latestSnapshot.failures) printError(`  incomplete: ${failure.kind} ${failure.endpoint}: ${failure.message}`);
                process.exitCode = 1;
            }
        } catch (error) {
            const failure = {
                kind: 'fatal',
                endpoint: error.endpoint ?? null,
                message: error.message,
                attempts: error.attempts ?? null,
            };
            latestSnapshot.failures = [...(latestSnapshot.failures ?? []), failure];
            for (const slice of Object.values(latestSnapshot.byUser ?? {})) slice.failures = latestSnapshot.failures;
            writeAll(latestSnapshot, { completedAt: new Date().toISOString(), status: 'incomplete' });
            printError(`Human review harvest incomplete: ${error.message}`);
            process.exitCode = 1;
        }
    } catch (error) {
        printError(`Human review harvest failed: ${error.message}`);
        process.exitCode = 1;
    }
}
