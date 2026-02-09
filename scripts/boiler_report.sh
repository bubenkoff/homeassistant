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
curl -s "${BASE}/history/period/${START}?filter_entity_id=binary_sensor.opentherm_boiler_flame,sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting,binary_sensor.opentherm_boiler_hot_water&minimal_response" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
from datetime import datetime
from collections import defaultdict

data = json.load(sys.stdin)
if len(data) < 2:
    print('  Недостатньо даних')
    sys.exit()

# Find flame, modulation and DHW data by entity_id
flame_data = None
mod_data = None
dhw_data = None

for d in data:
    if d and len(d) > 0:
        eid = d[0].get('entity_id', '')
        if 'flame' in eid:
            flame_data = d
        elif 'modulation' in eid:
            mod_data = d
        elif 'hot_water' in eid:
            dhw_data = d

if not flame_data:
    print('  Немає даних flame')
    sys.exit()

mod_timeline = [(h.get('last_changed','')[:19], h.get('state','?')) for h in (mod_data or [])]

# Build DHW periods
dhw_periods = []
if dhw_data:
    dhw_on = None
    for h in dhw_data:
        t = h.get('last_changed','')[:19]
        s = h.get('state','')
        if s == 'on':
            dhw_on = t
        elif s == 'off' and dhw_on:
            dhw_periods.append((dhw_on, t))
            dhw_on = None

def is_dhw_active(start_time, end_time):
    for dhw_start, dhw_end in dhw_periods:
        if dhw_start <= start_time <= dhw_end or dhw_start <= end_time <= dhw_end:
            return True
        if start_time <= dhw_start <= end_time:
            return True
    return False

flame_on = None
cycles = []
for h in flame_data:
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
            is_dhw = is_dhw_active(flame_on, t)
            cycles.append((flame_on, dur, mod, is_dhw))
        except:
            pass
        flame_on = None

total = len(cycles)
if total == 0:
    print('  Немає циклів')
    sys.exit()

# Separate DHW and CH cycles
dhw_cycles = [(t, d, m) for t, d, m, is_dhw in cycles if is_dhw]
ch_cycles = [(t, d, m) for t, d, m, is_dhw in cycles if not is_dhw]

durations = [d for _, d, _, _ in cycles]
total_on = sum(durations)
total_time = (datetime.fromisoformat(cycles[-1][0]) - datetime.fromisoformat(cycles[0][0])).total_seconds()
duty = (total_on / total_time * 100) if total_time > 0 else 0

print(f'  Всього циклів:    {total} (DHW: {len(dhw_cycles)}, CH: {len(ch_cycles)})')
print(f'  Середній цикл:    {sum(durations)/total:.0f}с ({sum(durations)/total/60:.1f} хв)')
print(f'  Мін / Макс:       {min(durations):.0f}с / {max(durations):.0f}с')
print(f'  Duty cycle:       {duty:.1f}%')

# CH-only stats (what we care about for short cycling)
if ch_cycles:
    ch_durations = [d for _, d, _ in ch_cycles]
    ch_short = sum(1 for d in ch_durations if d < 30)
    ch_medium = sum(1 for d in ch_durations if 30 <= d < 120)
    ch_normal = sum(1 for d in ch_durations if 120 <= d < 600)
    ch_long = sum(1 for d in ch_durations if d >= 600)
    ch_total = len(ch_cycles)

    print()
    print(f'  ─── CH (опалення) ───')
    print(f'  Циклів: {ch_total}, Середній: {sum(ch_durations)/ch_total:.0f}с ({sum(ch_durations)/ch_total/60:.1f} хв)')
    print(f'  Розподіл:')
    print(f'    ✗ <30с (коротке):  {ch_short:>3} ({ch_short/ch_total*100:.0f}%)')
    print(f'    ~ 30с-2хв:        {ch_medium:>3} ({ch_medium/ch_total*100:.0f}%)')
    print(f'    ✓ 2-10хв:         {ch_normal:>3} ({ch_normal/ch_total*100:.0f}%)')
    print(f'    ✓ >10хв:          {ch_long:>3} ({ch_long/ch_total*100:.0f}%)')

# DHW stats
if dhw_cycles:
    dhw_durations = [d for _, d, _ in dhw_cycles]
    print()
    print(f'  ─── DHW (гаряча вода) ───')
    print(f'  Циклів: {len(dhw_cycles)}, Середній: {sum(dhw_durations)/len(dhw_cycles):.0f}с')

# Stats by modulation (CH only)
if ch_cycles:
    by_mod = defaultdict(lambda: {'ch': [], 'dhw': []})
    for _, dur, mod, is_dhw in cycles:
        try:
            key = 'dhw' if is_dhw else 'ch'
            by_mod[float(mod)][key].append(dur)
        except:
            pass

    print()
    print('  По рівню модуляції (CH):')
    print(f'  {\"MaxMod\":>8}  {\"Циклів\":>7}  {\"Сер.\":>7}  {\"Мін\":>6}  {\"<30с\":>5}')
    for mod in sorted(by_mod.keys()):
        ds = by_mod[mod]['ch']
        if ds:
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
curl -s "${BASE}/history/period/${START}?filter_entity_id=sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting,climate.living_room,climate.kitchen,climate.master_bedroom,climate.kateryna_s_bedroom,climate.margarya_s_bedroom,climate.alexander_s_bedroom,climate.bathroom&minimal_response" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
data = json.load(sys.stdin)

# Find modulation and climate data
mod_data = None
climate_data = {}

for d in data:
    if d and len(d) > 0:
        eid = d[0].get('entity_id', '')
        if 'modulation' in eid:
            mod_data = d
        elif 'climate.' in eid:
            climate_data[eid] = d

if not mod_data:
    print('  Немає даних')
    sys.exit(0)

changes = [h for h in mod_data if h.get('state') not in ['unavailable','unknown']]
print(f'  Зміни за період: {len(changes)}')
print()
print(f'    {\"Час\":<20} {\"MaxMod\":>8}  {\"Demand\":>7}  Статус')
print(f'    {\"─\"*20} {\"─\"*8}  {\"─\"*7}  {\"─\"*15}')

for h in changes:
    change_time = h.get('last_changed','')[:19]
    mod_val = h.get('state', '?')

    # Find max demand at this time
    max_demand = None
    for eid, history in climate_data.items():
        last_state = None
        for ch in history:
            t = ch.get('last_changed','')[:19]
            if t <= change_time:
                last_state = ch
            else:
                break
        if last_state:
            attrs = last_state.get('attributes', {})
            target = attrs.get('temperature')
            current = attrs.get('current_temperature')
            if target and current:
                demand = round(target - current, 1)
                if max_demand is None or demand > max_demand:
                    max_demand = demand

    # Determine expected modulation
    demand_str = f'{max_demand:+.1f}°C' if max_demand is not None else '?'

    try:
        mod_float = float(mod_val)
        if max_demand is not None:
            if max_demand <= 0:
                expected = 100
            elif max_demand <= 0.5:
                expected = 30
            elif max_demand <= 1.0:
                expected = 40
            elif max_demand <= 2.0:
                expected = 50
            else:
                expected = 80

            if mod_float >= 99 and expected == 100:
                status = '✓ reset'
            elif abs(mod_float - expected) <= 1:
                status = '✓'
            else:
                status = f'⚠ exp:{expected}%'
        else:
            status = '? no data'
    except:
        status = '?'

    print(f'    {change_time:<20} {mod_val:>7}%  {demand_str:>7}  {status}')
" 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
