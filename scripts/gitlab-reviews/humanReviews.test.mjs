import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
    collectHumanReviews,
    createGlabApi,
    discussionContentHash,
    emptyLedger,
    ledgerPathFor,
    mergeLedger,
    processOnlyReason,
    readLedger,
    resolveAuthors,
    resolveReviewer,
    writeLedgerAtomic,
} from './humanReviewsLib.mjs';

// Fixture reviewer. The library has no built-in identity, so tests carry their own.
const REVIEWER_ID = 4242;
const user = { id: REVIEWER_ID, username: 'reviewer', name: 'Reviewer One' };
const projectId = '1234567';

const mr = (iid, title = `MR ${iid}`) => ({
    iid,
    project_id: projectId,
    title,
    state: 'merged',
    web_url: `https://gitlab.example/mr/${iid}`,
    updated_at: '2026-09-10T10:00:00Z',
    diff_refs: { base_sha: `base-${iid}`, head_sha: `head-${iid}` },
});

const note = (id, authorId, body, createdAt, extra = {}) => ({
    id,
    author: { id: authorId, username: authorId === REVIEWER_ID ? 'reviewer' : 'other' },
    body,
    created_at: createdAt,
    updated_at: createdAt,
    system: false,
    ...extra,
});

test('collects paginated substantive roots and preserves context, metadata, and exclusions', async () => {
    const calls = [];
    const api = async (endpoint) => {
        calls.push(endpoint);
        if (endpoint === 'users?username=reviewer') return [{ id: REVIEWER_ID, username: 'reviewer', name: 'Reviewer One' }];
        if (endpoint.includes('/merge_requests?')) {
            const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
            if (page === '1') return [mr(1), mr(2)];
            if (page === '2') return [mr(3)];
            return [];
        }
        const match = endpoint.match(/merge_requests\/(\d+)\/discussions/);
        assert.ok(match, `unexpected endpoint ${endpoint}`);
        const iid = Number(match[1]);
        const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
        if (page !== '1') return [];
        if (iid === 1) {
            return [{
                id: 'discussion-1',
                individual_note: false,
                notes: [
                    note(101, REVIEWER_ID, 'Please move this validation into the page object.', '2026-06-01T12:00:00Z', { position: { new_line: 12, new_path: 'playwright/tests/a.spec.ts' } }),
                    note(102, 7, 'Thanks, fixed.', '2026-06-01T13:00:00Z'),
                ],
            }];
        }
        if (iid === 2) {
            return [{
                id: 'discussion-2',
                notes: [
                    note(201, 7, 'Please change this.', '2026-06-02T12:00:00Z'),
                    note(202, REVIEWER_ID, 'I agree with this thread.', '2026-06-02T13:00:00Z'),
                ],
            }];
        }
        return [{
            id: 'discussion-3',
            notes: [note(301, REVIEWER_ID, 'approving CO changes', '2026-06-03T12:00:00Z')],
        }];
    };

    const progress = [];
    const checkpoints = [];
    const result = await collectHumanReviews({
        api,
        projectId,
        repository: 'example-repo',
        user,
        since: '2026-03-11',
        until: '2026-09-11',
        perPage: 2,
        concurrency: 2,
        checkpointEvery: 2,
        onProgress: (value) => progress.push(value),
        onCheckpoint: (value) => checkpoints.push(value),
    });

    assert.equal(result.mergeRequestsDiscovered, 3);
    assert.equal(result.mergeRequestsProcessed, 3);
    assert.equal(result.candidates.length, 1);
    assert.equal(result.candidates[0].id, `${projectId}:101`);
    assert.equal(result.candidates[0].discussion.notes.length, 2);
    assert.equal(result.candidates[0].mrUrl, 'https://gitlab.example/mr/1');
    assert.deepEqual(result.candidates[0].diffRefs, { base_sha: 'base-1', head_sha: 'head-1' });
    assert.equal(result.candidates[0].position.new_path, 'playwright/tests/a.spec.ts');
    assert.ok(result.exclusions.some((entry) => entry.noteId === '202' && entry.reason === 'reply-not-root'));
    assert.ok(result.exclusions.some((entry) => entry.noteId === '301' && entry.reason.includes('process-only')));
    assert.equal(result.failures.length, 0);
    assert.equal(progress.at(-1).processed, 3);
    assert.equal(checkpoints.length, 2);
    assert.ok(calls.some((endpoint) => endpoint.includes('updated_after=2026-03-11')));
});

test('retries a failed discussion page and reports incomplete coverage', async () => {
    let attempts = 0;
    const api = async (endpoint) => {
        if (endpoint.includes('/merge_requests?')) return [mr(10)];
        if (endpoint.includes('/discussions')) {
            attempts += 1;
            throw new Error('temporary GitLab failure');
        }
        throw new Error(`unexpected ${endpoint}`);
    };
    const result = await collectHumanReviews({ api, projectId, user, perPage: 2, retries: 2, retryDelays: [0] });
    assert.equal(attempts, 3);
    assert.equal(result.complete, false);
    assert.equal(result.failures.length, 1);
    assert.equal(result.failures[0].attempts, 3);
    assert.equal(result.failures[0].mr, 10);
});

test('writes a checkpoint before a later discussion request resolves', async () => {
    let resolveSecond;
    let secondStartedResolve;
    const secondStarted = new Promise((resolve) => {
        secondStartedResolve = resolve;
    });
    const api = async (endpoint) => {
        if (endpoint.includes('/merge_requests?')) {
            const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
            return page === '1' ? [mr(20), mr(21)] : [];
        }
        if (endpoint.includes('/merge_requests/20/discussions')) return [{ id: 'd20', notes: [note(620, REVIEWER_ID, 'first', '2026-06-01T12:00:00Z')] }];
        if (endpoint.includes('/merge_requests/21/discussions')) {
            secondStartedResolve();
            return new Promise((resolve) => {
                resolveSecond = () => resolve([]);
            });
        }
        throw new Error(`unexpected ${endpoint}`);
    };
    const checkpoints = [];
    const scan = collectHumanReviews({
        api,
        projectId,
        user,
        perPage: 2,
        concurrency: 1,
        checkpointEvery: 1,
        onCheckpoint: (snapshot) => checkpoints.push(snapshot.processed),
    });
    await secondStarted;
    assert.deepEqual(checkpoints, [1]);
    resolveSecond();
    await scan;
    assert.deepEqual(checkpoints, [1, 2]);
});

test('content changes mark reviewed entries for recheck and preserve verdict metadata', () => {
    const run = { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID, id: 'run-1' };
    const context = { discussionId: 'd1', individualNote: true, notes: [note(501, REVIEWER_ID, 'old body', '2026-06-01T12:00:00Z')] };
    const oldCandidate = {
        id: `${projectId}:501`,
        noteId: '501',
        projectId,
        contentHash: discussionContentHash(context),
        discussion: context,
        body: 'old body',
        status: 'pending',
    };
    let ledger = mergeLedger(null, { candidates: [oldCandidate], exclusions: [], total: 1, processed: 1, failures: [] }, run);
    ledger.entries[0].status = 'applied';
    ledger.entries[0].reviewedAt = '2026-06-02T12:00:00Z';
    ledger.entries[0].reviewNote = 'verified in source';
    const changedContext = { ...context, notes: [note(501, REVIEWER_ID, 'new body', '2026-06-01T12:00:00Z')] };
    ledger = mergeLedger(ledger, {
        candidates: [{ ...oldCandidate, body: 'new body', discussion: changedContext, contentHash: discussionContentHash(changedContext) }],
        exclusions: [],
        total: 1,
        processed: 1,
        failures: [],
    }, { ...run, id: 'run-2' });
    assert.equal(ledger.entries[0].status, 'needs-recheck');
    assert.equal(ledger.entries[0].previousVerdict, 'applied');
    assert.equal(ledger.entries[0].reviewNote, 'verified in source');
    assert.equal(ledger.entries[0].reviewedAt, '2026-06-02T12:00:00Z');
});

test('moves a process-only root out of the active candidate queue', () => {
    const run = { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID, id: 'run-1' };
    const candidate = { id: `${projectId}:601`, noteId: '601', contentHash: 'a', status: 'pending', body: 'review' };
    const ledger = mergeLedger(null, { candidates: [candidate], exclusions: [], total: 1, processed: 1, failures: [] }, run);
    const next = mergeLedger(ledger, {
        candidates: [],
        exclusions: [{ id: `${projectId}:601`, noteId: '601', reason: 'process-only approval or acknowledgement' }],
        total: 1,
        processed: 1,
        failures: [],
    }, { ...run, id: 'run-2' });
    assert.equal(next.entries[0].active, false);
    assert.match(next.entries[0].excludedReason, /process-only/);
    ledger.entries[0].status = 'applied';
    const revised = mergeLedger(ledger, {
        candidates: [], exclusions: [{ id: candidate.id, noteId: '601', reason: 'process-only', body: 'approved' }],
    }, { ...run, id: 'run-3' });
    assert.equal(revised.entries[0].status, 'needs-recheck');
    assert.equal(revised.entries[0].previousVerdict, 'applied');
});

test('a corrective reply reopens a reviewed learning without changing its root text', () => {
    const run = { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID };
    const discussion = { notes: [note(901, REVIEWER_ID, 'Use this cache.', '2026-06-01T00:00:00Z')] };
    const entry = { id: `${projectId}:901`, noteId: '901', body: 'Use this cache.', discussion, contentHash: discussionContentHash(discussion), status: 'applied' };
    const ledger = mergeLedger(null, { candidates: [entry] }, run);
    const revisedDiscussion = { notes: [...discussion.notes, note(902, 7, 'That cache contains an unsaved draft.', '2026-06-02T00:00:00Z')] };
    const next = mergeLedger(ledger, { candidates: [{ ...entry, discussion: revisedDiscussion, contentHash: discussionContentHash(revisedDiscussion) }] }, run);
    assert.equal(next.entries[0].body, entry.body);
    assert.equal(next.entries[0].status, 'needs-recheck');
});

test('glab API uses execFile with a GET request and parses JSON', async () => {
    let invocation;
    const api = createGlabApi({
        execFileFn: (file, args, options, callback) => {
            invocation = { file, args, options };
            callback(null, { stdout: '[{"id":1}]', stderr: '' });
        },
    });
    assert.deepEqual(await api('users?username=reviewer'), [{ id: 1 }]);
    assert.deepEqual(invocation.args, ['api', '--method', 'GET', 'users?username=reviewer']);
    assert.equal(invocation.file, 'glab');
});

test('reviewer resolution verifies the expected GitLab id', async () => {
    const options = { username: 'reviewer', expectedId: REVIEWER_ID };
    const reviewer = await resolveReviewer(async () => [{ id: REVIEWER_ID, username: 'reviewer' }], options);
    assert.equal(reviewer.id, REVIEWER_ID);
    await assert.rejects(
        () => resolveReviewer(async () => [{ id: 12, username: 'reviewer' }], options),
        new RegExp(`expected ${REVIEWER_ID}`),
    );
});

test('process-only filtering remains conservative for substantive text', () => {
    assert.match(processOnlyReason('Accepting CO changes'), /process-only/);
    assert.match(processOnlyReason('approving CO changes'), /process-only/);
    assert.equal(processOnlyReason('Accepting CO changes because the new assertion is correct.'), null);
    assert.match(processOnlyReason('requested changes'), /process-only/);
    assert.match(processOnlyReason('Can you please rebase this branch?'), /process-only/);
    assert.equal(processOnlyReason('Please rebase this cache on server data.'), null);
    assert.match(processOnlyReason('`@coderabbitai review`'), /process-only/);
    assert.match(processOnlyReason('CO approval only'), /process-only/);
    assert.equal(processOnlyReason('@coderabbitai review. The cache key is missing projectId.'), null);
});

test('ledger writes are atomic and malformed stores fail loudly', () => {
    const directory = mkdtempSync(join(tmpdir(), 'human-reviews-'));
    const file = join(directory, 'ledger.json');
    const ledger = emptyLedger({ repository: 'example-repo', projectId, user: 'reviewer', userId: REVIEWER_ID });
    writeLedgerAtomic(file, ledger);
    assert.deepEqual(readLedger(file), ledger);
    writeFileSync(file, '{bad json');
    assert.throws(() => readLedger(file), /Cannot read human review ledger/);
});

test('review CLI filters by status and records a local verdict without GitLab writes', () => {
    const directory = mkdtempSync(join(tmpdir(), 'human-review-cli-'));
    const file = join(directory, 'ledger.json');
    const ledger = emptyLedger({ repository: 'example-repo', projectId, user: 'reviewer', userId: REVIEWER_ID });
    ledger.entries.push({ id: `${projectId}:701`, noteId: '701', mr: 70, status: 'pending', active: true, body: 'review body' });
    writeLedgerAtomic(file, ledger);
    const environment = { ...process.env, HR_OUT: file };
    // Resolve beside this file so the suite runs from any working directory.
    const script = fileURLToPath(new URL('./reviewHumanReviews.mjs', import.meta.url));
    const listing = spawnSync(process.execPath, [script, '--status', 'pending'], { cwd: process.cwd(), env: environment, encoding: 'utf8' });
    assert.equal(listing.status, 0, listing.stderr);
    assert.match(listing.stdout, /Entries: 1\/1/);
    const verdict = spawnSync(process.execPath, [script, '--set', `${projectId}:701`, 'applied', 'verified'], { cwd: process.cwd(), env: environment, encoding: 'utf8' });
    assert.equal(verdict.status, 0, verdict.stderr);
    assert.match(verdict.stdout, /-> applied/);
    assert.equal(readLedger(file).entries[0].status, 'applied');
    const invalid = spawnSync(process.execPath, [script, '--status'], { env: environment, encoding: 'utf8' });
    assert.equal(invalid.status, 1);
    const missingReason = spawnSync(process.execPath, [script, '--set', `${projectId}:701`, 'rejected'], { env: environment, encoding: 'utf8' });
    assert.equal(missingReason.status, 1);
    assert.equal(readLedger(file).entries[0].status, 'applied');
});

test('discussion pagination includes boundary roots and excludes replies, system notes, and older roots', async () => {
    const make = (id, date, extra = {}) => ({ id: `d${id}`, notes: [note(id, REVIEWER_ID, 'Check the failure state.', date, extra)] });
    const pages = [
        [make(801, '2026-03-11T00:00:00Z'), make(802, '2026-09-11T07:00:00Z')],
        [make(803, '2026-03-10T23:59:59Z'), make(804, '2026-09-11T07:00:01Z')],
        [make(805, '2026-06-01T00:00:00Z', { system: true }), {
            id: 'old-root-new-reply', notes: [
                note(806, REVIEWER_ID, 'Old root.', '2026-03-10T00:00:00Z'),
                note(807, REVIEWER_ID, 'New reply.', '2026-06-01T00:00:00Z'),
            ],
        }],
        [make(801, '2026-03-11T00:00:00Z')],
    ];
    const result = await collectHumanReviews({
        api: async (endpoint) => endpoint.includes('/merge_requests?') ? [mr(80)] : pages[Number(new URLSearchParams(endpoint.split('?')[1]).get('page')) - 1],
        user, perPage: 2, since: '2026-03-11', until: '2026-09-11T07:00:00Z',
    });
    const run = { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID };
    const ledger = mergeLedger(null, result, run);
    assert.deepEqual(ledger.entries.map((entry) => entry.noteId), ['801', '802']);
    assert.deepEqual(new Set(ledger.exclusions.map((entry) => entry.noteId)), new Set(['803', '804', '805', '806', '807']));
    ledger.entries[0].status = 'applied';
    const repeated = mergeLedger(ledger, result, run);
    assert.equal(repeated.entries.length, 2);
    assert.equal(repeated.entries[0].status, 'applied');
});

test('MR listing failure retains partial evidence and records the failed endpoint', async () => {
    const result = await collectHumanReviews({
        api: async (endpoint) => {
            if (endpoint.includes('/merge_requests?')) {
                if (endpoint.endsWith('page=1')) return [mr(90), mr(91)];
                throw new Error('listing unavailable');
            }
            return [];
        }, user, perPage: 2, retries: 0,
    });
    const ledger = mergeLedger(null, result, { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID });
    assert.equal(result.complete, false);
    assert.equal(ledger.lastRun.mergeRequestsProcessed, 2);
    assert.match(ledger.lastRun.failureDetails[0].endpoint, /page=2$/);
});

test('marks a comment on the reviewer own merge request as self-authored', async () => {
    const api = async (endpoint) => {
        if (endpoint === 'users?username=reviewer') return [user];
        if (endpoint.includes('/merge_requests?')) {
            const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
            if (page !== '1') return [];
            return [
                { ...mr(41), author: { id: REVIEWER_ID, username: 'reviewer' } },
                { ...mr(42), author: { id: 9, username: 'other' } },
            ];
        }
        const iid = Number(endpoint.match(/merge_requests\/(\d+)\/discussions/)[1]);
        const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
        if (page !== '1') return [];
        return [{ id: `d${iid}`, notes: [note(iid, REVIEWER_ID, 'Hoist this helper to module scope.', '2026-06-01T12:00:00Z')] }];
    };

    const result = await collectHumanReviews({ api, user, since: '2026-03-11', until: '2026-09-11', concurrency: 1 });
    const byMr = new Map(result.candidates.map((candidate) => [candidate.mr, candidate]));
    assert.equal(byMr.get(41).selfAuthored, true);
    assert.equal(byMr.get(41).mergeRequest.author.username, 'reviewer');
    assert.equal(byMr.get(42).selfAuthored, false);
    assert.equal(byMr.get(42).mergeRequest.author.username, 'other');
});

test('a later run refreshes self-authored without overwriting a recorded verdict', () => {
    const run = { repository: 'example-repo', projectId, username: 'reviewer', userId: REVIEWER_ID, id: 'run-1' };
    const discussion = { discussionId: 'd50', individualNote: true, notes: [note(50, REVIEWER_ID, 'Hoist this helper.', '2026-06-01T12:00:00Z')] };
    const candidate = {
        id: `${projectId}:50`,
        noteId: '50',
        body: 'Hoist this helper.',
        discussion,
        contentHash: discussionContentHash(discussion),
        selfAuthored: false,
        status: 'pending',
    };
    const first = mergeLedger(null, { candidates: [candidate], exclusions: [] }, run);
    first.entries[0].status = 'applied';
    const second = mergeLedger(first, { candidates: [{ ...candidate, selfAuthored: true }], exclusions: [] }, { ...run, id: 'run-2' });
    assert.equal(second.entries[0].selfAuthored, true);
    assert.equal(second.entries[0].status, 'applied');
});

test('one scan serves several reviewers and keeps their candidates apart', async () => {
    const second = { id: 77, username: 'reviewer-two', name: 'Reviewer Two' };
    const endpoints = [];
    const api = async (endpoint) => {
        endpoints.push(endpoint);
        if (endpoint.includes('/merge_requests?')) {
            const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
            return page === '1' ? [{ ...mr(61), author: { id: 9, username: 'other' } }] : [];
        }
        const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
        if (page !== '1') return [];
        return [
            { id: 'd1', notes: [note(61, REVIEWER_ID, 'Hoist this helper to module scope.', '2026-06-01T12:00:00Z')] },
            { id: 'd2', notes: [note(62, second.id, 'Use TanStack Query here rather than a new slice.', '2026-06-01T12:00:00Z')] },
            { id: 'd3', notes: [note(63, 9, 'A third party comment.', '2026-06-01T12:00:00Z')] },
        ];
    };

    const result = await collectHumanReviews({ api, users: [user, second], since: '2026-03-11', until: '2026-09-11', concurrency: 1 });

    assert.equal(endpoints.filter((endpoint) => endpoint.includes('/discussions')).length, 1);
    assert.deepEqual(result.byUser['reviewer'].candidates.map((candidate) => candidate.noteId), ['61']);
    assert.deepEqual(result.byUser['reviewer-two'].candidates.map((candidate) => candidate.noteId), ['62']);
    assert.equal(result.byUser['reviewer'].mergeRequestsProcessed, 1);
    assert.equal(result.byUser['reviewer-two'].mergeRequestsProcessed, 1);
    assert.equal(result.candidates.length, 2);
});

test('a per-reviewer slice builds a ledger holding only that reviewer', () => {
    const second = { id: 77, username: 'reviewer-two', name: 'Reviewer Two' };
    const slice = {
        candidates: [{ id: '1234567:70', noteId: '70', body: 'Use a discriminated union.', status: 'pending' }],
        exclusions: [],
        total: 1,
        processed: 1,
    };
    const ledger = mergeLedger(null, slice, {
        repository: 'example-repo',
        projectId,
        username: second.username,
        userId: second.id,
        id: 'run-1',
        status: 'complete',
    });
    assert.equal(ledger.reviewer.username, 'reviewer-two');
    assert.equal(ledger.entries.length, 1);
    assert.equal(ledger.lastRun.mergeRequestsProcessed, 1);
});

test('a ledger path is derived from the repository and reviewer', () => {
    assert.equal(ledgerPathFor('example-repo', 'reviewer-two'), 'tools-local/human-reviews/example-repo-reviewer-two.json');
    assert.equal(ledgerPathFor('other-repo', 'reviewer.three'), 'tools-local/human-reviews/other-repo-reviewer.three.json');
});

test('sign-off filtering covers test confirmations, codeowner scope, and bare praise', () => {
    for (const body of [
        'tested by dev :white_check_mark:',
        'retested :white_check_mark:',
        'tested by me',
        'approving CO part',
        'approving codeowners changes',
        'Nice work with mocks refactor! :100:',
        'done :white_check_mark:',
    ]) {
        assert.equal(processOnlyReason(body), 'process-only approval or acknowledgement', body);
    }
});

test('a sign-off that carries a finding stays a candidate', () => {
    for (const body of [
        'tested by me, but the counter still shows 0',
        'Nice catch, but this drops the is_not criteria and we need to check the scale',
        'approving CO part, though the migration still needs a rerun before merge',
        'dead module, imo drop',
        'links working correctly',
    ]) {
        assert.equal(processOnlyReason(body), null, body);
    }
});

test('a dev-tested sign-off with a verdict is filtered, one with a finding is not', () => {
    for (const body of [
        'Dev tested - correct!',
        'dev tested by me, web: correct mobile: correct',
        'Tested by me, correct',
        'Dev tested by me - correct!',
    ]) {
        assert.equal(processOnlyReason(body), 'process-only approval or acknowledgement', body);
    }
    for (const body of [
        'tested by me, but the counter still shows 0',
        'dev tested, the toast never appears on Android',
    ]) {
        assert.equal(processOnlyReason(body), null, body);
    }
});

test('scope approvals and a leading tick are sign-offs; the same text with a finding is not', () => {
    for (const body of [
        ':white_check_mark: tested by me',
        ':white_check_mark: Tested by dev',
        'Approved CO part',
        'approve shared part',
        'reviewed CO changes',
        '@coderabbitai review full',
    ]) {
        assert.equal(processOnlyReason(body), 'process-only approval or acknowledgement', body);
    }
    for (const body of [
        'Approved the shared part but the toast still fires twice',
        'Approved CO part, though the migration still needs a rerun',
    ]) {
        assert.equal(processOnlyReason(body), null, body);
    }
});

test('discovery collects every thread opener and buckets them by author', async () => {
    const api = async (endpoint) => {
        if (endpoint.includes('/merge_requests?')) {
            const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
            return page === '1' ? [{ ...mr(71), author: { id: 9, username: 'author' } }] : [];
        }
        const page = new URLSearchParams(endpoint.split('?')[1]).get('page');
        if (page !== '1') return [];
        return [
            { id: 'd1', notes: [note(71, REVIEWER_ID, 'Hoist this helper to module scope.', '2026-06-01T12:00:00Z')] },
            { id: 'd2', notes: [note(72, 77, 'Use a discriminated union here.', '2026-06-01T12:00:00Z')] },
            { id: 'd3', notes: [{ ...note(73, 500, 'system thing', '2026-06-01T12:00:00Z'), system: true }] },
        ];
    };

    const result = await collectHumanReviews({
        api,
        projectId,
        discoverReviewers: true,
        since: '2026-03-11',
        until: '2026-09-11',
        concurrency: 1,
    });

    assert.deepEqual(Object.keys(result.byUser).sort(), ['other', 'reviewer']);
    assert.equal(result.byUser.reviewer.candidates[0].noteId, '71');
    assert.equal(result.byUser.other.candidates[0].noteId, '72');
    assert.equal(result.candidates.length, 2);
});

test('discovery needs no reviewer list, a named run still does', async () => {
    const api = async () => [];
    await collectHumanReviews({ api, projectId, discoverReviewers: true, since: '2026-03-11', until: '2026-09-11' });
    await assert.rejects(
        () => collectHumanReviews({ api, projectId, since: '2026-03-11', until: '2026-09-11' }),
        /requires a resolved reviewer/,
    );
});

test('author resolution flags bots and keeps an unreadable account', async () => {
    const api = async (endpoint) => {
        if (endpoint === 'users/1') return { id: 1, username: 'a-bot', bot: true };
        if (endpoint === 'users/2') return { id: 2, username: 'a-human', bot: false };
        throw new Error('404 Not Found');
    };
    const resolved = await resolveAuthors(api, [1, 2, 3], { retries: 0, retryDelays: [] });
    assert.equal(resolved.get('1').bot, true);
    assert.equal(resolved.get('2').bot, false);
    assert.equal(resolved.get('3').unresolved, true);
    assert.equal(resolved.get('3').bot, false);
});
