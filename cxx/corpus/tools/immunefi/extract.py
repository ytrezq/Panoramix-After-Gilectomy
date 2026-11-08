# Extract the bounty list embedded in Immunefi's Next.js page (RSC payload).
import json, re, sys
html = open(sys.argv[1], encoding='utf-8').read()
chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', html, re.S)
text = ''.join(json.loads('"' + c + '"') for c in chunks)
# find the array that holds the bounty objects: look for '"slug":' occurrences and their enclosing objects
best = None
for m in re.finditer(r'\[\{"contentfulId":', text):
    start = m.start()
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == '[' or ch == '{': depth += 1
        elif ch == ']' or ch == '}':
            depth -= 1
            if depth == 0:
                frag = text[start:i+1]
                try:
                    arr = json.loads(frag)
                except Exception:
                    break
                if isinstance(arr, list) and arr and isinstance(arr[0], dict) and 'slug' in arr[0] and (best is None or len(arr) > len(best)):
                    best = arr
                break
print(len(text), 'chars of payload;', len(best) if best else 0, 'bounties')
json.dump(best, open(sys.argv[2], 'w'), indent=1)
if best:
    print(sorted(best[0].keys()))
