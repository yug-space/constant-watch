"""Read-only, evidence-backed day and week reviews. No inferred completed work."""
from collections import Counter
from datetime import date, timedelta
import json
import re

from .recall import evidence, NOTICE


def plain(value):
    return re.sub(r'[\[\]<>`*_#]', '', ' '.join(value.split()))[:180]


def review(store, start: str, end: str) -> dict:
    first, last = date.fromisoformat(start), date.fromisoformat(end)
    if first > last or (last - first).days > 30:
        raise ValueError('Choose an ordered date range of at most 31 days.')
    start, end = first.isoformat(), last.isoformat()
    with store.connect() as db:
        rows = [dict(r) for r in db.execute(
            'SELECT * FROM observations WHERE day BETWEEN ? AND ? ORDER BY julianday(captured_at), id', (start, end))]
    days = Counter(r['day'] for r in rows)
    apps = Counter(r['app_id'] for r in rows)
    names = {r['app_id']: r['app_name'] for r in rows}
    groups = {}
    for row in rows:
        topics = json.loads(row['topics'])
        # Only an explicit project name may merge documents across applications.
        project = next((t for t in topics if t.get('basis') == 'Explicit project name in captured text'), None)
        key = ('project', project['key']) if project else ('document', row['app_id'], row['source_url'] or row['document_name'] or row['window_title'])
        group = groups.setdefault(key, {'title': project['label'] if project else row['document_name'] or row['window_title'] or row['app_name'],
            'basis': 'Suggested group · matching project name' if project else 'Same source document or window', 'rows': []})
        group['rows'].append(row)
    highlights = []
    for group in groups.values():
        sources, seen = [], set()
        for row in reversed(group['rows']):
            source = evidence(row, ['next', 'decision', 'deadline'])
            key = (source['app_id'], source['quote'])
            if key not in seen and source['quote']:
                sources.append(source); seen.add(key)
            if len(sources) == 3:
                break
        if sources:
            highlights.append({'id': group['rows'][0]['id'], 'title': group['title'], 'basis': group['basis'],
                'captures': len(group['rows']), 'apps': list(dict.fromkeys(r['app_name'] for r in group['rows'])),
                'last_seen': group['rows'][-1]['captured_at'], 'sources': sources})
    highlights.sort(key=lambda h: (-h['captures'], -h['id']))
    total_groups = len(highlights)
    highlights = highlights[:12]
    draft = [f'# Review · {start}' + (f' to {end}' if start != end else ''),
        '> Draft from captured text. Verify before sharing. Screen content does not prove completed work.', '', '## Context to report']
    for item in highlights:
        source = item['sources'][0]
        draft.append(f"- {plain(item['title'])} · {plain(', '.join(item['apps']))} — [source #{source['id']}]({source['deep_link']})")
        draft.extend('  > ' + line for line in plain(source['quote']).splitlines())
    if not highlights:
        draft.append('No captured evidence in this date range.')
    draft += ['', '## Completed outcomes', '- [Add confirmed outcomes; these cannot be established from screen captures alone.]',
              '', '## Next priorities', '- [Add your priorities.]', '', '## Blockers', '- [Confirm any blockers.]']
    return {'start': start, 'end': end, 'notice': NOTICE,
        'captures': len(rows), 'app_count': len(apps), 'days_with_captures': len(days),
        'days': [{'day': (first + timedelta(days=i)).isoformat(), 'captures': days[(first + timedelta(days=i)).isoformat()]} for i in range((last-first).days+1)],
        'apps': [{'app_id': key, 'app_name': names[key], 'captures': count} for key, count in apps.most_common()],
        'highlights': highlights, 'total_groups': total_groups, 'draft': '\n'.join(draft) + '\n'}
