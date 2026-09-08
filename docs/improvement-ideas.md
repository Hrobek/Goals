# Nápady na zlepšení

Backlog nápadů nad rámec verze 1.1.0. Zaškrtávej, co je hotové. Seřazeno podle poměru přínos/práce.
Stav při vzniku: větev `feature/habits`, po commitu `31f0cba` (Today day strip, iCloud sync status, backup, weekly review).

## Velké kameny (nejvíc posunou produkt)

- [x] **Apple Watch app + komplikace.** Odškrtnutí ze zápěstí, ranní/večerní komplikace s "3 ze 7", nezávislé na telefonu. Největší jednotlivá chybějící věc pro habit tracker. Zároveň největší práce - spíš samostatný milník. — Hotovo ve větvi `feature/habits`: standalone watchOS app `GoalsWatch Watch App` (Today list, odškrtávání přes sdílený `HabitLogger`/`ProgressLogger`, haptika), `GoalsWatchWidgetExtension` s komplikacemi (`accessoryCircular`/`Inline`/`Corner`/`Rectangular`, "3 / 7", interaktivní check-off), CloudKit sync na data + WatchConnectivity most na identitu/nastavení. Watch app i iOS schéma se čistě builduje (watchOS 26.5 simulátor). Watch ikona zatím převzatá z iPhone appky.
- [ ] **Apple Health integrace.** Číst kroky, workouty, mindful minutes, váhu, spánek a automaticky plnit habit/goal ("Uběhnout 100 km" z workoutů, "Meditovat" z mindful minutes). Sníží tření u nejčastěji zakládaných cílů.
- [x] **Streak freeze / grace day.** Zasloužená banka mražáků (Duolingo styl): +1 za každých 7 splněných dní v sérii (Pro 5), strop 1 (Pro 3), globální na účet. Free aplikuje ručně tlačítkem "Použít mražák" na detailu, Pro automaticky přes smiřovací průchod + undo. Kryje jen 1 zmeškaný den na incident, jen day-based rozvrhy, avoid návyky ne. Model `StreakFreeze` (synced), `FreezeLedger`/`FreezeBank` (App Group, device-local jako Vacation), `StreakFreezeEngine`. Vyžaduje deploy Production CloudKit schématu.
- [ ] **Live Activity + interaktivní notifikace.** Odškrtnutí přímo z notifikace bez otevření appky. Live Activity na zamykačce pro dnešní progres nebo blížící se deadline. iOS 18 Controls API do Ovládacího centra na one-tap check-in.

## Střední (dobrý poměr)

### Today obrazovka
- [ ] Denní progress ring nahoře ("4 ze 7 hotovo") místo jen seznamu.
- [ ] Swipe akce na řádku: check in / přeskočit dnes / odložit.
- [ ] Ruční řazení (drag) přímo v Today, ne jen podle priority.

### Stats / insighty
- [ ] Roční "year in pixels" mřížka (GitHub contribution graf) za celý rok, ne jen měsíční.
- [ ] "Nejsilnější den v týdnu", "obvykle odškrtáváš kolem 20:00" - a z toho odvodit chytřejší čas připomínky.
- [ ] Osobní rekordy vytažené nahoru (nejdelší série vůbec, nejlepší měsíc).
- [ ] Export do CSV (do backupu i samostatně) - pro lidi, co trackují roky.

### Cíle a návyky
- [ ] Negativní / "quit" návyky ("žádný alkohol") s modelem "X dní čistých" místo série odškrtnutí.
- [ ] Opakující se cíle, co se samy resetují každé období (měsíční spořicí cíl, který začne znovu od nuly).
- [ ] Uložit si vlastní šablonu z existujícího cíle.
- [ ] Propojení cíl ↔ návyk ("Přečíst 12 knih" napojené na "Číst 20 min denně").
- [ ] Habit stacking pole ("po ranní kávě") jako textový cue u návyku.

### Sync
- [ ] Vacation mode synchronizovat přes iCloud (teď se nastaví na telefonu a iPad o něm neví - v kódu okomentované jako known limitation).

## Rychlé výhry

- [ ] Haptika při check-inu a extra odezva při překročení milníku série.
- [ ] Long-press na ikonu appky → Home Screen quick actions (rychlý check-in nejbližšího návyku, přidat cíl).
- [ ] Lock Screen / StandBy accessory widgety (jen kruh + číslo).
- [ ] Siri fráze nad rámec AppShortcuts ("zaloguj 5 km běh").
- [ ] "Naplánuj zítřek" / večerní recap jako volitelná notifikace.
- [ ] iPad: dvousloupcový layout místo roztažené iPhone verze.
- [ ] Sample data v onboardingu, ať si člověk appku prohlédne, než něco založí.

## Na zvážení

- [ ] Free trial u ročního předplatného (teď měsíc/rok/lifetime bez zkušebky).
- [ ] Family Sharing pro lifetime nákup.
- [ ] Kalendář: přidat deadline cíle do systémového Kalendáře.

## Doporučené pořadí

Do 1.2: **streak freeze**, **Health integrace**, **swipe akce + denní ring na Today**.
Watch app jako samostatný větší milník.
