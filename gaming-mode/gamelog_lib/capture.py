"""Record one Path of Exile 2 session: system samples, game log events, settings.

Passive only: reads the game's log and config, OS counters and the MangoHud
frame log. Never reads game memory, never sends input.
"""
import gzip
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import threading
import time
from pathlib import Path

HOME = Path.home()
STATE = Path(os.environ.get('GAMELOG_STATE', HOME/'.local/state/gaming/poe2')).absolute()
PROC = Path(os.environ.get('GAMELOG_PROC', '/proc'))
SYS = Path(os.environ.get('GAMELOG_SYS', '/sys'))
GAME_DIR = Path(os.environ.get('GAMELOG_GAME_DIR', HOME/'Games/path-of-exile-2'))
CLIENT_LOG = Path(os.environ.get('GAMELOG_CLIENT_LOG', GAME_DIR/'logs/Client.txt'))
INI = Path(os.environ.get('GAMELOG_INI', HOME/'Documents/My Games/Path of Exile 2/poe2_production_Config.ini'))
LUTRIS_GAMES = Path(os.environ.get('GAMELOG_LUTRIS_GAMES', HOME/'.config/lutris/games'))
LUTRIS_SLUG = 'path-of-exile-2'
LAUNCH = shlex.split(os.environ.get('GAMELOG_LAUNCH', f'lutris lutris:rungame/{LUTRIS_SLUG}'))
PROC_RE = re.compile(os.environ.get('GAMELOG_PROC_RE', r'PathOfExile\w*\.exe'))
PORT = 21360
NOTIFY = os.environ.get('GAMELOG_NOTIFY', 'ops').split()
INTERVAL = float(os.environ.get('GAMELOG_INTERVAL', '1'))
START_WAIT = float(os.environ.get('GAMELOG_START_WAIT', '180'))
RESTART_WAIT = float(os.environ.get('GAMELOG_RESTART_WAIT', '10'))
MIN_SECONDS = float(os.environ.get('GAMELOG_MIN_SECONDS', '60'))
CACHE_DIR = GAME_DIR/'drive_c/users/steamuser/AppData/Local/Path of Exile 2'
VERSION_FILE = GAME_DIR/'drive_c/users/steamuser/AppData/Roaming/Path of Exile 2/engine.version'
MANGO_CONF = Path(os.environ.get('GAMELOG_MANGO_CONF', HOME/'.config/gaming/poe2-mangohud.conf')).absolute()
INCOMING = STATE/'incoming'
SESSIONS = STATE/'sessions'
TICKS = os.sysconf('SC_CLK_TCK')


def read(path, default=''):
    try:
        return Path(path).read_text(errors='replace')
    except OSError:
        return default


def run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def notify(title, message, priority=3):
    subprocess.run([*NOTIFY, 'notify', title, message, '--priority', str(priority)], check=False)


# ---------------------------------------------------------------- game log

LINE = re.compile(r'^(\d{4})/(\d\d)/(\d\d) (\d\d):(\d\d):(\d\d) (\d+) [0-9a-f]+ \[(\w+) Client \d+\] (.*)$')
# Each pattern must match from the first character of the message. Chat lines
# start with a channel mark (#, @, $, %, &) or ": ", so they can never match.
EVENTS = [
    ('start', re.compile(r'\[STARTUP\] Game Start'), ()),
    ('renderer', re.compile(r'\[RENDER\] Starting device: (\w+)'), ('value',)),
    ('present_mode', re.compile(r'\[VULKAN\] Present mode = (\w+)'), ('value',)),
    ('swapchain', re.compile(r'\[\w+\] Init SwapChain = (\d+x\d+)'), ('value',)),
    ('upscaler', re.compile(r'\[STREAMLINE\]\[(DLSS|NIS|FSR)\] Enabled: (\w+)'), ('name', 'value')),
    ('reflex', re.compile(r'\[STREAMLINE\]\[Reflex\] Reflex Low Latency: (\w+)'), ('value',)),
    ('pso_cache', re.compile(r'\[SHADER\] PSO Cache: (\w+)'), ('value',)),
    ('lmdb_failed', re.compile(r'Failed to open LMDB environment'), ()),
    ('zone', re.compile(r'Generating level (\d+) area "([\w ]+)"'), ('level', 'area')),
    ('scene', re.compile(r'\[SCENE\] Set Source \[([^\]()]+)\]'), ('name',)),
    ('loading', re.compile(r'\[LOADING SCREEN\] \(([^)]*)\) Duration = ([\d.]+) seconds'), ('name', 'seconds')),
    ('focus', re.compile(r'\[WINDOW\] (Gained|Lost) focus'), ('value',)),
    ('connect', re.compile(r'Connect time to instance server was (\d+)ms'), ('ms',)),
    ('vram_warning', re.compile(r'\[TEXTURE\] Insufficient VRAM'), ()),
    ('exit_graceful', re.compile(r'Closing game gracefully'), ()),
    ('disconnect', re.compile(r'Abnormal disconnect'), ()),
]
NUMERIC = {'level': int, 'seconds': float, 'ms': int}


def parse_line(line):
    """One Client.txt line -> event dict, or None for anything not on the list."""
    found = LINE.match(line.rstrip('\r\n'))
    if not found:
        return None
    y, mo, d, h, mi, s, uptime, level, message = found.groups()
    stamp = time.mktime((int(y), int(mo), int(d), int(h), int(mi), int(s), 0, 0, -1))
    event = {'t': stamp, 'uptime_ms': int(uptime)}
    for kind, pattern, names in EVENTS:
        hit = pattern.match(message)
        if hit:
            event['kind'] = kind
            for name, value in zip(names, hit.groups()):
                event[name] = NUMERIC.get(name, str)(value)
            return event
    if level == 'CRIT':
        event['kind'] = 'crit'
        event['text'] = re.sub(r'\d+', 'N', message)[:60]
        return event
    return None


def log_position(path=None):
    path = path or CLIENT_LOG
    try:
        stat = os.stat(path)
        return {'offset': stat.st_size, 'inode': stat.st_ino}
    except OSError:
        return {'offset': 0, 'inode': None}


def read_events(position, path=None):
    """Events appended since position. Returns (events, crit_counts, truncated)."""
    path = path or CLIENT_LOG
    try:
        stat = os.stat(path)
    except OSError:
        return [], {}, False
    truncated = position['inode'] is not None and (stat.st_ino != position['inode'] or stat.st_size < position['offset'])
    events, crits = [], {}
    with open(path, 'rb') as handle:
        handle.seek(0 if truncated else position['offset'])
        for raw in handle:
            event = parse_line(raw.decode('utf-8', 'replace'))
            if not event:
                continue
            if event['kind'] == 'crit':
                crits[event['text']] = crits.get(event['text'], 0) + 1
            else:
                events.append(event)
    return events, crits, truncated


# ---------------------------------------------------------------- frame log

def frame_log_info(path):
    """(frames, seconds) of a MangoHud log; (0, 0.0) when it holds no frames."""
    opener = gzip.open if str(path).endswith('.gz') else open
    frames, last, in_frames = 0, '', False
    try:
        with opener(path, 'rt', errors='replace') as handle:
            for line in handle:
                if in_frames and line.count(',') == 15 and line.endswith('\n'):    # a crash can cut the last row
                    frames, last = frames + 1, line
                elif line.startswith('fps,'):
                    in_frames = True
    except (OSError, EOFError):
        pass
    try:
        return frames, int(last.rsplit(',', 1)[1]) / 1e9
    except (IndexError, ValueError):
        return frames, 0.0


def collect_frames(session, started):
    """Move this session's MangoHud logs into the session; delete older strays."""
    kept = []
    for path in sorted(INCOMING.glob('*.csv')) if INCOMING.exists() else []:
        if path.name.endswith('_summary.csv') or path.stat().st_mtime < started:
            path.unlink()
            continue
        (session/'frames').mkdir(exist_ok=True)
        target = session/'frames'/(path.name + '.gz')
        with open(path, 'rb') as source, gzip.open(target, 'wb', compresslevel=6) as out:
            shutil.copyfileobj(source, out)
        os.utime(target, (path.stat().st_atime, path.stat().st_mtime))
        path.unlink()
        kept.append(target)
    return kept


# ---------------------------------------------------------------- processes

def pids():
    try:
        return [int(n) for n in os.listdir(PROC) if n.isdigit()]
    except OSError:
        return []


def find_game():
    """Pid of the game: the largest process that runs the game's exe under its own name or Wine."""
    best, best_rss = None, -1
    for pid in pids():
        if not PROC_RE.search(read(PROC/str(pid)/'cmdline').replace('\0', ' ')):
            continue
        comm = read(PROC/str(pid)/'comm').strip()
        try:
            exe = os.path.basename(os.readlink(PROC/str(pid)/'exe'))
        except OSError:
            exe = ''
        # Launch wrappers (lutris-wrapper, umu-run, python) carry the exe in
        # their arguments too; only Wine processes and the game itself count.
        if not (comm and PROC_RE.pattern.startswith(comm[:8]) or exe.startswith('wine')):
            continue
        rss = int((re.search(r'VmRSS:\s+(\d+)', read(PROC/str(pid)/'status')) or [0, 0])[1])
        if rss > best_rss:
            best, best_rss = pid, rss
    return best


def wait_for_game(seconds):
    deadline = time.monotonic() + seconds
    while True:
        pid = find_game()
        if pid or time.monotonic() >= deadline:
            return pid
        time.sleep(min(1, max(INTERVAL, 0.01)))


def alive(pid):
    stat = read(PROC/str(pid)/'stat')
    state = stat[stat.rfind(')') + 2:stat.rfind(')') + 3]    # the name itself may hold ") "
    return bool(state) and state not in 'ZX'


# ---------------------------------------------------------------- settings

PACKAGES = ['linux', 'nvidia-open', 'nvidia-utils', 'lib32-nvidia-utils', 'mesa', 'mangohud', 'gamemode', 'lutris',
            'umu-launcher', 'vulkan-icd-loader', 'kwin', 'xorg-xwayland', 'wine', 'linux-firmware-nvidia', 'amd-ucode']
ENV_PREFIXES = ('PROTON', 'WINE', 'DXVK_', 'VKD3D_', '__GL_', '__NV_', 'MANGOHUD', 'VK_', 'AFMF', 'UMU_', 'STAGING_',
                'LD_PRELOAD', 'SteamGameId', 'GAMEID', 'SDL_', 'DISPLAY', 'WAYLAND_DISPLAY', 'ENABLE_', 'DISABLE_')
SECRET = re.compile(r'TOKEN|KEY|SECRET|PASS|CREDENTIAL|COOKIE|AUTH', re.I)
INI_SECRET = re.compile(r'token|session|password|credential|email|account|login', re.I)
LIBS = re.compile(r'MangoHud|VkLayer|afmf|nvngx|dxvk|vkd3d|d3d12|d3d11|winevulkan|libvulkan|libGLX_nvidia|ntsync', re.I)


def lutris_config():
    found = sorted(LUTRIS_GAMES.glob(f'{LUTRIS_SLUG}*.yml'))
    return found[0] if found else None


def system_env(text):
    block = re.search(r'^system:\n((?:[ \t].*\n?)*)', text, re.M)
    env = re.search(r'^  env:\n((?:    .*\n?)*)', block.group(1), re.M) if block else None
    pairs = re.findall(r"^    (\w+): '?([^'\n]*)'?", env.group(1), re.M) if env else []
    return {name: value for name, value in pairs if not SECRET.search(name)}


INI_SECTIONS = ('DISPLAY', 'NETWORKING', 'GENERAL', 'SOUND')


def filtered_ini():
    """The game config without account data: four sections, no secret-looking keys."""
    lines, keep = [], True
    for line in read(INI).splitlines():
        section = re.match(r'\[(\w+)\]', line)
        if section:
            keep = section.group(1) in INI_SECTIONS
        if keep and not INI_SECRET.search(line.split('=', 1)[0]):
            lines.append(line)
    return '\n'.join(lines) + '\n' if lines else ''


def capture_settings():
    """Everything that can explain a difference between two sessions, before launch."""
    gpu = run(['nvidia-smi', '--query-gpu=driver_version,memory.used,memory.total', '--format=csv,noheader,nounits']).strip().split(', ')
    meminfo = dict(re.findall(r'^(\w+):\s+(\d+)', read(PROC/'meminfo'), re.M))
    cpu0 = SYS/'devices/system/cpu/cpu0/cpufreq'
    config = lutris_config()
    ini = filtered_ini()
    layers = sorted(p.name for d in (HOME/'.local/share/vulkan/implicit_layer.d', Path('/usr/share/vulkan/implicit_layer.d'),
                                     Path('/etc/vulkan/implicit_layer.d')) if d.is_dir() for p in d.glob('*.json'))
    packages = dict(line.split(' ', 1) for line in run(['pacman', '-Q', *PACKAGES]).splitlines() if ' ' in line)
    return {
        'kernel': os.uname().release,
        'cmdline': re.sub(r'(root|machine_id)=\S+', r'\1=…', read(PROC/'cmdline').strip()),
        'packages': packages,
        'nvidia_driver': gpu[0] if gpu[0] else None,
        'vram_used_mib_at_launch': int(gpu[1]) if len(gpu) == 3 and gpu[1].isdigit() else None,
        'vram_total_mib': int(gpu[2]) if len(gpu) == 3 and gpu[2].isdigit() else None,
        'game_mode_on': (Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))/'gaming/state').exists(),
        'governor': read(cpu0/'scaling_governor').strip(),
        'epp': read(cpu0/'energy_performance_preference').strip(),
        'amd_pstate': read(SYS/'devices/system/cpu/amd_pstate/status').strip(),
        'power_profile': run(['powerprofilesctl', 'get']).strip(),
        'thp': (re.search(r'\[(\w+)\]', read(SYS/'kernel/mm/transparent_hugepage/enabled')) or ['', ''])[1],
        'split_lock_mitigate': read(PROC/'sys/kernel/split_lock_mitigate').strip(),
        'swappiness': read(PROC/'sys/vm/swappiness').strip(),
        'swap_total_mb': int(meminfo.get('SwapTotal', 0)) // 1024,
        'swap_free_mb': int(meminfo.get('SwapFree', 0)) // 1024,
        'mem_available_mb': int(meminfo.get('MemAvailable', 0)) // 1024,
        'kwin_allow_tearing': run(['kreadconfig6', '--file', 'kwinrc', '--group', 'Compositing', '--key', 'AllowTearing']).strip(),
        'lutris_env': system_env(read(config)) if config else {},
        'lutris_ignored_env': sorted(set(re.findall(r"^    (\w+):", (re.search(r'^game:\n(?:[ \t].*\n)*?  env:\n((?:    .*\n?)*)', read(config), re.M) or ['', ''])[1], re.M))
                                     - set(system_env(read(config)))) if config else [],
        'proton_pinned': bool(re.search(r'^wine:\n(?:[ \t].*\n)*?  version:', read(config), re.M)) if config else None,
        'implicit_layers': layers,
        'game_version': VERSION_FILE.read_bytes()[:16].hex() if VERSION_FILE.is_file() else None,
        'ini_hash': hashlib.sha256(ini.encode()).hexdigest()[:16] if ini else None,
    }


def capture_process(pid):
    """What the running game really got: environment, libraries, sync method."""
    base = PROC/str(pid)
    env = {}
    for pair in read(base/'environ').split('\0'):
        name, _, value = pair.partition('=')
        if name.startswith(ENV_PREFIXES) and not SECRET.search(name):
            env[name] = value
    maps = read(base/'maps')
    libs = sorted({os.path.basename(p) for p in re.findall(r'(/\S+)$', maps, re.M) if LIBS.search(os.path.basename(p))})
    proton_root = re.search(r'(/\S+)/files/(?:lib|bin)', maps)
    proton_dir = env.get('PROTONPATH') or (proton_root.group(1) if proton_root else '')
    ntsync = eventfd = 0
    for candidate in [pid] + [p for p in pids() if read(PROC/str(p)/'comm').strip() == 'wineserver']:
        try:
            for fd in os.listdir(PROC/str(candidate)/'fd'):
                try:
                    link = os.readlink(PROC/str(candidate)/'fd'/fd)
                except OSError:
                    continue
                ntsync += 'ntsync' in link
                eventfd += 'eventfd' in link
        except OSError:
            pass
    out = {'pid': pid, 'comm': read(base/'comm').strip(), 'ntsync_fds': ntsync, 'eventfd_fds': eventfd,
           'sync': 'ntsync' if ntsync else 'esync' if eventfd > 50 else 'fsync or none'}
    if env:
        out['env'] = env
    if libs:
        out['libs'] = libs
        out['mangohud_loaded'] = any('mangohud' in l.lower() for l in libs)
        out['afmf_loaded'] = any('afmf' in l.lower() for l in libs)
    if proton_dir:
        out['proton_dir'] = proton_dir
        out['proton_version'] = read(Path(proton_dir)/'version').strip().split(' ')[-1]
    return out


def kernel_log(start, end):
    text = run(['journalctl', '-k', '--since', f'@{int(start)}', '--until', f'@{int(end) + 2}', '-o', 'short-iso', '--no-pager'], timeout=20)
    keep = re.compile(r'NVRM|Xid|nv_drm|nvidia|Out of memory|oom-kill|mce:|segfault|split lock|ntsync|amdgpu', re.I)
    return '\n'.join(l for l in text.splitlines() if keep.search(l))


# ---------------------------------------------------------------- sampler

GPU_FIELDS = ['utilization.gpu', 'utilization.memory', 'memory.used', 'memory.total', 'temperature.gpu', 'power.draw',
              'clocks.gr', 'clocks.mem', 'pstate', 'fan.speed', 'clocks_event_reasons.hw_slowdown',
              'clocks_event_reasons.hw_thermal_slowdown', 'clocks_event_reasons.sw_power_cap',
              'clocks_event_reasons.sw_thermal_slowdown']
GPU_COLUMNS = ['gpu_util', 'gpu_mem_util', 'vram_used', 'vram_total', 'gpu_temp', 'gpu_w', 'gpu_clk', 'gpu_mem_clk',
               'gpu_pstate', 'gpu_fan', 'thr_hw', 'thr_hw_thermal', 'thr_sw_power', 'thr_sw_thermal']
COLUMNS = ['t', 'pid', 'cpu_total', 'cpu_cores', 'cpu_mhz_mean', 'cpu_mhz_max', 'cpu_w', 'cpu_temp', 'nvme_temp',
           *GPU_COLUMNS, 'proc_vram', 'rss_mb', 'threads', 'fds', 'io_read_mb', 'io_write_mb', 'psi_cpu_ms',
           'psi_mem_ms', 'psi_io_ms', 'mem_avail_mb', 'swap_used_mb', 'top_threads', 'rtt_ms', 'rttvar_ms',
           'retrans', 'cache_mb']


class GpuStream:
    """One long-lived nvidia-smi; a silent or missing one gives empty columns."""

    def __init__(self):
        self.latest, self.seen, self.proc, self.restarts = None, 0.0, None, 0
        self.start()

    def start(self):
        try:
            self.proc = subprocess.Popen(['nvidia-smi', f'--query-gpu={",".join(GPU_FIELDS)}', '--format=csv,noheader,nounits',
                                          '-lms', str(max(100, int(INTERVAL * 1000)))],
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        except OSError:
            self.proc = None
            return
        self.seen = time.monotonic()
        threading.Thread(target=self.pump, args=(self.proc,), daemon=True).start()

    def pump(self, proc):
        for line in proc.stdout:
            parts = [p.strip() for p in line.split(',')]
            if len(parts) == len(GPU_FIELDS):
                self.latest, self.seen = parts, time.monotonic()

    def values(self):
        if self.proc and time.monotonic() - self.seen > max(5, 5 * INTERVAL):
            self.latest = None
            self.stop()
            if self.restarts < 1:
                self.restarts += 1
                self.start()
        if not self.latest:
            return [''] * len(GPU_FIELDS)
        return ['1' if v == 'Active' else '0' if v == 'Not Active' else '' if v.startswith('[') else v for v in self.latest]

    def stop(self):
        if self.proc:
            self.proc.kill()
            self.proc = None


class Sampler:
    def __init__(self, pid, path):
        self.pid, self.n = pid, 0
        self.out = open(path, 'a', buffering=1)
        if self.out.tell() == 0:
            self.out.write(','.join(COLUMNS) + '\n')
        self.gpu = GpuStream()
        self.prev = {}
        self.hwmon = {read(d/'name').strip(): d for d in sorted((SYS/'class/hwmon').glob('hwmon*'))}
        self.slow = {'proc_vram': '', 'rtt': ('', '', ''), 'cache': ''}
        self.cpu_seconds = time.process_time()

    def delta(self, key, value, now):
        old = self.prev.get(key)
        self.prev[key] = (value, now)
        if old is None or now <= old[1]:
            return None
        return (value - old[0]) / (now - old[1])

    def cpu(self, now):
        total, cores = '', []
        for line in read(PROC/'stat').splitlines():
            if not line.startswith('cpu'):
                break
            name, *nums = line.split()
            nums = [int(x) for x in nums[:8]]
            busy_rate = self.delta(name + ':busy', sum(nums) - nums[3] - nums[4], now)
            all_rate = self.delta(name + ':all', sum(nums), now)
            pct = '' if not all_rate else f'{100 * busy_rate / all_rate:.0f}'
            if name == 'cpu':
                total = pct
            else:
                cores.append(pct)
        return total, '|'.join(cores)

    def threads(self, now):
        usage = []
        try:
            tids = os.listdir(PROC/str(self.pid)/'task')
        except OSError:
            return '', ''
        for tid in tids:
            stat = read(PROC/str(self.pid)/'task'/tid/'stat')
            close = stat.rfind(')')
            fields = stat[close + 2:].split()
            if close < 0 or len(fields) < 13:
                continue
            rate = self.delta(f't{tid}', int(fields[11]) + int(fields[12]), now)
            if rate:
                usage.append((100 * rate / TICKS, stat[stat.find('(') + 1:close]))
        usage.sort(reverse=True)
        return str(len(tids)), '|'.join(f'{name.replace("|", "").replace(",", "")}:{pct:.0f}' for pct, name in usage[:5])

    def psi(self, kind, now):
        found = re.search(r'^some .*total=(\d+)', read(PROC/'pressure'/kind), re.M)
        rate = self.delta('psi' + kind, int(found.group(1)), now) if found else None
        return '' if rate is None else f'{rate / 1000:.1f}'

    def temp(self, chip):
        raw = read(self.hwmon[chip]/'temp1_input').strip() if chip in self.hwmon else ''
        return f'{int(raw) / 1000:.0f}' if raw.isdigit() else ''

    def slow_sources(self):
        if self.n % 5 == 0:
            best = None
            for chunk in re.split(r'\n(?=\S)', run(['ss', '-tinH', 'dport', '=', f':{PORT}'], timeout=2)):
                rtt = re.search(r'\brtt:([\d.]+)/([\d.]+)', chunk)
                if rtt:
                    idle = int((re.search(r'lastrcv:(\d+)', chunk) or [0, 10**9])[1])
                    retrans = (re.search(r'retrans:\d+/(\d+)', chunk) or [0, '0'])[1]
                    if best is None or idle < best[0]:
                        best = (idle, rtt.group(1), rtt.group(2), retrans)
            self.slow['rtt'] = best[1:] if best else ('', '', '')
        if self.n % 10 == 0:
            apps = run(['nvidia-smi', '--query-compute-apps=pid,used_memory', '--format=csv,noheader,nounits'], timeout=3)
            found = re.search(rf'^{self.pid}, (\d+)', apps, re.M)
            self.slow['proc_vram'] = found.group(1) if found else ''
        if self.n % 60 == 0:
            size = 0
            for root, _, files in os.walk(CACHE_DIR):
                for name in files:
                    try:
                        size += os.lstat(os.path.join(root, name)).st_size
                    except OSError:
                        pass
            self.slow['cache'] = str(size // 2**20)

    def tick(self):
        now = time.monotonic()
        base = PROC/str(self.pid)
        total, cores = self.cpu(now)
        freqs = [int(v) / 1000 for v in (read(p).strip() for p in (SYS/'devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_cur_freq')) if v.isdigit()]
        energy = read(SYS/'class/powercap/intel-rapl:0/energy_uj').strip()
        watts = self.delta('rapl', int(energy), now) if energy.isdigit() else None
        status = read(base/'status')
        rss = re.search(r'VmRSS:\s+(\d+)', status)
        io = dict(re.findall(r'^(\w+): (\d+)', read(base/'io'), re.M))
        try:
            fds = str(len(os.listdir(base/'fd')))
        except OSError:
            fds = ''
        meminfo = dict(re.findall(r'^(\w+):\s+(\d+)', read(PROC/'meminfo'), re.M))
        count, top = self.threads(now)
        self.slow_sources()
        mb = lambda key, src: str(int(src[key]) // 2**20) if key in src else ''
        row = [f'{time.time():.3f}', str(self.pid), total, cores,
               f'{sum(freqs) / len(freqs):.0f}' if freqs else '', f'{max(freqs):.0f}' if freqs else '',
               f'{watts / 1e6:.1f}' if watts and watts > 0 else '', self.temp('k10temp'), self.temp('nvme'),
               *self.gpu.values(), self.slow['proc_vram'], str(int(rss.group(1)) // 1024) if rss else '', count, fds,
               mb('read_bytes', io), mb('write_bytes', io), self.psi('cpu', now), self.psi('memory', now), self.psi('io', now),
               str(int(meminfo['MemAvailable']) // 1024) if 'MemAvailable' in meminfo else '',
               str((int(meminfo.get('SwapTotal', 0)) - int(meminfo.get('SwapFree', 0))) // 1024) if meminfo else '',
               top, *self.slow['rtt'], self.slow['cache']]
        self.out.write(','.join(row) + '\n')
        self.n += 1

    def close(self):
        self.gpu.stop()
        self.out.close()
        return time.process_time() - self.cpu_seconds


# ---------------------------------------------------------------- one session

def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=1, sort_keys=True) + '\n')


def record(launch):
    """Record one session. Returns the session directory, or None when no game started."""
    started = time.time()
    session = SESSIONS/time.strftime('%Y%m%d-%H%M%S', time.localtime(started))
    session.mkdir(parents=True, mode=0o700)
    INCOMING.mkdir(parents=True, exist_ok=True)
    meta = {'schema': 1, 'start': started, 'tz_offset_s': time.localtime(started).tm_gmtoff, 'settings': capture_settings()}
    position = log_position()
    ini = filtered_ini()
    if ini:
        (session/'config.ini').write_text(ini)
    if launch:
        subprocess.Popen(LAUNCH, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, start_new_session=True)
    pid = wait_for_game(START_WAIT)
    if not pid:
        meta.update(end=time.time(), status='no-game')
        write_json(session/'meta.json', meta)
        notify('PoE2 recorder', f'The game did not start within {START_WAIT:.0f} s. Nothing was recorded.', 4)
        return None
    meta['game_start'] = time.time()
    sampler = Sampler(pid, session/'sampler.csv')
    process = {}
    while True:
        tick_start = time.monotonic()
        if not alive(pid):
            pid = wait_for_game(RESTART_WAIT)
            if not pid:
                break
            sampler.pid = pid
            meta['game_restarts'] = meta.get('game_restarts', 0) + 1
        if sampler.n in (1, 10, 60):
            process.update(capture_process(pid))
        sampler.tick()
        time.sleep(max(0, INTERVAL - (time.monotonic() - tick_start)))
    ended = time.time()
    meta.update(end=ended, process=process, samples=sampler.n, recorder_cpu_s=round(sampler.close(), 2))

    events, crits, truncated = read_events(position)
    with open(session/'events.jsonl', 'w') as out:
        for event in events:
            out.write(json.dumps(event) + '\n')
    kinds = [e['kind'] for e in events]
    last_start = max((i for i, k in enumerate(kinds) if k == 'start'), default=0)
    meta['exit'] = 'graceful' if 'exit_graceful' in kinds[last_start:] else 'not graceful'
    meta['log_truncated'] = truncated
    meta['crit_counts'] = dict(sorted(crits.items(), key=lambda kv: -kv[1])[:20])
    kernel = kernel_log(started, ended)
    if kernel:
        (session/'kernel.log').write_text(kernel + '\n')

    frames = [frame_log_info(p) for p in collect_frames(session, started)]
    meta['frames'] = sum(f[0] for f in frames)
    meta['frame_seconds'] = round(sum(f[1] for f in frames), 1)
    played = ended - meta['game_start']
    if played < MIN_SECONDS:
        meta['status'] = 'short'
        notify('PoE2 recorder', f'Session lasted {played:.0f} s: too short to measure.', 2)
    elif meta['frame_seconds'] < MIN_SECONDS:
        meta['status'] = 'no-frames'
        notify('PoE2 recorder', 'Session was not measured: MangoHud wrote no frame log. '
               'Check that Lutris still has MANGOHUD=1 for PoE2 (run: gamelog install-env).', 4)
    else:
        meta['status'] = 'ok'
    write_json(session/'meta.json', meta)
    return session


def prune(now=None, frame_days=30, detail_days=180, cap_bytes=5 * 2**30):
    """Old frame logs go first, then old detail; summaries stay."""
    now = now or time.time()
    sessions = sorted(p for p in SESSIONS.iterdir() if p.is_dir()) if SESSIONS.exists() else []

    def age_days(session):
        try:
            return (now - time.mktime(time.strptime(session.name, '%Y%m%d-%H%M%S'))) / 86400
        except ValueError:
            return 0

    for session in sessions:
        if age_days(session) > frame_days:
            shutil.rmtree(session/'frames', ignore_errors=True)
        if age_days(session) > detail_days:
            for path in session.iterdir():
                if path.name not in ('meta.json', 'summary.json'):
                    shutil.rmtree(path) if path.is_dir() else path.unlink()
    size = lambda: sum(f.stat().st_size for s in sessions for f in s.rglob('*') if f.is_file())
    for session in sessions[:-1]:
        if size() <= cap_bytes:
            break
        shutil.rmtree(session/'frames', ignore_errors=True)


MANGO_TEMPLATE = """# Written by gamelog install-env. Per-frame log for the PoE2 session recorder.
fps_only
position=top-right
font_size=16
background_alpha=0.3
toggle_hud=Shift_R+F12
autostart_log=1
log_interval=0
log_versioning
output_folder={incoming}
"""


def install_env():
    """Point PoE2 at a MangoHud config that logs every frame. The one setting gamelog writes."""
    from . import lutris_env
    config = lutris_config()
    if not config:
        raise SystemExit(f'no Lutris config for {LUTRIS_SLUG} in {LUTRIS_GAMES}')
    INCOMING.mkdir(parents=True, exist_ok=True)
    MANGO_CONF.parent.mkdir(parents=True, exist_ok=True)
    MANGO_CONF.write_text(MANGO_TEMPLATE.format(incoming=INCOMING))
    text = config.read_text()
    new = lutris_env.set_env(lutris_env.set_env(text, 'MANGOHUD', '1'), 'MANGOHUD_CONFIGFILE', str(MANGO_CONF))
    if new != text:
        config.write_text(new)
    print(f'{config.name}: MANGOHUD=1, MANGOHUD_CONFIGFILE={MANGO_CONF}')
