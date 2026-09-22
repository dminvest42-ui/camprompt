#!/usr/bin/env python3
"""Проверка относительных ссылок и якорей в документации CamPrompt.

Правила slug'а GitHub: в нижний регистр → выкинуть пунктуацию (кроме дефиса
и подчёркивания) → КАЖДЫЙ пробел заменить на дефис (подряд идущие не
схлопываются). Внутри code-span'ов ссылки не ищем."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent
if not (root / "Package.swift").exists():
    root = pathlib.Path("/home/olya/projects/teleprompter")

FILES = [root / "README.md", root / "CLAUDE.md", root / "CHANGELOG.md"]
FILES += sorted((root / "docs").glob("*.md"))
FILES = [f for f in FILES if f.exists()]

# ../../releases/latest и подобное — github-относительные адреса репозитория
GITHUB_REL = re.compile(r'^\.\./\.\./(releases|issues|actions|wiki|pulls)')

def strip_code(text: str) -> str:
    text = re.sub(r'```.*?```', '', text, flags=re.S)
    return re.sub(r'`[^`\n]*`', '', text)

def slugify(heading: str) -> str:
    s = re.sub(r'^#+\s*', '', heading).strip().lower()
    s = re.sub(r'[`*_\[\]]', '', s)                 # разметка
    s = ''.join(c for c in s if c.isalnum() or c in ' -_')
    return s.replace(' ', '-')

anchors = {}
for f in FILES:
    anchors[f.resolve()] = {slugify(l) for l in f.read_text().splitlines() if l.startswith('#')}

problems, checked = [], 0
for f in FILES:
    body = strip_code(f.read_text())
    for m in re.finditer(r'\[([^\]]+)\]\(([^)\s]+)\)', body):
        label, target = m.group(1), m.group(2)
        if target.startswith(('http://', 'https://', 'mailto:')) or GITHUB_REL.match(target):
            continue
        checked += 1
        path_part, _, anchor = target.partition('#')
        if not path_part:
            if anchor not in anchors[f.resolve()]:
                problems.append(f"{f.name}: [{label}](#{anchor}) → нет такого заголовка в этом файле")
            continue
        resolved = (f.parent / path_part).resolve()
        if not resolved.exists():
            problems.append(f"{f.name}: [{label}]({target}) → файла нет")
        elif anchor and resolved in anchors and anchor not in anchors[resolved]:
            problems.append(f"{f.name}: [{label}]({target}) → якоря нет в {resolved.name}")
    for m in re.finditer(r'\[\[([^\]]+)\]\]', body):
        problems.append(f"{f.name}: [[{m.group(1)}]] → wikilink, GitHub его не отрендерит")

print(f"файлов: {len(FILES)}, проверено ссылок: {checked}")
if problems:
    print("ПРОБЛЕМЫ:")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print("OK — все относительные ссылки и якоря разрешаются")
