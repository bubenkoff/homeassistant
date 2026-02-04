#!/bin/bash
# Boiler & Automation Report
# Usage: ./scripts/boiler_report.sh [hours]
# Default: last 24 hours

HOURS=${1:-24}
TOKEN=$(ssh homeassistant.local "cat /data/.ha_token")
BASE="http://homeassistant.local:8123/api"
START=$(python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(hours=${HOURS})).strftime('%Y-%m-%dT%H:%M:%S+00:00'))")
END=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S+00:00'))")

echo "╔══════════════════════════════════════════════════╗"
echo "║         BOILER REPORT (last ${HOURS}h)               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# --- Current state ---
echo "━━━ ПОТОЧНИЙ СТАН ━━━"
ssh homeassistant.local "curl -s 'http://otgw.local/api/v1/otgw/otmonitor' 2>/dev/null" | python3 -c "
import sys,json
data = json.load(sys.stdin)
vals = {item['name']: item['value'] for item in data.get('otmonitor', [])}
flame = '🔥 ON' if vals.get('flamestatus') == 'On' else '⬛ OFF'
print(f\"  Flame:      {flame}\")
print(f\"  Water:      {vals.get('boilertemperature')}°C (setpoint: {vals.get('controlsetpoint')}°C)\")
print(f\"  Return:     {vals.get('returnwatertemperature')}°C\")
print(f\"  MaxMod:     {vals.get('maxrelmodlvl')}%\")
print(f\"  CH:         {vals.get('chmodus')}\")
"

echo ""
echo "━━━ КІМНАТИ ━━━"
curl -s "${BASE}/states" -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for c in ['living_room','kitchen','master_bedroom','kateryna_s_bedroom','margarya_s_bedroom','alexander_s_bedroom','bathroom']:
    for e in data:
        if e['entity_id'] == f'climate.{c}':
            t = e['attributes'].get('temperature')
            cur = e['attributes'].get('current_temperature')
            action = e['attributes'].get('hvac_action','?')
            demand = round(t - cur, 1) if t and cur else 0
            icon = '🟢' if demand <= 0 else ('🟡' if demand <= 0.5 else '🔴')
            name = c.replace('_s_bedroom',' BR').replace('_',' ').title()
            print(f'  {icon} {name:<18} {cur}°C → {t}°C  (demand: {demand:+.1f}°C) [{action}]')
"

echo ""
echo "━━━ FLAME ЦИКЛИ ━━━"
curl -s "${BASE}/history/period/${START}?filter_entity_id=binary_sensor.opentherm_boiler_flame,sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting&minimal_response" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
from datetime import datetime
from collections import defaultdict

data = json.load(sys.stdin)
if len(data) < 2:
    print('  Недостатньо даних')
    sys.exit()

mod_timeline = [(h.get('last_changed','')[:19], h.get('state','?')) for h in data[1]]

flame_on = None
cycles = []
for h in data[0]:
    t = h.get('last_changed','')[:19]
    s = h.get('state','')
    if s == 'on':
        flame_on = t
    elif s == 'off' and flame_on:
        mod = '?'
        for mt, mv in mod_timeline:
            if mt <= flame_on:
                mod = mv
        try:
            t1 = datetime.fromisoformat(flame_on)
            t2 = datetime.fromisoformat(t)
            dur = (t2-t1).total_seconds()
            cycles.append((flame_on, dur, mod))
        except:
            pass
        flame_on = None

total = len(cycles)
if total == 0:
    print('  Немає циклів')
    sys.exit()

durations = [d for _, d, _ in cycles]
short = sum(1 for d in durations if d < 30)
medium = sum(1 for d in durations if 30 <= d < 120)
normal = sum(1 for d in durations if 120 <= d < 600)
long_ = sum(1 for d in durations if d >= 600)
total_on = sum(durations)
total_time = (datetime.fromisoformat(cycles[-1][0]) - datetime.fromisoformat(cycles[0][0])).total_seconds()
duty = (total_on / total_time * 100) if total_time > 0 else 0

print(f'  Всього циклів:    {total}')
print(f'  Середній цикл:    {sum(durations)/total:.0f}с ({sum(durations)/total/60:.1f} хв)')
print(f'  Мін / Макс:       {min(durations):.0f}с / {max(durations):.0f}с')
print(f'  Duty cycle:       {duty:.1f}%')
print()
print(f'  Розподіл:')
print(f'    ✗ <30с (коротке):  {short:>3} ({short/total*100:.0f}%)')
print(f'    ~ 30с-2хв:        {medium:>3} ({medium/total*100:.0f}%)')
print(f'    ✓ 2-10хв:         {normal:>3} ({normal/total*100:.0f}%)')
print(f'    ✓ >10хв:          {long_:>3} ({long_/total*100:.0f}%)')

# Stats by modulation
by_mod = defaultdict(list)
for _, dur, mod in cycles:
    try:
        by_mod[float(mod)].append(dur)
    except:
        pass

print()
print('  По рівню модуляції:')
print(f'  {\"MaxMod\":>8}  {\"Циклів\":>7}  {\"Сер.\":>7}  {\"Мін\":>6}  {\"<30с\":>5}')
for mod in sorted(by_mod.keys()):
    ds = by_mod[mod]
    avg = sum(ds)/len(ds)
    sh = sum(1 for d in ds if d < 30)
    print(f'  {mod:>7.0f}%  {len(ds):>7}  {avg:>5.0f}с  {min(ds):>5.0f}с  {sh:>5}')
" 2>/dev/null

echo ""
echo "━━━ АВТОМАТИЗАЦІЯ ━━━"
curl -s "${BASE}/states/automation.boiler_modulation_control" -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
d = json.load(sys.stdin)
print(f\"  State:          {d['state']}\")
print(f\"  Last triggered: {d['attributes'].get('last_triggered', 'never')[:19]}\")" 2>/dev/null

curl -s "${BASE}/logbook?entity=automation.boiler_modulation_control" -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
from datetime import datetime, timedelta
data = json.load(sys.stdin)
triggers = [e for e in data if 'triggered' in e.get('message','')]
print(f'  Triggers today:   {len(triggers)}')
if triggers:
    times = [e.get('when','') for e in triggers]
    # Count triggers by source
    by_source = {}
    for e in triggers:
        src = e.get('message','unknown')
        by_source[src] = by_source.get(src, 0) + 1
    for src, cnt in by_source.items():
        print(f'    {src}: {cnt}')
" 2>/dev/null

echo ""
echo "━━━ MaxMod ЗМІНИ ━━━"
curl -s "${BASE}/history/period/${START}?filter_entity_id=sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting&minimal_response&no_attributes" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
data = json.load(sys.stdin)
if data and data[0]:
    changes = [h for h in data[0] if h.get('state') not in ['unavailable','unknown']]
    print(f'  Зміни за період: {len(changes)}')
    print()
    for h in changes:
        print(f\"    {h.get('last_changed','')[:19]}  →  {h.get('state')}%\")
" 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
