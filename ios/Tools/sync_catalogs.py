#!/usr/bin/env python3
"""Recopie les catalogues de l'app Flutter (fournisseurs et agents intégrés) en JSON
pour l'app iOS native : ios/NexoraKit/Sources/NexoraKit/Resources/{providers,agents}.json.

Usage : python3 ios/Tools/sync_catalogs.py [--check]
--check : échoue si les fichiers ne sont pas à jour (utilisé par la CI).
"""
import re, json, sys, os
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = os.path.join(root, 'app', 'lib', 'data') + '/'
out_dir = os.path.join(root, 'ios', 'NexoraKit', 'Sources', 'NexoraKit', 'Resources')
check = '--check' in sys.argv
stale = []

def emit(name, data):
    path = os.path.join(out_dir, name)
    text = json.dumps(data, ensure_ascii=False, indent=1) + '\n'
    old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
    if old != text:
        stale.append(name)
        if not check:
            open(path, 'w', encoding='utf-8').write(text)

def dart_strings(s, env):
    # concatenate adjacent dart string literals, handling escapes and $var interpolation
    out = ''
    for m in re.finditer(r"'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"", s):
        t = m.group(1) if m.group(1) is not None else m.group(2)
        t = t.replace("\\'", "'").replace('\\"', '"').replace('\\n', '\n').replace('\\$', '$')
        t = re.sub(r'\$\{?(_\w+)\}?', lambda k: env.get(k.group(1), k.group(0)), t)
        out += t
    return out
# providers
txt = open(src+'providers_catalog.dart', encoding='utf-8').read()
body = txt[txt.index('const List<ProviderDef> providersCatalog'):txt.index('ProviderDef customProviderTemplate')]
provs = []
for blk in re.split(r'\n  ProviderDef\(', body)[1:]:
    p = {}
    fields = re.findall(r'\n    (\w+):\s*([\s\S]*?),(?=\n    \w+:|\n  \),)', blk + '\n  ),')
    for k, v in fields:
        v = v.strip()
        if k in ('id','name','emoji','baseUrl','keyUrl','docsUrl','description','chatPath','freeModelSuffix'):
            p[k] = dart_strings(v, {})
        elif k == 'color': p[k] = v
        elif k in ('free','needsKey','local','usesGitHubToken'): p[k] = v == 'true'
        elif k == 'kind': p[k] = v.split('.')[-1]
        elif k == 'listing': p[k] = v.split('.')[-1]
        elif k == 'defaultModels': p[k] = [dart_strings(x, {}) for x in re.findall(r"'[^']*'", v)]
        elif k == 'extraHeaders': p[k] = dict(re.findall(r"'([^']*)':\s*'([^']*)'", v))
        else: print('??', k, file=sys.stderr)
    provs.append(p)
emit('providers.json', provs)
# agents
txt = open(src+'agents_catalog.dart', encoding='utf-8').read()
env = {}
for m in re.finditer(r"const (_\w+) =\s*([\s\S]*?);\n", txt):
    env[m.group(1)] = dart_strings(m.group(2), env)
agents = []
start = txt.index('final List<Agent> builtinAgents')
for blk in re.split(r'\n  _a\(', txt[start:])[1:]:
    blk = blk[:blk.index('\n  ),')]
    tools = []
    tm = re.search(r'tools:\s*\[([^\]]*)\]', blk)
    if tm:
        tools = re.findall(r"'([^']*)'", tm.group(1)); blk = blk[:tm.start()]
    # split args at top level: lines starting with 4 spaces and a string literal begin args
    args = re.split(r",\n    (?=['\"])", '\n    ' + blk.strip().rstrip(','))
    args = [dart_strings(a, env) for a in args]
    if len(args) != 6: print('bad', args[:2], len(args), file=sys.stderr); continue
    id_, emoji, name, cat, desc, prompt = args
    agents.append(dict(id='builtin:'+id_, emoji=emoji, name=name, category=cat, description=desc, systemPrompt=prompt, tools=tools))
emit('agents.json', agents)
print(f"{len(provs)} fournisseurs, {len(agents)} agents" + (f" ; à jour : {', '.join(stale)}" if stale else " ; rien à changer"))
if check and stale:
    print("Catalogues iOS en retard sur l'app Flutter : lancez python3 ios/Tools/sync_catalogs.py", file=sys.stderr)
    sys.exit(1)
