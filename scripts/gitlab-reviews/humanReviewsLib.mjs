import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname } from 'node:path';
import { promisify } from 'node:util';

// This repository is public, so no reviewer, project or window is named here. The
// defaults come from a config file outside the checkout; HR_* variables override it.
// Every value is optional: without one, the CLI asks for the variable it needs.
export const CONFIG_FILE = process.env.HR_CONFIG ?? `${homedir()}/.config/gitlab-reviews/config.json`;
const CONFIG = (() => {
    try {
        return JSON.parse(readFileSync(CONFIG_FILE, 'utf8'));
    } catch {
        return {};
    }
})();

export const DEFAULT_REPOSITORY = CONFIG.repository ?? '';
export const DEFAULT_PROJECT_ID = CONFIG.projectId == null ? '' : String(CONFIG.projectId);
export const DEFAULT_USER = CONFIG.user ?? '';
export const DEFAULT_USER_ID = CONFIG.userId;
export const DEFAULT_SINCE = CONFIG.since ?? '1970-01-01';
export const LEDGER_DIR = CONFIG.ledgerDir ?? 'tools-local/human-reviews';
// Every reviewer, including the first one, is addressed the same way.
export const DEFAULT_OUTPUT = `${LEDGER_DIR}/${DEFAULT_REPOSITORY}-${DEFAULT_USER}.json`;
export const PER_PAGE = 100;
export const DEFAULT_CONCURRENCY = 4;
export const DEFAULT_RETRIES = 2;
export const REVIEWED_STATUSES = new Set(['applied', 'rejected', 'stale', 'superseded']);
export const OPEN_STATUSES = new Set(['pending', 'needs-recheck']);

const DEFAULT_RETRY_DELAYS = [250, 750];
// Patterns live in processOnlyPatterns.json so adding a reviewer's vocabulary is a data edit.
const patternFile = new URL('./processOnlyPatterns.json', import.meta.url);
const PATTERN_DATA = JSON.parse(readFileSync(patternFile, 'utf8'));
const PROCESS_ONLY_PATTERNS = PATTERN_DATA.patterns.map((source) => new RegExp(source, 'i'));
// A message an integration delivered into the thread is not a review at all, so it earns
// its own reason rather than being filed as an approval.
const NON_REVIEW_PATTERNS = (PATTERN_DATA.nonReviewPatterns ?? []).map(
    (source) => new RegExp(source, 'i'),
);

// A sign-off often ends in an emoji shortcode or punctuation. Strip those before matching,
// so `done :white_check_mark:` and `done` reach the same pattern.
const stripSignOffDecoration = (value) => {
    let text = value;
    let previous;
    do {
        previous = text;
        text = text
            .replace(/(?::[a-z0-9_+-]+:|[\u{1F300}-\u{1FAFF}\u{2700}-\u{27BF}\u{2600}-\u{26FF}\u{FE0F}])\s*$/iu, '')
            .replace(/[\s.!,;)\-]+$/u, '')
            // Some reviewers lead with the tick instead of trailing it.
            .replace(/^\s*(?::[a-z0-9_+-]+:|[\u{1F300}-\u{1FAFF}\u{2700}-\u{27BF}\u{2600}-\u{26FF}\u{FE0F}])\s*/iu, '')
            // A sign-off often links its evidence; the link is not the finding.
            .replace(/\s*(?:<)?https?:\/\/\S+(?:>)?\s*$/u, '')
            // A bolded sign-off is still a sign-off.
            .replace(/^\s*([*_]{1,2})([\s\S]*)\1\s*$/u, '$2')
            .trim();
    } while (text !== previous);
    return text;
};

const asText = (value) => (value == null ? '' : String(value));

const errorText = (error) => {
    const message = error instanceof Error ? error.message : asText(error);
    return message.replace(/\s+/g, ' ').trim().slice(0, 1000);
};

const sleep = (milliseconds) =>
    milliseconds > 0 ? new Promise((resolve) => setTimeout(resolve, milliseconds)) : Promise.resolve();

const parseDate = (value, endOfDay = false) => {
    const raw = asText(value).trim();
    if (!raw) return NaN;
    const normalized = endOfDay && /^\d{4}-\d{2}-\d{2}$/.test(raw) ? `${raw}T23:59:59.999Z` : raw;
    return Date.parse(normalized);
};

export const dateInWindow = (value, since, until) => {
    const timestamp = Date.parse(asText(value));
    return !Number.isNaN(timestamp) && timestamp >= parseDate(since) && timestamp <= parseDate(until, true);
};

export const validateWindow = (since, until) => {
    if (Number.isNaN(parseDate(since))) throw new Error(`Invalid HR_SINCE date: ${since}`);
    if (Number.isNaN(parseDate(until, true))) throw new Error(`Invalid HR_UNTIL date: ${until}`);
    if (parseDate(since) > parseDate(until, true)) {
        throw new Error(`HR_SINCE must be before HR_UNTIL: ${since} > ${until}`);
    }
};

export const createGlabApi = ({ execFileFn = execFile } = {}) => {
    const run = promisify(execFileFn);
    return async (endpoint) => {
        const result = await run('glab', ['api', '--method', 'GET', endpoint], {
            encoding: 'utf8',
            maxBuffer: 1 << 28,
            timeout: 120_000,
        });
        const stdout = typeof result === 'string' ? result : result.stdout;
        try {
            return JSON.parse(stdout);
        } catch (error) {
            throw new Error(`Invalid JSON from glab for ${endpoint}: ${errorText(error)}`);
        }
    };
};

export const callWithRetry = async (
    api,
    endpoint,
    { retries = DEFAULT_RETRIES, retryDelays = DEFAULT_RETRY_DELAYS } = {},
) => {
    let lastError;
    for (let attempt = 0; attempt <= retries; attempt += 1) {
        try {
            return await api(endpoint);
        } catch (error) {
            lastError = error;
            if (attempt === retries) break;
            await sleep(retryDelays[attempt] ?? retryDelays.at(-1) ?? 0);
        }
    }
    const failure = new Error(`GitLab request failed after ${retries + 1} attempts: ${endpoint}: ${errorText(lastError)}`);
    failure.endpoint = endpoint;
    failure.attempts = retries + 1;
    failure.cause = lastError;
    throw failure;
};

export const resolveReviewer = async (
    api,
    { username = DEFAULT_USER, expectedId = username === DEFAULT_USER ? DEFAULT_USER_ID : undefined, ...retryOptions } = {},
) => {
    const endpoint = `users?username=${encodeURIComponent(username)}`;
    const users = await callWithRetry(api, endpoint, retryOptions);
    if (!Array.isArray(users)) throw new Error(`GitLab users response is not an array for ${username}`);
    const user = users.find((candidate) => asText(candidate.username).toLowerCase() === username.toLowerCase());
    if (!user || user.id == null) throw new Error(`GitLab user not found: ${username}`);
    const id = Number(user.id);
    if (!Number.isInteger(id)) throw new Error(`GitLab user ${username} has an invalid id: ${user.id}`);
    if (expectedId != null && id !== Number(expectedId)) {
        throw new Error(`GitLab user ${username} resolved to id ${id}, expected ${expectedId}`);
    }
    return { id, username: user.username, name: user.name ?? null, webUrl: user.web_url ?? null };
};

const getAuthorId = (note) => note.author?.id ?? note.author_id ?? null;
const noteId = (note) => (note.id == null ? null : String(note.id));

const canonicalize = (value) => {
    if (Array.isArray(value)) return value.map(canonicalize);
    if (value && typeof value === 'object') {
        return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
    }
    return value;
};

export const discussionContentHash = (discussion) =>
    createHash('sha256')
        .update(JSON.stringify(canonicalize(discussion)))
        .digest('hex');

const NON_REVIEW_REASON = 'automated message delivered into the thread, not a review';

export const processOnlyReason = (body) => {
    const compact = asText(body).trim().replace(/\s+/g, ' ');
    if (!compact) return null;
    // An automated post is recognised by how it opens, not by how short it is. A CI report
    // runs to hundreds of characters, so it is matched before the sign-off length cap.
    // Its patterns are prefix-anchored, which is why they can safely see a long body.
    if (NON_REVIEW_PATTERNS.some((candidate) => candidate.test(compact))) return NON_REVIEW_REASON;
    if (compact.length > 160) return null;
    const bare = stripSignOffDecoration(compact);
    if (!bare) return 'process-only approval or acknowledgement';
    const matches = (list) => list.find((candidate) => candidate.test(compact) || candidate.test(bare));
    if (matches(NON_REVIEW_PATTERNS)) return NON_REVIEW_REASON;
    return matches(PROCESS_ONLY_PATTERNS) ? 'process-only approval or acknowledgement' : null;
};

const normalizedNote = (note) => ({
    ...note,
    id: noteId(note),
    authorId: getAuthorId(note),
});

const sortActualNotes = (notes) =>
    notes
        .map((note, index) => ({ note, index }))
        .filter(({ note }) => note.system !== true)
        .sort((left, right) => {
            const leftDate = Date.parse(asText(left.note.created_at));
            const rightDate = Date.parse(asText(right.note.created_at));
            if (!Number.isNaN(leftDate) && !Number.isNaN(rightDate) && leftDate !== rightDate) return leftDate - rightDate;
            return left.index - right.index;
        })
        .map(({ note }) => note);

const mrMetadata = (mergeRequest) => ({
    iid: mergeRequest.iid,
    title: mergeRequest.title ?? null,
    author: mergeRequest.author ? { id: mergeRequest.author.id, username: mergeRequest.author.username } : null,
    state: mergeRequest.state ?? null,
    webUrl: mergeRequest.web_url ?? null,
    sourceBranch: mergeRequest.source_branch ?? null,
    targetBranch: mergeRequest.target_branch ?? null,
    updatedAt: mergeRequest.updated_at ?? null,
    diffRefs: mergeRequest.diff_refs ?? null,
});

const exclusionFor = (mergeRequest, discussion, note, reason, runId) => ({
    id: `${mergeRequest.project_id ?? ''}:${noteId(note)}`.replace(/^:/, ''),
    noteId: noteId(note),
    discussionId: discussion.id ?? null,
    repository: mergeRequest.repository ?? null,
    projectId: String(mergeRequest.project_id ?? ''),
    mr: mergeRequest.iid,
    mrUrl: mergeRequest.web_url ?? null,
    title: mergeRequest.title ?? null,
    reason,
    body: note.body ?? '',
    createdAt: note.created_at ?? null,
    author: note.author ?? null,
    position: note.position ?? null,
    diffRefs: mergeRequest.diff_refs ?? null,
    lastSeenRunId: runId,
});

const candidateFor = (mergeRequest, discussion, root, user, runId) => {
    const notes = (discussion.notes ?? []).map(normalizedNote);
    const context = {
        discussionId: discussion.id ?? null,
        individualNote: discussion.individual_note === true,
        notes,
    };
    return {
        id: `${mergeRequest.project_id}:${noteId(root)}`,
        noteId: noteId(root),
        discussionId: discussion.id ?? null,
        repository: mergeRequest.repository,
        projectId: String(mergeRequest.project_id),
        reviewer: { id: user.id, username: user.username },
        mr: mergeRequest.iid,
        mrUrl: mergeRequest.web_url ?? null,
        title: mergeRequest.title ?? null,
        mergeRequest: mrMetadata(mergeRequest),
        rootNote: normalizedNote(root),
        position: root.position ?? null,
        diffRefs: mergeRequest.diff_refs ?? null,
        discussion: context,
        body: root.body ?? '',
        createdAt: root.created_at ?? null,
        updatedAt: root.updated_at ?? null,
        selfAuthored: mergeRequest.author?.id != null && String(mergeRequest.author.id) === String(user.id),
        selectionReason: 'new-thread-root authored by reviewer',
        contentHash: discussionContentHash(context),
        status: 'pending',
        lastSeenRunId: runId,
    };
};

const inspectDiscussion = (mergeRequest, discussion, user, since, until, runId) => {
    const notes = Array.isArray(discussion.notes) ? discussion.notes : [];
    const actual = sortActualNotes(notes);
    const root = actual[0];
    if (!root) {
        return { candidate: null, exclusions: notes.filter((note) => String(getAuthorId(note)) === String(user.id)).map((note) => exclusionFor(mergeRequest, discussion, note, 'system-note', runId)) };
    }
    const exclusions = [];
    for (const note of notes) {
        if (String(getAuthorId(note)) !== String(user.id)) continue;
        const id = noteId(note);
        if (note.system === true) {
            exclusions.push(exclusionFor(mergeRequest, discussion, note, 'system-note', runId));
        } else if (id !== noteId(root)) {
            exclusions.push(exclusionFor(mergeRequest, discussion, note, 'reply-not-root', runId));
        } else if (!dateInWindow(note.created_at, since, until)) {
            exclusions.push(exclusionFor(mergeRequest, discussion, note, 'outside-requested-date-window', runId));
        } else {
            const processReason = processOnlyReason(note.body);
            if (processReason) exclusions.push(exclusionFor(mergeRequest, discussion, note, processReason, runId));
        }
    }
    const rootIsReviewer = String(getAuthorId(root)) === String(user.id);
    if (!rootIsReviewer || !dateInWindow(root.created_at, since, until) || processOnlyReason(root.body)) {
        return { candidate: null, exclusions };
    }
    return { candidate: candidateFor(mergeRequest, discussion, root, user, runId), exclusions };
};

const mapLimit = async (items, limit, worker) => {
    const results = new Array(items.length);
    let next = 0;
    const runWorker = async () => {
        while (true) {
            const index = next;
            next += 1;
            if (index >= items.length) return;
            results[index] = await worker(items[index], index);
        }
    };
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, runWorker));
    return results;
};

// A per-reviewer view of one shared scan. Coverage and failures are the scan's, so every reviewer sees the same numbers.
const snapshotByUser = (byUser, processed, total, failures, runId) =>
    Object.fromEntries(
        [...byUser.entries()].map(([username, bucket]) => [
            username,
            {
                runId,
                user: bucket.user,
                processed,
                total,
                mergeRequestsDiscovered: total,
                mergeRequestsProcessed: processed,
                candidates: [...bucket.candidates],
                exclusions: [...bucket.exclusions],
                failures: [...failures],
            },
        ]),
    );

// The first non-system note of a thread, as a reviewer record. Empty when there is none.
const openerAsReviewer = (discussion) => {
    const root = sortActualNotes(Array.isArray(discussion.notes) ? discussion.notes : [])[0];
    const author = root?.author;
    if (!author?.id || !author?.username || root.system === true) return [];
    return [{ id: author.id, username: author.username, name: author.name ?? null }];
};

const ensureArray = (value, label) => {
    if (!Array.isArray(value)) throw new Error(`GitLab ${label} response is not an array`);
    return value;
};

export const ledgerPathFor = (repository, username) => `${LEDGER_DIR}/${repository}-${username}.json`;

// GitLab's discussions payload carries no bot flag, so resolve each discovered author once.
export const resolveAuthors = async (api, ids, options = {}) => {
    const resolved = new Map();
    for (const id of ids) {
        try {
            const person = await callWithRetry(api, `users/${encodeURIComponent(id)}`, options);
            resolved.set(String(id), { id: person.id, username: person.username, bot: person.bot === true });
        } catch {
            // An unreadable account is kept, so a lookup failure never silently drops a reviewer.
            resolved.set(String(id), { id, username: null, bot: false, unresolved: true });
        }
    }
    return resolved;
};

export const collectHumanReviews = async ({
    api,
    projectId = DEFAULT_PROJECT_ID,
    repository = DEFAULT_REPOSITORY,
    user,
    users,
    discoverReviewers = false,
    since = DEFAULT_SINCE,
    until = new Date().toISOString(),
    concurrency = DEFAULT_CONCURRENCY,
    perPage = PER_PAGE,
    checkpointEvery = 50,
    retries = DEFAULT_RETRIES,
    retryDelays = DEFAULT_RETRY_DELAYS,
    runId = new Date().toISOString(),
    onProgress,
    onCheckpoint,
} = {}) => {
    if (typeof api !== 'function') throw new Error('collectHumanReviews requires an api function');
    const reviewers = users ?? (user ? [user] : []);
    if (!discoverReviewers && (!reviewers.length || reviewers.some((entry) => !entry?.id || !entry?.username))) {
        throw new Error('collectHumanReviews requires a resolved reviewer');
    }
    validateWindow(since, until);
    const requestOptions = { retries, retryDelays };
    const failures = [];
    const mergeRequests = [];
    let mrPage = 1;
    while (true) {
        const endpoint = `projects/${encodeURIComponent(projectId)}/merge_requests?state=all&updated_after=${encodeURIComponent(since)}&order_by=created_at&sort=asc&per_page=${perPage}&page=${mrPage}`;
        try {
            const batch = ensureArray(await callWithRetry(api, endpoint, requestOptions), 'merge requests');
            mergeRequests.push(...batch.map((mr) => ({ ...mr, project_id: projectId, repository })));
            if (batch.length < perPage) break;
            mrPage += 1;
        } catch (error) {
            failures.push({ kind: 'merge-request-page', endpoint, message: errorText(error), attempts: error.attempts ?? retries + 1 });
            break;
        }
    }
    const uniqueMergeRequests = [...new Map(mergeRequests.map((mergeRequest) => [String(mergeRequest.iid), mergeRequest])).values()];

    const candidates = [];
    const exclusions = [];
    // One scan serves every reviewer: each discussion is inspected once per reviewer.
    const byUser = new Map(reviewers.map((reviewer) => [reviewer.username, { user: reviewer, candidates: [], exclusions: [] }]));
    let processed = 0;
    await mapLimit(uniqueMergeRequests, Math.max(1, Number(concurrency) || DEFAULT_CONCURRENCY), async (mergeRequest) => {
        const discussions = [];
        const mrFailures = [];
        let page = 1;
        while (true) {
            const endpoint = `projects/${encodeURIComponent(projectId)}/merge_requests/${encodeURIComponent(mergeRequest.iid)}/discussions?per_page=${perPage}&page=${page}`;
            try {
                const batch = ensureArray(await callWithRetry(api, endpoint, requestOptions), 'discussions');
                discussions.push(...batch);
                if (batch.length < perPage) break;
                page += 1;
            } catch (error) {
                mrFailures.push({
                    kind: 'discussion-page',
                    endpoint,
                    mr: mergeRequest.iid,
                    message: errorText(error),
                    attempts: error.attempts ?? retries + 1,
                });
                break;
            }
        }
        failures.push(...mrFailures);
        for (const discussion of discussions) {
            // In discovery mode the thread's own opener is the reviewer, so every human is collected
            // in the same pass and the filtering decision moves to curation.
            const discussionReviewers = discoverReviewers ? openerAsReviewer(discussion) : reviewers;
            for (const reviewer of discussionReviewers) {
                if (discoverReviewers && !byUser.has(reviewer.username)) {
                    byUser.set(reviewer.username, { user: reviewer, candidates: [], exclusions: [] });
                }
                const inspected = inspectDiscussion(mergeRequest, discussion, reviewer, since, until, runId);
                const bucket = byUser.get(reviewer.username);
                if (inspected.candidate) {
                    candidates.push(inspected.candidate);
                    bucket.candidates.push(inspected.candidate);
                }
                exclusions.push(...inspected.exclusions);
                bucket.exclusions.push(...inspected.exclusions);
            }
        }
        processed += 1;
        if (onProgress && (processed % 25 === 0 || processed === uniqueMergeRequests.length)) {
            await onProgress({ processed, total: uniqueMergeRequests.length, candidates: candidates.length, exclusions: exclusions.length, failures: failures.length });
        }
        if (onCheckpoint && (processed % checkpointEvery === 0 || processed === uniqueMergeRequests.length)) {
            await onCheckpoint({
                runId,
                processed,
                total: uniqueMergeRequests.length,
                candidates: [...candidates],
                exclusions: [...exclusions],
                failures: [...failures],
                byUser: snapshotByUser(byUser, processed, uniqueMergeRequests.length, failures, runId),
            });
        }
    });

    return {
        repository,
        projectId: String(projectId),
        user: reviewers[0],
        users: reviewers,
        since,
        until,
        mergeRequestsDiscovered: uniqueMergeRequests.length,
        mergeRequestsProcessed: processed,
        candidates,
        exclusions,
        failures,
        byUser: snapshotByUser(byUser, processed, uniqueMergeRequests.length, failures, runId),
        complete: failures.length === 0 && processed === uniqueMergeRequests.length,
    };
};

export const emptyLedger = ({ repository = DEFAULT_REPOSITORY, projectId = DEFAULT_PROJECT_ID, user = DEFAULT_USER, userId = DEFAULT_USER_ID } = {}) => ({
    schemaVersion: 1,
    repository,
    projectId: String(projectId),
    reviewer: { username: user, id: Number(userId) },
    entries: [],
    exclusions: [],
    runs: [],
    lastRun: null,
});

const isLedger = (value) =>
    value && typeof value === 'object' && !Array.isArray(value) && value.schemaVersion === 1 && Array.isArray(value.entries) && Array.isArray(value.exclusions) && Array.isArray(value.runs);

export const readLedger = (file) => {
    let parsed;
    try {
        parsed = JSON.parse(readFileSync(file, 'utf8'));
    } catch (error) {
        if (error.code === 'ENOENT') return null;
        throw new Error(`Cannot read human review ledger ${file}: ${errorText(error)}`);
    }
    if (!isLedger(parsed)) throw new Error(`Malformed human review ledger ${file}: expected schemaVersion 1 with entries, exclusions, and runs arrays`);
    return parsed;
};

export const writeLedgerAtomic = (file, ledger) => {
    if (!isLedger(ledger)) throw new Error(`Refusing to write malformed human review ledger: ${file}`);
    mkdirSync(dirname(file), { recursive: true });
    const temporary = `${file}.${process.pid}.tmp`;
    writeFileSync(temporary, `${JSON.stringify(ledger, null, 2)}\n`, { mode: 0o600 });
    renameSync(temporary, file);
};

const mergeById = (previous, current, key) => {
    const currentById = new Map(current.map((entry) => [entry[key], entry]));
    const merged = [];
    for (const candidate of currentById.values()) {
        const old = previous.find((entry) => entry[key] === candidate[key]);
        merged.push(old ? { ...old, ...candidate } : candidate);
    }
    for (const old of previous) if (!currentById.has(old[key])) merged.push(old);
    return merged;
};

const mergeCandidates = (previous, current) => {
    const currentById = new Map(current.map((entry) => [entry.id, entry]));
    const merged = [...currentById.values()].map((candidate) => {
        const old = previous.find((entry) => entry.id === candidate.id);
        if (!old) return { ...candidate, active: true };
        const changed = old.contentHash !== candidate.contentHash;
        const result = {
            ...old,
            ...candidate,
            status: old.status ?? 'pending',
            active: true,
            reviewedAt: old.reviewedAt ?? null,
            reviewNote: old.reviewNote ?? old.note ?? null,
        };
        delete result.excludedReason;
        if (changed && REVIEWED_STATUSES.has(old.status)) {
            result.previousVerdict = old.status;
            result.status = 'needs-recheck';
            result.contentChanged = true;
        } else if (!changed) {
            delete result.contentChanged;
        }
        return result;
    });
    for (const old of previous) if (!currentById.has(old.id)) merged.push(old);
    return merged;
};

export const mergeLedger = (previous, snapshot, run, { partial = false } = {}) => {
    const base = previous ?? emptyLedger({ repository: run.repository, projectId: run.projectId, user: run.username, userId: run.userId });
    const currentCandidates = snapshot.candidates ?? [];
    const currentExclusions = new Map((snapshot.exclusions ?? []).map((entry) => [entry.noteId, entry]));
    const entries = mergeCandidates(base.entries, currentCandidates);
    for (const entry of entries) {
        const exclusion = currentExclusions.get(entry.noteId);
        if (exclusion && !currentCandidates.some((candidate) => candidate.id === entry.id)) {
            entry.active = false;
            entry.excludedReason = exclusion.reason;
            if (REVIEWED_STATUSES.has(entry.status) && exclusion.body != null && exclusion.body !== entry.body) {
                entry.previousVerdict = entry.status;
                entry.status = 'needs-recheck';
                entry.contentChanged = true;
            }
        }
    }
    const next = {
        ...base,
        schemaVersion: 1,
        repository: run.repository,
        projectId: String(run.projectId),
        reviewer: { username: run.username, id: Number(run.userId) },
        entries,
        exclusions: mergeById(base.exclusions, snapshot.exclusions ?? [], 'id'),
    };
    const recordedRun = {
        ...run,
        mergeRequestsDiscovered: snapshot.total ?? snapshot.mergeRequestsDiscovered ?? run.mergeRequestsDiscovered ?? 0,
        mergeRequestsProcessed: snapshot.processed ?? snapshot.mergeRequestsProcessed ?? run.mergeRequestsProcessed ?? 0,
        candidates: snapshot.candidates?.length ?? 0,
        exclusions: snapshot.exclusions?.length ?? 0,
        failures: snapshot.failures?.length ?? 0,
        failureDetails: snapshot.failures ?? [],
        status: partial ? 'in-progress' : run.status,
    };
    if (partial) {
        next.lastRun = recordedRun;
    } else {
        next.runs = [...base.runs, recordedRun];
        next.lastRun = recordedRun;
    }
    return next;
};
