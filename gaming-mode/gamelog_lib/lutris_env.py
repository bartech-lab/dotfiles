"""Read and set one environment variable in a Lutris game config.

Lutris passes only system: env: to the game; game: env: is ignored.
"""
import re


def _env_span(text):
    system = re.search(r'^system:\n((?:[ \t].*\n?)*)', text, re.M)
    if not system:
        return None, None
    env = re.search(r'^  env:\n((?:    .*\n?)*)', system.group(1), re.M)
    if not env:
        return system, None
    return system, (system.start(1) + env.start(1), system.start(1) + env.end(1))


def get_env(text, name):
    span = _env_span(text)[1]
    if not span:
        return None
    found = re.search(rf"^    {re.escape(name)}: '?([^'\n]*)'?[ \t]*$", text[span[0]:span[1]], re.M)
    return found.group(1) if found else None


def set_env(text, name, value):
    """Return text with name set to value under system: env:. value None removes it."""
    if text and not text.endswith('\n'):
        text += '\n'
    system, span = _env_span(text)
    entry = '' if value is None else f"    {name}: '{value}'\n"
    if span:
        body = re.sub(rf"^    {re.escape(name)}: .*\n?", '', text[span[0]:span[1]], flags=re.M)
        return text[:span[0]] + entry + body + text[span[1]:]
    if value is None:
        return text
    if system:
        return text[:system.start(1)] + '  env:\n' + entry + text[system.start(1):]
    return text + 'system:\n  env:\n' + entry
