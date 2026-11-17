"""Builds assets/i18n/<lang>.json for the app: every tr('...') text in lib/, translated from the website's
own catalogs (../../mockify/translations/<lang>.json) and, for texts only the app has, from app_texts.json.

    python tool/make_i18n.py            # writes the files and lists what is still missing
"""
import io
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
SITE = os.path.join(APP, '..', '..', 'mockify', 'translations')
LANGS = ['uz', 'ru', 'tr', 'ar', 'hi', 'tg', 'ky', 'zh']
LIT = re.compile(r"""tr\(\s*'((?:[^'\\]|\\.)*)'|tr\(\s*"((?:[^"\\]|\\.)*)\"""")


def keys():
    out = set()
    for dp, _, fs in os.walk(os.path.join(APP, 'lib')):
        for f in fs:
            if f.endswith('.dart'):
                for m in LIT.finditer(io.open(os.path.join(dp, f), encoding='utf-8').read()):
                    k = m.group(1) if m.group(1) is not None else m.group(2)
                    out.add(k.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n'))
    return sorted(out)


def main():
    ks = keys()
    own = json.load(io.open(os.path.join(HERE, 'app_texts.json'), encoding='utf-8')) if os.path.exists(os.path.join(HERE, 'app_texts.json')) else {}
    os.makedirs(os.path.join(APP, 'assets', 'i18n'), exist_ok=True)
    missing = {}
    for lang in LANGS:
        site = {}
        p = os.path.join(SITE, f'{lang}.json')
        if os.path.exists(p):
            site = json.load(io.open(p, encoding='utf-8'))
        out = {}
        for k in ks:
            v = (own.get(k) or {}).get(lang) or site.get(k)
            if v:
                out[k] = v
            else:
                missing.setdefault(k, []).append(lang)
        io.open(os.path.join(APP, 'assets', 'i18n', f'{lang}.json'), 'w', encoding='utf-8').write(
            json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True))
    print(f'{len(ks)} texts; missing in some language: {len(missing)}')
    io.open(os.path.join(HERE, 'i18n_missing.txt'), 'w', encoding='utf-8').write('\n'.join(missing))


if __name__ == '__main__':
    main()
