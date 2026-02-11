# Project Instructions

## Git

- **Always `git pull`** at the start of work to ensure the local repo is up to date.

## Changelog

- **Always read `CHANGELOG.md`** at the start of work to understand recent changes.
- **Always update `CHANGELOG.md`** after making any changes to the project.
- Use the `## [Unreleased]` section for new entries.
- Format: `- <short description of what was changed and why>`
- When a release is made, move unreleased entries under a dated heading `## [YYYY-MM-DD]`.

## Boiler Control System

### Architecture

```
Netatmo TRVs (7 кімнат) → встановлюють setpoint (цільова температура води)
Boiler Modulation Control → обмежує max modulation (потужність котла)
OpenTherm Gateway (OTGW) → передає команди котлу через opentherm_gw.set_max_modulation
```

Netatmo керує **коли** гріти (setpoint), автоматизація керує **як сильно** (modulation).

### Кімнати (Netatmo TRVs)

| Entity                          | Назва              |
|---------------------------------|--------------------|
| `climate.living_room`           | Вітальня           |
| `climate.kitchen`               | Кухня              |
| `climate.master_bedroom`        | Спальня батьків    |
| `climate.kateryna_s_bedroom`    | Спальня Катерини   |
| `climate.margarya_s_bedroom`    | Спальня Маргариті  |
| `climate.alexander_s_bedroom`   | Спальня Олександра |
| `climate.bathroom`              | Ванна              |

### Автоматизація: Boiler Modulation Control

**Файл:** `automations.yaml`, id: `boiler_modulation_control`

**Тригери:**
- Старт Home Assistant
- Кожну 1 хвилину (time_pattern)
- Зміна стану будь-якого climate entity (з затримкою 30с)

**Логіка:** Розраховує `max_heat_demand` — максимальну різницю (target - current) серед усіх кімнат, та встановлює відповідний рівень модуляції:

| Demand (°C)  | Max Modulation | Змінна           |
|--------------|----------------|------------------|
| ≤ 0          | 30%            | mod_level_low    |
| ≤ 1.0        | 30%            | mod_level_low    |
| ≤ 1.5        | 40%            | mod_level_med    |
| ≤ 3.0        | 50%            | mod_level_high   |
| > 3.0        | 80%            | mod_level_max    |

**Умова:** Команда надсилається тільки якщо нове значення відрізняється від поточного.

### Ключові сенсори

| Entity                                                                    | Опис                          |
|---------------------------------------------------------------------------|-------------------------------|
| `sensor.opentherm_gateway_otgw_otgw_max_rel_modulation_level_setting`     | Поточний ліміт модуляції      |
| `binary_sensor.opentherm_boiler_flame`                                    | Стан полум'я (on/off)         |
| `binary_sensor.opentherm_boiler_hot_water`                                | Режим ГВП (DHW)               |

### Діагностика: boiler_report.sh

**Файл:** `scripts/boiler_report.sh [hours]` (за замовчуванням 24 години)

**Вимоги:** SSH доступ до `homeassistant.local`, HA API token з `/data/.ha_token`, доступ до `otgw.local`.

**Секції звіту:**
1. **Поточний стан** — flame, температура води, return, modulation, CH режим (з OTGW API)
2. **Кімнати** — поточна/цільова температура, demand, hvac_action для кожної кімнати
3. **Flame цикли** — аналіз циклів горіння з розділенням на CH/DHW:
   - Розподіл по тривалості: <30с (короткі), 30с-2хв, 2-10хв, >10хв
   - Статистика по рівню модуляції
   - Duty cycle
4. **Автоматизація** — стан, останній тригер, кількість тригерів за день по джерелу
5. **MaxMod зміни** — історія змін модуляції з валідацією відповідності demand

### Відомі проблеми та налаштування

- Модуляція 20% — занадто низька, котел не може підтримувати полум'я
- Модуляція 30% — оптимальна для низького demand, 0 коротких циклів
- Модуляція 40% — може спричиняти короткі цикли при низькому demand
- Короткий цикл = flame < 30 секунд (зношує котел)
- Ціль: мінімізувати короткі цикли CH, тримати duty cycle стабільним
