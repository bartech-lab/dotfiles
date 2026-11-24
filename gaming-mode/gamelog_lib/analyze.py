"""Turn a recorded session into numbers, plain findings and one offline HTML page."""
import csv
import gzip
import hashlib
import html
import json
import random
import statistics
import time
from array import array
from bisect import bisect_left, bisect_right
from pathlib import Path

STUTTER_FACTOR = 2.5      # a stutter is a frame this many times the local median...
STUTTER_MS = 25           # ...and at least this long
SETTLE_S = 20             # after a loading screen, slow seconds count as "new area"
MIN_VISIT_S = 30          # an area visit shorter than this is mostly load-in and is left out of comparisons
MIN_PLAY_MIN = 30         # each settings group needs this many minutes of such visits, from any number of sessions
MIN_VISITS = 5            # ...and this many visits: the interval comes from resampling visits; false verdicts stop falling at 5
MIN_EFFECT = {'stutters_per_10min': 5, 'p99_ms': 0.3, 'low1_fps': 2, 'avg_fps': 1}    # smaller changes are noise
CHOSEN_INI = ('renderer_type', 'vsync', 'framerate_limit', 'framerate_limit_enabled', 'upscale', 'upscale_quality',
              'upscale_resolution', 'use_dynamic_resolution', 'dynamic_resolution_fps', 'shadow_type', 'texture_quality',
              'texture_filtering', 'light_quality', 'engine_multithreading_mode', 'screenspace_effects_resolution',
              'resolution_width', 'resolution_height', 'fullscreen', 'borderless_windowed_fullscreen', 'reflex_mode',
              'frame_generation', 'water_detail', 'global_illumination_detail', 'sun_shadow_type', 'bloom_strength')
VOLATILE_INI = ('window_x', 'window_y', 'adapter_name', 'last_monitor_name')    # may move without anyone choosing
CAUSES = {
    'new_area': 'new area loading in (shaders compile; expected, the game cannot keep its shader cache under Proton)',
    'vram': 'graphics memory full',
    'throttle': 'overheating or hardware slowdown',
    'pressure': 'disk or memory stall',
    'gpu': 'graphics card at its limit',
    'cpu': 'one CPU thread at its limit',
    'unexplained': 'no recorded cause',
}


def percentile(sorted_values, q):
    if not sorted_values:
        return None
    return sorted_values[min(len(sorted_values) - 1, int(q * len(sorted_values)))]


def number(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- loading

def load_frames(session):
    """Wall-clock time and length (ms) of every frame, from all MangoHud logs of the session."""
    times, lengths = array('d'), array('d')
    for path in sorted((session/'frames').glob('*.csv.gz')) if (session/'frames').is_dir() else []:
        rows, in_frames = [], False
        try:
            with gzip.open(path, 'rt', errors='replace') as handle:
                for line in handle:
                    if in_frames:
                        parts = line.rstrip().split(',')
                        if len(parts) == 16:
                            try:
                                rows.append((int(parts[15]), float(parts[1])))
                            except ValueError:
                                pass
                    elif line.startswith('fps,'):
                        in_frames = True
        except (OSError, EOFError):
            pass
        if not rows:
            continue
        # Rows are flushed as they happen, so the file's last write is the last frame.
        origin = path.stat().st_mtime - rows[-1][0] / 1e9
        for elapsed, length in rows:
            times.append(origin + elapsed / 1e9)
            lengths.append(length)
    return times, lengths


def load_samples(session):
    try:
        with open(session/'sampler.csv', newline='') as handle:
            return list(csv.DictReader(handle))
    except OSError:
        return []


def load_events(session):
    """Events with sub-second times: the log stamps whole seconds but also a millisecond uptime."""
    try:
        events = [json.loads(line) for line in (session/'events.jsonl').read_text().splitlines() if line.strip()]
    except OSError:
        return []
    if events:
        low = max(e['t'] - e['uptime_ms'] / 1000 for e in events)
        high = min(e['t'] + 1 - e['uptime_ms'] / 1000 for e in events)
        if low <= high:    # one uptime clock for the whole session
            for e in events:
                e['t'] = (low + high) / 2 + e['uptime_ms'] / 1000
    return events


def ini_values(session):
    """All key=value pairs of the saved game config; '[DISPLAY]' holds that section's keys alone."""
    values, display, section = {}, {}, None
    try:
        for line in (session/'config.ini').read_text().lstrip('\ufeff').splitlines():
            if line.startswith('['):
                section = line.strip('[] \r')
                continue
            key, sep, value = line.partition('=')
            if sep:
                values[key.strip()] = value.strip()
                if section == 'DISPLAY':
                    display[key.strip()] = value.strip()
    except OSError:
        pass
    values['[DISPLAY]'] = display
    return values


# ---------------------------------------------------------------- structure of a session

def area_kind(area):
    if 'Hideout' in area:
        return 'hideout'
    if 'town' in area.lower():
        return 'town'
    return 'map' if area.startswith('Map') else 'other'


def zones_and_pauses(events, end):
    """Zones (from the end of a loading screen to the next load) and stretches to leave out."""
    zones, pauses, pending, lost = [], [], None, None
    for e in events:
        if e['kind'] == 'zone':
            if zones and zones[-1]['end'] is None:
                zones[-1]['end'] = e['t']
            pending = e
        elif e['kind'] == 'loading':
            pauses.append((e['t'] - e['seconds'] - 0.5, e['t'] + 0.5))
            if pending:
                zones.append({'area': pending['area'], 'name': e['name'], 'level': pending['level'],
                              'kind': area_kind(pending['area']), 'start': e['t'] + 0.5, 'end': None,
                              'load_s': e['seconds']})
                pending = None
        elif e['kind'] == 'focus':
            if e['value'] == 'Lost':
                lost = e['t']
            elif lost is not None:
                pauses.append((lost, e['t'] + 0.5))
                lost = None
    if lost is not None:
        pauses.append((lost, end))
    if zones and zones[-1]['end'] is None:
        zones[-1]['end'] = end
    merged = []
    for start, stop in sorted(pauses):      # a load during an unfocused stretch must not end the stretch
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], stop))
        else:
            merged.append((start, stop))
    return zones, merged


def frame_stats(lengths):
    """Numbers for one set of frames (ms)."""
    if not lengths:
        return None
    ordered = sorted(lengths)
    total = sum(ordered)
    p99, p999 = percentile(ordered, 0.99), percentile(ordered, 0.999)
    return {'frames': len(ordered), 'seconds': round(total / 1000, 1), 'avg_fps': round(1000 * len(ordered) / total, 1),
            'median_fps': round(1000 / statistics.median(ordered), 1), 'low1_fps': round(1000 / p99, 1),
            'low01_fps': round(1000 / p999, 1), 'p95_ms': round(percentile(ordered, 0.95), 2), 'p99_ms': round(p99, 2),
            'p999_ms': round(p999, 2), 'max_ms': round(ordered[-1], 1)}


def find_stutters(times, lengths):
    """(time, ms) of each stutter; neighbours within 100 ms count once, the longest wins."""
    found = []
    for i, length in enumerate(lengths):
        if length < STUTTER_MS:
            continue
        local = statistics.median(lengths[max(0, i - 60):i + 61])
        if length < STUTTER_FACTOR * local:
            continue
        if found and times[i] - found[-1][0] <= 0.1 + length / 1000:
            if length > found[-1][1]:
                found[-1] = (times[i], length)
        else:
            found.append((times[i], length))
    return found


# ---------------------------------------------------------------- analysis

def fingerprint(meta, ini):
    """The settings somebody chose. Updates (kernel, driver, packages) are kept apart as 'ambient'."""
    settings, process = meta.get('settings', {}), meta.get('process', {})
    env = process.get('env', {})
    # The whole display section when the file has one, so no graphics key is missed.
    graphics = dict(ini.get('[DISPLAY]') or {k: ini[k] for k in CHOSEN_INI if k in ini})
    graphics.update({k: ini[k] for k in ('engine_multithreading_mode', 'networking_type') if k in ini})
    for volatile in VOLATILE_INI:
        graphics.pop(volatile, None)
    chosen = {
        'ini': graphics,
        'lutris_env': {k: v for k, v in settings.get('lutris_env', {}).items() if not k.startswith('MANGOHUD')},
        'game_env': {k: v for k, v in env.items() if k.startswith(('PROTON_', 'WINEFSYNC', 'WINEESYNC', 'WINENTSYNC', 'DXVK_', 'VKD3D_', 'AFMF', '__GL_'))
                     and k not in ('PROTON_LOG_DIR',)},
        'sync': process.get('sync'),
        'afmf': bool(process.get('afmf_loaded')),
        'game_mode': settings.get('game_mode_on'),
        'system': {k: settings.get(k) for k in ('governor', 'epp', 'power_profile', 'thp', 'split_lock_mitigate',
                                                'swappiness', 'swap_total_mb', 'kwin_allow_tearing')},
    }
    # The kernel command line names the kernel version in initrd=; that part is an update, not a choice.
    chosen['system']['cmdline'] = ' '.join(p for p in (settings.get('cmdline') or '').split() if not p.startswith(('initrd=', 'BOOT_IMAGE='))) or None
    # The Proton build follows the newest release on purpose, so it is an update like the driver.
    ambient = {'kernel': settings.get('kernel'), 'nvidia_driver': settings.get('nvidia_driver'), 'proton': process.get('proton_version'),
               'game_version': settings.get('game_version'), 'packages': settings.get('packages', {})}
    digest = hashlib.sha256(json.dumps(chosen, sort_keys=True).encode()).hexdigest()[:8]
    return digest, chosen, ambient


def flatten(data, prefix=''):
    flat = {}
    for key, value in (data or {}).items():
        if isinstance(value, dict):
            flat.update(flatten(value, f'{prefix}{key}.'))
        else:
            flat[prefix + key] = value
    return flat


def differences(old, new):
    a, b = flatten(old), flatten(new)
    return {k: [a.get(k), b.get(k)] for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)}


def analyze(session):
    session = Path(session)
    meta = json.loads((session/'meta.json').read_text())
    ini = ini_values(session)
    times, lengths = load_frames(session)
    samples = load_samples(session)
    events = load_events(session)
    end = meta.get('end', time.time())
    zones, pauses = zones_and_pauses(events, end)
    digest, chosen, ambient = fingerprint(meta, ini)
    summary = {'schema': 1, 'session': session.name, 'status': meta.get('status'), 'start': meta.get('start'), 'end': end,
               'fingerprint': digest, 'chosen': chosen, 'ambient': ambient, 'exit': meta.get('exit'),
               'findings': [], 'zones': [], 'kinds': {}, 'causes': {}}
    cap = number(ini.get('framerate_limit')) if ini.get('framerate_limit_enabled', '').lower() == 'true' else None
    summary['fps_cap'] = cap

    # Play time: inside a zone, not loading, window focused.
    def paused(t):
        i = bisect_right(pauses, (t, float('inf'))) - 1
        return i >= 0 and pauses[i][0] <= t < pauses[i][1]

    active_t, active_l = array('d'), array('d')
    for zone in zones:
        lo, hi = bisect_left(times, zone['start']), bisect_left(times, zone['end'])
        zt = [i for i in range(lo, hi) if not paused(times[i])]
        zl = [lengths[i] for i in zt]
        stats = frame_stats(zl)
        zone['stats'] = stats
        zone['_idx'] = zt
        if stats:
            active_t.extend(times[i] for i in zt)
            active_l.extend(zl)
    stutters = find_stutters(active_t, active_l)
    overall = frame_stats(active_l)
    summary['overall'] = overall
    if not overall:
        summary['findings'].append({'level': 'bad', 'text': 'No frames were recorded during play, so this session has no performance numbers.'})
        return summary, {'times': times, 'lengths': lengths, 'samples': samples, 'events': events, 'zones': zones, 'stutters': []}
    minutes = overall['seconds'] / 60
    summary['active_minutes'] = round(minutes, 1)
    summary['stutters'] = len(stutters)
    summary['stutters_per_10min'] = round(len(stutters) / max(minutes, 0.1) * 10, 1)
    summary['worst_stutter_ms'] = round(max((s[1] for s in stutters), default=0), 1)

    for zone in zones:
        idx = zone.pop('_idx')
        if zone['stats']:
            zone['stutters'] = sum(1 for t, _ in stutters if zone['start'] <= t < zone['end'])
            summary['zones'].append({k: zone[k] for k in ('area', 'name', 'level', 'kind', 'load_s', 'stats', 'stutters', 'start', 'end')})
            summary['kinds'].setdefault(zone['kind'], []).extend(lengths[i] for i in idx)
    summary['kinds'] = {kind: frame_stats(values) for kind, values in summary['kinds'].items()}
    for kind, stats in summary['kinds'].items():
        count = sum(z['stutters'] for z in summary['zones'] if z['kind'] == kind)
        stats['stutters_per_10min'] = round(count / max(stats['seconds'], 1) * 600, 1)

    # One-second windows joined with the system samples.
    per_second = {}
    for t, length in zip(active_t, active_l):
        bucket = per_second.setdefault(int(t), [0, 0.0])
        bucket[0] += 1
        bucket[1] += length
    by_second = {int(float(row['t'])): row for row in samples if number(row.get('t'))}
    stutter_seconds = {int(t) for t, _ in stutters}
    median_fps = overall['median_fps']
    # A limit the game does not reach most of the time (240 on a card that does 200) is not a target.
    target = cap if cap and median_fps >= 0.95 * cap else None
    summary['fps_cap_reached'] = bool(target)
    load_ends = [z['start'] for z in zones]
    warnings = sorted(e['t'] for e in events if e['kind'] == 'vram_warning')
    pso_off = any(e['kind'] == 'pso_cache' and e['value'] != 'Enabled' for e in events) or any(e['kind'] == 'lmdb_failed' for e in events)
    causes, slow = {}, 0
    for second, (count, total_ms) in per_second.items():
        if total_ms < 500:      # a second mostly spent paused
            continue
        fps = 1000 * count / total_ms
        if not (second in stutter_seconds or fps < (0.95 * target if target else 0.8 * median_fps)):
            continue
        slow += 1
        row = by_second.get(second) or by_second.get(second - 1) or by_second.get(second + 1) or {}
        value = lambda key: number(row.get(key))
        top = number((row.get('top_threads') or '').split('|')[0].rpartition(':')[2])
        i = bisect_right(load_ends, second + 1) - 1
        near_warning = bisect_left(warnings, second - 5) < bisect_right(warnings, second + 5)
        if (value('vram_used') and value('vram_total') and value('vram_used') >= 0.93 * value('vram_total')) or near_warning:
            cause = 'vram'
        # The power-cap flag is left out: a fully busy card always sits at its power limit, so that is 'gpu'.
        elif any(value(k) == 1 for k in ('thr_hw', 'thr_hw_thermal', 'thr_sw_thermal')) or (value('cpu_temp') or 0) >= 93:
            cause = 'throttle'
        elif (value('psi_io_ms') or 0) >= 100 or (value('psi_mem_ms') or 0) >= 100 or (value('psi_cpu_ms') or 0) >= 200:
            cause = 'pressure'
        elif i >= 0 and second - load_ends[i] <= SETTLE_S and (value('gpu_util') or 0) < 95:
            cause = 'new_area'
        elif (value('gpu_util') or 0) >= 95:
            cause = 'gpu'
        elif (top or 0) >= 90:
            cause = 'cpu'
        else:
            cause = 'unexplained'
        causes[cause] = causes.get(cause, 0) + 1
    seconds = sum(1 for _, total_ms in per_second.values() if total_ms >= 500)
    summary['slow_seconds'] = slow
    summary['slow_share'] = round(slow / max(seconds, 1), 4)
    summary['causes'] = dict(sorted(causes.items(), key=lambda kv: -kv[1]))

    # System picture during play.
    active_rows = [by_second[s] for s in per_second if s in by_second]

    def column(key):
        return sorted(v for v in (number(r.get(key)) for r in active_rows) if v is not None)

    gpu, vram, rtt = column('gpu_util'), column('vram_used'), column('rtt_ms')
    tops = sorted(v for v in (number((r.get('top_threads') or '').split('|')[0].rpartition(':')[2]) for r in active_rows) if v is not None)
    total_vram = max(column('vram_total') or [0])
    summary['system'] = {
        'gpu_util_median': percentile(gpu, 0.5), 'gpu_util_p95': percentile(gpu, 0.95),
        'top_thread_median': percentile(tops, 0.5), 'top_thread_p95': percentile(tops, 0.95),
        'vram_peak_mib': vram[-1] if vram else None, 'vram_total_mib': total_vram or None,
        'proc_vram_peak_mib': (column('proc_vram') or [None])[-1],
        'cpu_temp_max': (column('cpu_temp') or [None])[-1], 'gpu_temp_max': (column('gpu_temp') or [None])[-1],
        'gpu_w_median': percentile(column('gpu_w'), 0.5), 'cpu_w_median': percentile(column('cpu_w'), 0.5),
        'rss_peak_mb': (column('rss_mb') or [None])[-1], 'rtt_median_ms': percentile(rtt, 0.5), 'rtt_p95_ms': percentile(rtt, 0.95),
        'rtt_spikes': sum(1 for v in rtt if v > max(3 * percentile(rtt, 0.5), percentile(rtt, 0.5) + 50)) if rtt else 0,
        'cache_growth_mb': (lambda c: round(c[-1] - c[0]) if c else None)([v for v in (number(r.get('cache_mb')) for r in samples) if v is not None]),
        'recorder_cpu_pct': round(100 * meta.get('recorder_cpu_s', 0) / max(end - meta.get('game_start', end), 1), 2),
    }
    kernel = (session/'kernel.log').read_text().splitlines() if (session/'kernel.log').exists() else []
    summary['kernel'] = {'xid': [l for l in kernel if 'Xid' in l][:10], 'flip_timeouts': sum('Flip event timeout' in l for l in kernel),
                         'oom': sum(('Out of memory' in l) or ('oom-kill' in l) for l in kernel)}
    summary['game_log'] = {'vram_warnings': len(warnings), 'disconnects': sum(e['kind'] == 'disconnect' for e in events),
                           'pso_cache_off': pso_off, 'present_mode': next((e['value'] for e in reversed(events) if e['kind'] == 'present_mode'), None),
                           'renderer': next((e['value'] for e in reversed(events) if e['kind'] == 'renderer'), None),
                           'reflex': next((e['value'] for e in reversed(events) if e['kind'] == 'reflex'), None),
                           'connect_ms_median': percentile(sorted(e['ms'] for e in events if e['kind'] == 'connect'), 0.5),
                           'load_s_median': percentile(sorted(z['load_s'] for z in zones), 0.5), 'crit_counts': meta.get('crit_counts', {})}
    afmf = chosen['afmf']
    summary['frame_basis'] = 'real' if not afmf else 'unknown' if not cap else 'doubled' if overall['median_fps'] >= 1.8 * cap else 'real'
    summary['findings'] = findings(summary, meta)
    detail = {'times': times, 'lengths': lengths, 'samples': samples, 'events': events, 'zones': zones, 'stutters': stutters,
              'pauses': pauses, 'per_second': per_second}
    return summary, detail


def findings(s, meta):
    """Plain sentences, most important first. level: bad, warn, info, good."""
    out = []
    add = lambda level, text: out.append({'level': level, 'text': text})
    o, system, log, settings = s['overall'], s['system'], s['game_log'], meta.get('settings', {})
    process = meta.get('process', {})
    if s['exit'] != 'graceful':
        add('bad', 'The game did not close normally (crash, kill or frozen exit).')
    if s['kernel']['xid']:
        add('bad', f"The graphics driver reported {len(s['kernel']['xid'])} error(s) (Xid) during the session.")
    if s['kernel']['oom']:
        add('bad', 'The system ran out of memory during the session.')
    if log['disconnects']:
        add('warn', f"{log['disconnects']} abnormal disconnect(s) from the game server.")
    if process and process.get('mangohud_loaded') is False:
        add('warn', 'MangoHud was not loaded in the game; frame numbers may be missing.')
    cap = s['fps_cap'] if s.get('fps_cap_reached') else None
    share = s['slow_share']
    if cap and share < 0.02:
        headroom = '' if system['gpu_util_median'] is None else f" The graphics card was {system['gpu_util_median']:.0f}% busy (median), so it has room for more."
        add('good', f"The game held its own {cap:.0f} fps limit {100 * (1 - share):.1f}% of the time.{headroom}")
    elif share >= 0.02:
        parts = ', '.join(f"{CAUSES[c].split(' (')[0]} {100 * n / s['slow_seconds']:.0f}%" for c, n in s['causes'].items())
        add('warn', f"{100 * share:.1f}% of play seconds were slow or stuttered. Causes: {parts}.")
    if s['stutters_per_10min'] >= 5:
        add('warn', f"{s['stutters_per_10min']} stutters per 10 minutes; the worst frame took {s['worst_stutter_ms']:.0f} ms.")
    if log['vram_warnings'] or (system['vram_peak_mib'] and system['vram_total_mib'] and system['vram_peak_mib'] >= 0.93 * system['vram_total_mib']):
        why = '' if settings.get('game_mode_on') else ' Game mode was off, so Bonsai held most of it.'
        add('bad', f"Graphics memory ran short: {log['vram_warnings']} warning(s) in the game log, peak {system['vram_peak_mib'] or 0:.0f} of {system['vram_total_mib'] or 0:.0f} MiB.{why}")
    if (system['cpu_temp_max'] or 0) >= 93 or s['causes'].get('throttle'):
        add('warn', f"Overheating or a hardware slowdown was recorded (CPU peak {system['cpu_temp_max']} °C, GPU peak {system['gpu_temp_max']} °C).")
    if system['rtt_spikes'] and system['rtt_median_ms'] is not None:
        add('warn', f"Network: {system['rtt_spikes']} latency spike(s); usual round trip {system['rtt_median_ms']:.0f} ms, 95% under {system['rtt_p95_ms']:.0f} ms. This is the connection, not rendering.")
    if log['pso_cache_off'] and s['causes'].get('new_area'):
        add('info', 'Hitches right after entering an area are expected: the game cannot keep its shader cache under Proton (Wine bug, no fix yet).')
    if s['kernel']['flip_timeouts']:
        add('info', f"{s['kernel']['flip_timeouts']} display 'flip timeout' message(s) from the driver: a known desktop issue at start or exit, not a game problem.")
    if s['frame_basis'] == 'doubled':
        add('info', 'Frame generation was on and the counter includes generated frames: fps numbers are about twice the real ones.')
    if system['recorder_cpu_pct'] > 1:
        add('warn', f"The recorder itself used {system['recorder_cpu_pct']}% of one CPU core.")
    return out


def write_summary(session):
    summary, detail = analyze(session)
    path = Path(session)/'summary.json'
    if path.exists() and not (Path(session)/'frames').is_dir():
        # The frame logs were pruned: the saved numbers are all that is left, so they are kept.
        return json.loads(path.read_text()), detail
    temp = path.with_name('summary.json.tmp')
    temp.write_text(json.dumps(summary, indent=1, sort_keys=True) + '\n')
    temp.replace(path)
    return summary, detail


# ---------------------------------------------------------------- comparison across sessions

def summaries(sessions_dir):
    out = []
    for path in sorted(Path(sessions_dir).glob('*/summary.json')):
        try:
            out.append(json.loads(path.read_text()))
        except (OSError, ValueError):
            pass
    return out


def visits(summary, kind):
    """Area visits of one kind long enough to compare; whole visits are the units resampled."""
    if summary.get('status') != 'ok':
        return []
    return [z for z in summary.get('zones') or [] if z.get('kind') == kind and z.get('stats') and z['stats']['seconds'] >= MIN_VISIT_S]


def latest_kind(all_summaries):
    """The kind of area the most recent session spent most time in: it shows what the user plays now."""
    for s in reversed(all_summaries):
        kinds = {k: v['seconds'] for k, v in (s.get('kinds') or {}).items() if v} if s.get('status') == 'ok' else {}
        if kinds:
            return max(kinds, key=kinds.get)
    return None


def metric(vs, key):
    if key == 'stutters_per_10min':     # pooled over play time, so short visits do not count as much as long ones
        return 600 * sum(z['stutters'] for z in vs) / sum(z['stats']['seconds'] for z in vs)
    return statistics.median(z['stats'][key] for z in vs)


def bootstrap(a, b, key, rounds=2000, seed=1):
    """95% interval for metric(b) - metric(a), resampling area visits."""
    rng = random.Random(seed)
    diffs = sorted(metric(rng.choices(b, k=len(b)), key) - metric(rng.choices(a, k=len(a)), key) for _ in range(rounds))
    return diffs[int(0.025 * rounds)], diffs[int(0.975 * rounds)]


def minutes(group):
    return sum(z['stats']['seconds'] for z in group['visits']) / 60


def compare(all_summaries):
    """Latest settings group against the one before it. Returns a dict with 'verdict' text."""
    kind = latest_kind(all_summaries)
    groups = []
    for s in all_summaries:
        vs = visits(s, kind) if kind else []
        if not vs:
            continue
        if groups and groups[-1]['fingerprint'] == s['fingerprint']:
            groups[-1]['sessions'].append(s)
            groups[-1]['visits'].extend(vs)
        else:
            groups.append({'fingerprint': s['fingerprint'], 'sessions': [s], 'visits': list(vs)})
    result = {'kind': kind, 'needed_minutes': MIN_PLAY_MIN,
              'groups': [{'fingerprint': g['fingerprint'], 'sessions': len(g['sessions']), 'minutes': round(minutes(g))} for g in groups]}
    if not groups:
        result['verdict'] = 'Not enough data: no recorded play to compare yet.'
        return result
    new = groups[-1]
    result['current_minutes'] = minutes(new)
    result['ready'] = minutes(new) >= MIN_PLAY_MIN
    if len(groups) < 2:
        state = 'ready' if result['ready'] else f'needs {MIN_PLAY_MIN}'
        result['verdict'] = (f"Baseline: {minutes(new):.0f} minutes of play in '{kind}' areas on the current settings ({state}). "
                             'Nothing to compare with yet.')
        return result
    old = groups[-2]
    result['changed'] = differences(old['sessions'][-1]['chosen'], new['sessions'][0]['chosen'])
    result['updates'] = differences(old['sessions'][-1]['ambient'], new['sessions'][-1]['ambient'])
    if minutes(old) < MIN_PLAY_MIN or minutes(new) < MIN_PLAY_MIN:
        result['verdict'] = (f"Not enough data in '{kind}' areas: the earlier settings have {minutes(old):.0f} minutes of play, "
                             f"the current ones {minutes(new):.0f}; need {MIN_PLAY_MIN} each.")
        return result
    if min(len(old['visits']), len(new['visits'])) < MIN_VISITS:
        result['verdict'] = (f"Not enough data in '{kind}' areas: the earlier settings have {len(old['visits'])} area visits, "
                             f"the current ones {len(new['visits'])}; need {MIN_VISITS} each.")
        return result
    bases = {s.get('frame_basis') for s in old['sessions'] + new['sessions']}
    if len(bases) > 1:
        result['verdict'] = 'Cannot compare: one group counts generated frames and the other does not.'
        return result
    result['metrics'] = {}
    lines = []
    for key, label, better in (('stutters_per_10min', 'stutters per 10 min', 'lower'), ('p99_ms', '99th percentile frame time (ms)', 'lower'),
                               ('low1_fps', '1% low fps', 'higher'), ('avg_fps', 'average fps', 'higher')):
        a, b = old['visits'], new['visits']
        low, high = bootstrap(a, b, key)
        before, after = metric(a, key), metric(b, key)
        diff = after - before
        real = (low > 0 or high < 0) and abs(diff) >= MIN_EFFECT[key]
        word = 'no clear change' if not real else 'better' if (diff < 0) == (better == 'lower') else 'worse'
        result['metrics'][key] = {'before': before, 'after': after, 'low': low, 'high': high, 'verdict': word}
        lines.append(f"{label}: {before:.1f} -> {after:.1f} ({word}; 95% range of the change {low:+.1f} to {high:+.1f})")
    result['verdict'] = (f"In '{kind}' areas, {minutes(old):.0f} minutes before ({len(old['sessions'])} session(s)) vs "
                         f"{minutes(new):.0f} after ({len(new['sessions'])}). " + '; '.join(lines) + '.')
    return result


# ---------------------------------------------------------------- what to try next

def candidates(summary, meta, today=None):
    """Ordered suggestions whose evidence holds now. Nothing here is applied by the tool."""
    today = today or time.strftime('%Y-%m-%d')
    s, settings, process = summary, meta.get('settings', {}), meta.get('process', {})
    ini = s['chosen']['ini']
    system, causes = s.get('system', {}), s.get('causes', {})
    slow = max(s.get('slow_seconds', 0), 1)
    share = lambda cause: causes.get(cause, 0) / slow if s.get('slow_share', 0) >= 0.02 else 0
    gpu = system.get('gpu_util_median')
    capped_easily = bool(s.get('fps_cap_reached')) and s.get('slow_share', 1) < 0.02
    vram_free = (system.get('vram_total_mib') or 0) - (system.get('vram_peak_mib') or 0)
    out = []

    def add(key, when, change, judged, evidence):
        if when:
            out.append({'id': key, 'change': change, 'judged_by': judged, 'evidence': evidence})

    add('game-mode', settings.get('game_mode_on') is False, 'Start the game from the desktop icon so game mode frees the graphics memory.',
        'graphics memory warnings', f"only {((settings.get('vram_total_mib') or 0) - (settings.get('vram_used_mib_at_launch') or 0)) / 1024:.1f} GB free at launch")
    add('afmf', today >= '2026-12-01' and not s['chosen']['afmf'], 'Turn frame generation on: game-quirks afmf lutris:path-of-exile-2',
        'smoothness as seen, real 1% low, stutters per 10 min (fps numbers double; never compared across)', 'planned first test; baseline is measured without it')
    # Left out: settings that cannot matter here (DXVK with the Vulkan renderer, cache housekeeping, fsync under ntsync).
    ignored = [n for n in settings.get('lutris_ignored_env') or []
               if not (n.startswith(('DXVK_', '__GL_SHADER_DISK_CACHE', 'VK_ICD')) or (n in ('WINEFSYNC', 'WINEESYNC') and process.get('sync') == 'ntsync'))]
    add('ignored-lutris-env', bool(ignored), f"Move one ignored Lutris setting at a time to 'system: env:': {', '.join(ignored)}",
        '1% low, stutters per 10 min', 'Lutris ignores the game-level list, so none of these has ever applied')
    add('fps-cap', capped_easily and gpu is not None and gpu < 60, f"Raise the in-game fps limit from {s.get('fps_cap') or 0:.0f} to 120 (the monitor shows 240).",
        '1% low at the new limit, temperatures, power', f"limit held {100 * (1 - s.get('slow_share', 0)):.1f}% of the time with the graphics card {gpu or 0:.0f}% busy")
    add('upscaler', ini.get('upscale') == 'NIS' and gpu is not None and gpu < 70,
        'Switch upscaling from NIS to DLSS at Quality or native (DLAA) and turn dynamic resolution off.',
        'image sharpness as seen, 1% low, graphics card load', f"NIS at {ini.get('upscale_resolution')} renders far below 1440p while the card is {gpu or 0:.0f}% busy")
    add('texture-quality', 'Low' in ini.get('texture_quality', '') and vram_free >= 6000 and settings.get('game_mode_on'),
        'Raise texture quality one step.', 'graphics memory peak, stutters after loading', f"{vram_free / 1024:.1f} GB of graphics memory stayed free")
    add('reflex', (s.get('game_log') or {}).get('reflex') == 'OFF' and share('gpu') >= 0.1, 'Turn NVIDIA Reflex on in the game.',
        '99th percentile frame time', 'the graphics card was the limit in slow moments')
    add('present-mode', (s.get('game_log') or {}).get('present_mode') == 'Fifo' and ini.get('vsync') == 'Off' and not s.get('fps_cap'),
        'The game presents with Fifo (synchronised) although vsync is off; try the DX12 renderer or check KWin tearing.',
        '0.1% low, input feel', 'present mode Fifo with vsync off')
    add('engine-multithreading', share('cpu') >= 0.15, f"Try engine_multithreading_mode other than '{ini.get('engine_multithreading_mode')}'.",
        '1% low', f"one CPU thread was the limit in {100 * share('cpu'):.0f}% of slow seconds")
    add('renderer-dx12', share('unexplained') >= 0.5 and s.get('stutters_per_10min', 0) >= 10, 'Try the DirectX 12 renderer (through vkd3d-proton).',
        'stutters per 10 min', 'frequent stutters without a recorded cause on the Vulkan renderer')
    add('proton-ge11', (process.get('proton_version') or '').startswith('GE-Proton10'), 'Try GE-Proton11-12 or newer (11-8 and 11-9 had a PoE fps bug).',
        '1% low, stutters per 10 min', f"running {process.get('proton_version')}")
    add('swap', (settings.get('swap_total_mb') or 0) < 2048 and (share('pressure') >= 0.1 or (settings.get('swap_free_mb') or 0) < 64),
        'Add zram or a larger swap file (the 512 MB one is full).', 'disk or memory stalls', f"swap free at launch: {settings.get('swap_free_mb')} MB")
    add('cpu-tuning', share('cpu') >= 0.3, 'One at a time: gamemode, EPP performance, a sched-ext scheduler.', '1% low',
        f"one CPU thread was the limit in {100 * share('cpu'):.0f}% of slow seconds")
    return out


# ---------------------------------------------------------------- HTML report

CSS = """
:root{--bg:#fbfbfa;--fg:#1c1c1c;--muted:#6b6b6b;--line:#d9d9d6;--card:#fff;--a:#2b6cb0;--b:#c05621;--c:#2f855a;--d:#805ad5;--bad:#c53030;--warn:#b7791f;--good:#2f855a}
@media(prefers-color-scheme:dark){:root{--bg:#161718;--fg:#e8e8e6;--muted:#9a9a97;--line:#3a3b3d;--card:#1f2022;--a:#63b3ed;--b:#f6ad55;--c:#68d391;--d:#b794f4;--bad:#fc8181;--warn:#f6e05e;--good:#68d391}}
body{background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif;max-width:1040px;margin:24px auto;padding:0 16px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px}small,.muted{color:var(--muted)}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 16px;min-width:130px}
.card b{display:block;font-size:26px;font-variant-numeric:tabular-nums}
ul.f{list-style:none;padding:0}ul.f li{padding:6px 10px;margin:4px 0;border-left:4px solid var(--line);background:var(--card)}
li.bad{border-color:var(--bad)}li.warn{border-color:var(--warn)}li.good{border-color:var(--good)}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{text-align:right;padding:4px 8px;border-bottom:1px solid var(--line)}
th:first-child,td:first-child{text-align:left}th{color:var(--muted);font-weight:500}
svg{width:100%;height:auto;background:var(--card);border:1px solid var(--line);border-radius:8px}
svg text{fill:var(--muted);font-size:11px}.ax{stroke:var(--line);stroke-width:1}.legend span{margin-right:14px}.sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px}
code{background:var(--card);border:1px solid var(--line);border-radius:4px;padding:0 4px}
"""
W, H, L, R, T, B = 1000, 220, 44, 10, 10, 22


def chart(series, t0, t1, y_max, unit, bands=(), marks=()):
    """series: [(label, css colour variable, [(t, low, high)])]. Each pixel column keeps its min and max."""
    span = max(t1 - t0, 1)
    x = lambda t: L + (W - L - R) * (t - t0) / span
    y = lambda v: T + (H - T - B) * (1 - min(v, y_max) / y_max)
    parts = [f'<svg viewBox="0 0 {W} {H}" role="img">']
    for start, end, label in bands:
        parts.append(f'<rect x="{x(start):.1f}" y="{T}" width="{max(x(end) - x(start), 0.5):.1f}" height="{H - T - B}" fill="var(--line)" opacity="0.35"><title>{html.escape(label)}</title></rect>')
    for i in range(5):
        value = y_max * i / 4
        parts.append(f'<line class="ax" x1="{L}" x2="{W - R}" y1="{y(value):.1f}" y2="{y(value):.1f}"/><text x="{L - 6}" y="{y(value) + 4:.1f}" text-anchor="end">{value:.0f}</text>')
    for i in range(7):
        t = t0 + span * i / 6
        parts.append(f'<text x="{x(t):.1f}" y="{H - 6}" text-anchor="{"end" if i == 6 else "middle"}">{(t - t0) / 60:.0f} min</text>')
    for label, colour, points in series:
        columns = {}
        for t, low, high in points:
            col = int(x(t))
            old = columns.get(col)
            columns[col] = (low, high) if old is None else (min(old[0], low), max(old[1], high))
        if not columns:
            continue
        path = ' '.join(f'{"M" if i == 0 else "L"}{col},{y(high):.1f} L{col},{y(low):.1f}' for i, (col, (low, high)) in enumerate(sorted(columns.items())))
        parts.append(f'<path d="{path}" fill="none" stroke="var({colour})" stroke-width="1.2"><title>{html.escape(label)}</title></path>')
    for t, label in marks:
        parts.append(f'<line x1="{x(t):.1f}" x2="{x(t):.1f}" y1="{T}" y2="{T + 8}" stroke="var(--bad)" stroke-width="1.5"><title>{html.escape(label)}</title></line>')
    parts.append(f'<text x="{L + 4}" y="{T + 12}">{html.escape(unit)}</text></svg>')
    legend = ''.join(f'<span><i class="sw" style="background:var({colour})"></i>{html.escape(label)}</span>' for label, colour, _ in series)
    return ''.join(parts) + f'<div class="legend muted">{legend}</div>'


def histogram(lengths, cap_ms=50):
    bins = [0] * 50
    for length in lengths:
        bins[min(49, int(length / cap_ms * 50))] += 1
    top = max(bins) or 1
    width = (W - L - R) / 50
    bars = ''.join(f'<rect x="{L + i * width:.1f}" y="{T + (H - T - B) * (1 - n / top):.1f}" width="{width - 1:.1f}" height="{(H - T - B) * n / top:.1f}" fill="var(--a)"><title>{i * cap_ms / 50:.0f}-{(i + 1) * cap_ms / 50:.0f} ms: {n} frames</title></rect>' for i, n in enumerate(bins))
    labels = ''.join(f'<text x="{L + (W - L - R) * i / 5:.1f}" y="{H - 6}" text-anchor="{"end" if i == 5 else "middle"}">{cap_ms * i / 5:.0f}{"+" if i == 5 else ""} ms</text>' for i in range(6))
    return f'<svg viewBox="0 0 {W} {H}" role="img">{bars}{labels}</svg>'


def report(session, summary, detail, comparison, suggestions):
    """Write report.html: offline, one file, no raw log lines."""
    e = html.escape
    o = summary.get('overall')
    start = summary.get('start') or 0
    title = f"PoE2 session {time.strftime('%Y-%m-%d %H:%M', time.localtime(start))}"
    doc = [f'<!doctype html><html lang="en"><meta charset="utf-8"><title>{e(title)}</title><style>{CSS}</style><h1>{e(title)}</h1>']
    chosen, ambient = summary['chosen'], summary['ambient']
    doc.append(f"<div class='muted'>{summary.get('active_minutes', 0)} min of play · Proton {e(str(ambient.get('proton')))} · driver {e(str(ambient.get('nvidia_driver')))} · kernel {e(str(ambient.get('kernel')))} · settings group <code>{summary['fingerprint']}</code></div>")
    if o:
        cards = [('average fps', o['avg_fps']), ('1% low fps', o['low1_fps']), ('0.1% low fps', o['low01_fps']),
                 ('stutters / 10 min', summary['stutters_per_10min']), ('worst frame, ms', o['max_ms'])]
        doc.append('<div class="cards">' + ''.join(f'<div class="card"><b>{v}</b>{e(k)}</div>' for k, v in cards) + '</div>')
    doc.append('<h2>Findings</h2><ul class="f">' + (''.join(f'<li class="{f["level"]}">{e(f["text"])}</li>' for f in summary['findings']) or '<li>Nothing unusual.</li>') + '</ul>')
    if o and not len(detail['times']):
        doc.append("<p class='muted'>The frame logs of this session were removed by the retention rules, so there are no charts. The numbers above are the saved ones.</p>")
    if o and len(detail['times']):
        t0, t1 = detail['times'][0], detail['times'][-1]
        per_second = {}
        for t, length in zip(detail['times'], detail['lengths']):
            bucket = per_second.setdefault(int(t), [length, length])
            bucket[0], bucket[1] = min(bucket[0], length), max(bucket[1], length)
        ft = [(s, lo, hi) for s, (lo, hi) in sorted(per_second.items())]
        bands = [(a, b, 'loading or window not focused') for a, b in detail.get('pauses', []) if b > t0]
        marks = [(t, f'stutter {ms:.0f} ms') for t, ms in detail['stutters']]
        doc.append('<h2>Frame time</h2><div class="muted">Each frame, lower is smoother. Grey: loading or window not focused (left out of the numbers). Red ticks: stutters.</div>')
        doc.append(chart([('frame time', '--a', ft)], t0, t1, 50, 'ms per frame (capped at 50)', bands, marks))
        doc.append('<h2>Frame time spread</h2>' + histogram(detail['lengths']))

        def line(key, scale=1.0, split=None):
            points = []
            for row in detail['samples']:
                raw = row.get(key) or ''
                value = number(raw.split('|')[0].rpartition(':')[2]) if split else number(raw)
                t = number(row.get('t'))
                if value is not None and t is not None:
                    points.append((t, value * scale, value * scale))
            return points
        doc.append('<h2>Load</h2>' + chart([('graphics card %', '--a', line('gpu_util')), ('busiest game thread %', '--b', line('top_threads', split=True)), ('all CPU cores %', '--c', line('cpu_total'))], t0, t1, 100, '% busy'))
        total = (summary['system'].get('vram_total_mib') or 16384) / 1024
        doc.append('<h2>Memory</h2>' + chart([('graphics memory used, GB', '--a', line('vram_used', 1 / 1024)), ('game memory, GB', '--b', line('rss_mb', 1 / 1024))], t0, t1, max(total, 1), 'GB'))
        doc.append('<h2>Temperature and power</h2>' + chart([('CPU °C', '--b', line('cpu_temp')), ('graphics card °C', '--a', line('gpu_temp')), ('graphics card W', '--d', line('gpu_w')), ('CPU W', '--c', line('cpu_w'))], t0, t1, 320, '°C / W'))
        rtt = line('rtt_ms')
        if rtt:
            doc.append('<h2>Connection</h2>' + chart([('round trip to the game server, ms', '--a', rtt)], t0, t1, max(100, max(p[1] for p in rtt)), 'ms'))
        doc.append('<h2>Areas</h2><table><tr><th>area</th><th>kind</th><th>min</th><th>avg fps</th><th>1% low</th><th>p99 ms</th><th>stutters</th><th>load s</th></tr>')
        for z in summary['zones']:
            st = z['stats']
            doc.append(f"<tr><td>{e(z['name'] or z['area'])}</td><td>{z['kind']}</td><td>{st['seconds'] / 60:.1f}</td><td>{st['avg_fps']}</td><td>{st['low1_fps']}</td><td>{st['p99_ms']}</td><td>{z['stutters']}</td><td>{z['load_s']:.1f}</td></tr>")
        doc.append('</table>')
        if summary['causes']:
            doc.append('<h2>Slow seconds by cause</h2><table><tr><th>cause</th><th>seconds</th></tr>' + ''.join(f'<tr><td>{e(CAUSES[c])}</td><td>{n}</td></tr>' for c, n in summary['causes'].items()) + '</table>')
    doc.append(f"<h2>Compared with earlier sessions</h2><p>{e(comparison.get('verdict', ''))}</p>")
    for label, key in (('Settings changed since the previous group', 'changed'), ('Updates since then (not a setting you chose)', 'updates')):
        if comparison.get(key):
            doc.append(f'<div class="muted">{label}:</div><table>' + ''.join(f'<tr><td>{e(k)}</td><td>{e(str(a))}</td><td>{e(str(b))}</td></tr>' for k, (a, b) in comparison[key].items()) + '</table>')
    doc.append('<h2>Suggestions, not applied</h2>')
    if suggestions:
        doc.append(f'<div class="muted">One change at a time; the first one is next. Each needs {MIN_PLAY_MIN} minutes of play before and after, in the same kind of content.</div><table><tr><th>change</th><th>why now</th><th>judged by</th></tr>' + ''.join(f"<tr><td>{e(c['change'])}</td><td>{e(c['evidence'])}</td><td>{e(c['judged_by'])}</td></tr>" for c in suggestions) + '</table>')
    else:
        doc.append('<p>None: nothing in this session points at a setting worth testing.</p>')
    flat = flatten(chosen)
    doc.append('<h2>Settings of this session</h2><table>' + ''.join(f'<tr><td>{e(k)}</td><td>{e(str(v))}</td></tr>' for k, v in flat.items()) + '</table>')
    path = Path(session)/'report.html'
    path.write_text('\n'.join(doc) + '\n')
    return path
